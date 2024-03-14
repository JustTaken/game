const std = @import("std");

const _config = @import("../../util/configuration.zig");
const _collections = @import("../../util/collections.zig");
const _io = @import("../../util/io.zig");
const _platform = @import("../../platform/platform.zig");

const _instance = @import("instance.zig");
const _device = @import("device.zig");
const _window = @import("window.zig");
const _data = @import("data.zig");

const Window = _window.Window;
const Device = _device.Device;
const Instance = _instance.Instance;
const Data = _data.Data;

const Platform = _platform.Platform;
const ArrayList = _collections.ArrayList;
const Io = _io.Io;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const GraphicsPipeline = struct {
    handle: c.VkPipeline,
    layout: c.VkPipelineLayout,
    render_pass: c.VkRenderPass,
    format: c.VkSurfaceFormatKHR,
    depth_format: c.VkFormat,
    descriptor: Descriptor,

    pub const Descriptor = struct {
        pools: ArrayList(Pool),
        layouts: ArrayList(c.VkDescriptorSetLayout),
        size_each: u32,

        arena: ArenaAllocator,

        const Pool = struct {
            handle: c.VkDescriptorPool,
            descriptor_set_layout: c.VkDescriptorSetLayout,
            descriptor_sets: ArrayList(c.VkDescriptorSet),

            fn new(device: Device, allocator: Allocator, layout: c.VkDescriptorSetLayout, size: u32) !Pool {
                const handle = try device.create_descriptor_pool(.{
                    .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                    .poolSizeCount = 1,
                    .pPoolSizes = &.{
                        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .descriptorCount = size,
                    },
                    .maxSets = size,
                });

                return .{
                    .handle = handle,
                    .descriptor_set_layout = layout,
                    .descriptor_sets = try ArrayList(c.VkDescriptorSet).init(allocator, size),
                };
            }

            fn allocate(self: *Pool, device: Device, count: u32, allocator: Allocator) ![]const c.VkDescriptorSet {
                if (!(self.descriptor_sets.items.len + count < self.descriptor_sets.capacity)) {
                    return error.NoSpace;
                }

                var layouts = ArrayList(c.VkDescriptorSetLayout).init(allocator, count) catch |e| {
                    logger.log(.Error, "Failed to create layouts array", .{});

                    return e;
                };

                for (0..count) |_| {
                    layouts.push(self.descriptor_set_layout) catch |e| {
                        logger.log(.Error, "Could not insert layou in descriptor set layouts array", .{});

                        return e;
                    };
                }

                defer layouts.deinit();

                const descriptor_sets = device.allocate_descriptor_sets(.{
                    .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                    .descriptorPool = self.handle,
                    .descriptorSetCount = count,
                    .pSetLayouts = layouts.items.ptr,
                }, allocator) catch |e| {
                    logger.log(.Error, "Failed to create descriptor sets", .{});

                    return e;
                };

                for (0..count) |i| {
                    self.descriptor_sets.push(descriptor_sets[i]) catch |e| {
                        logger.log(.Error, "Failed to insert element in descriptor sets array", .{});

                        return e;
                    };
                }

                return descriptor_sets;
            }

            fn destroy(self: *Pool, device: Device) void {
                device.free_descriptor_sets(self.handle, self.descriptor_sets.items.len, self.descriptor_sets.items) catch {};
            }
        };

        fn new(size_each: u32) !Descriptor {
            var arena = ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();

            return .{
                .pools = try ArrayList(Pool).init(allocator, 1),
                .layouts = try ArrayList(c.VkDescriptorSetLayout).init(allocator, 1),
                .size_each = size_each,
                .arena = arena,
            };
        }

        fn add_layout(self: *Descriptor, layout: c.VkDescriptorSetLayout) !usize {
            const id = self.layouts.items.len;
            try self.layouts.push(layout);

            return id;
        }

        pub fn allocate(self: *Descriptor, device: Device, layout_id: usize, count: u32) ![]const c.VkDescriptorSet {
            const allocator = self.arena.allocator();
            const descriptor_sets = blk: for (0..self.pools.items.len) |i| {
                const sets = self.pools.items[i].allocate(device, count, allocator) catch {
                    continue;
                };

                break :blk sets;
            } else {
                try self.pools.push(try Pool.new(device, allocator, self.layouts.items[layout_id], self.size_each));
                break :blk try self.pools.items[self.pools.items.len - 1].allocate(device, count, allocator);
            };

            return descriptor_sets;
        }

        fn destroy(self: *Descriptor, device: Device) void {
            for (0..self.pools.items.len) |i| {
                self.pools.items[i].destroy(device);
            }

            for (self.layouts.items) |layout| {
                device.destroy_descriptor_set_layout(layout);
            }

            _ = self.arena.deinit();
        }
    };

    pub fn new(device: Device, instance: Instance, window: Window, allocator: Allocator) !GraphicsPipeline {
        const vert_code = Io.read_file("assets/vert.spv", allocator) catch |e| {
            logger.log(.Error, "Could not read vertex shader byte code", .{});

            return e;
        };

        const frag_code = Io.read_file("assets/frag.spv", allocator) catch |e| {
            logger.log(.Error, "Could not read fragment shader byte code", .{});

            return e;
        };

        const vert_module = device.create_shader_module(.{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = vert_code.len,
            .pCode = @as([*]const u32, @ptrCast(@alignCast(vert_code))),
        }) catch |e| {
            logger.log(.Error, "Failed to create vertex shader module", .{});

            return e;
        };

        defer device.destroy_shader_module(vert_module);

        const frag_module = device.create_shader_module(.{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = frag_code.len,
            .pCode = @as([*]const u32, @ptrCast(@alignCast(frag_code))),
        }) catch |e| {
            logger.log(.Error, "Failed to create fragment shader module", .{});

            return e;
        };

        defer device.destroy_shader_module(frag_module);

        const shader_stage_infos = &[_]c.VkPipelineShaderStageCreateInfo {
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = vert_module,
                .pName = "main",
            },
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = frag_module,
                .pName = "main",
            },
        };

        const dynamic_states = &[_]c.VkDynamicState { c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = dynamic_states.ptr,
        };

        const vertex_input_state_info: c.VkPipelineVertexInputStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &Data.Model.Vertex.binding_description,
            .vertexAttributeDescriptionCount = Data.Model.Vertex.attribute_descriptions.len,
            .pVertexAttributeDescriptions = Data.Model.Vertex.attribute_descriptions.ptr,
        };

        const input_assembly_state_info: c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport_state_info: c.VkPipelineViewportStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &.{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(window.extent.width)),
                .height = @as(f32, @floatFromInt(window.extent.height)),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            },
            .pScissors = &.{
                .offset = .{.x = 0, .y = 0},
                .extent = .{
                    .width = window.extent.width,
                    .height = window.extent.height,
                }
            },
        };

        const rasterizer_state_info: c.VkPipelineRasterizationStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = c.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
        };

        const multisampling_state_info: c.VkPipelineMultisampleStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = c.VK_FALSE,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.VK_FALSE,
            .alphaToOneEnable = c.VK_FALSE,
        };

        const color_blend_state_info: c.VkPipelineColorBlendStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &.{
                .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                .blendEnable = c.VK_FALSE,
                .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .colorBlendOp = c.VK_BLEND_OP_ADD,
                .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .alphaBlendOp = c.VK_BLEND_OP_ADD,
            },
            .blendConstants = .{ 0.0, 0.0, 0.0, 0.0 },
        };

        const depth_stencil_state_info: c.VkPipelineDepthStencilStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.VK_FALSE,
            .stencilTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
        };

        const descriptor_set_layout = try device.create_descriptor_set_layout(.{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 1,
            .pBindings = &[_]c.VkDescriptorSetLayoutBinding {
                .{
                    .binding = 0,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = 1,
                    .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .pImmutableSamplers = null,
                },
            }
        });

        const layout = device.create_pipeline_layout(.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 2,
            .pSetLayouts = &[_] c.VkDescriptorSetLayout {descriptor_set_layout, descriptor_set_layout},
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        }) catch |e| {
            logger.log(.Error, "Failed to create pipeline layout", .{});

            return e;
        };

        var descriptor = Descriptor.new(16) catch |e| {
            logger.log(.Error, "Failed to create descriptor pool handle", .{});

            return e;
        };

        _ = try descriptor.add_layout(descriptor_set_layout);

        const formats = instance.get_physical_device_surface_formats(device.physical_device, window.surface, allocator) catch |e| {
            logger.log(.Error, "Failed to list surface formats", .{});

            return e;
        };

        const format = blk: for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                break :blk format;
            }
        } else {
            logger.log(.Warn, "Could not find a good surface format falling back to first in list", .{});

            break :blk formats[0];
        };

        const depth_formats = [_] c.VkFormat {
            c.VK_FORMAT_D32_SFLOAT,
            c.VK_FORMAT_D32_SFLOAT_S8_UINT,
            c.VK_FORMAT_D24_UNORM_S8_UINT,
        };

        const flags = c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
        const depth_format = blk: for (depth_formats) |candidate| {
            const format_properties = instance.get_physical_device_format_properties(device.physical_device, candidate);
            if ((format_properties.linearTilingFeatures & flags) == flags or (format_properties.optimalTilingFeatures & flags) == flags) {
                break :blk candidate;
            }
        } else {
            logger.log(.Error, "Failed to find suitable depth format", .{});

            return error.DepthFormat;
        };

        const render_pass = device.create_render_pass(.{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 2,
            .pAttachments = &[_] c.VkAttachmentDescription {
                .{
                    .format = format.format,
                    .samples = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                    .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                },
                .{
                    .format = depth_format,
                    .samples = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                }
            },
            .subpassCount = 1,
            .pSubpasses = &.{
                .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .colorAttachmentCount = 1,
                .pColorAttachments = &.{
                    .attachment = 0,
                    .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                },
                .pDepthStencilAttachment = &.{
                    .attachment = 1,
                    .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                },
            },
            .dependencyCount = 1,
            .pDependencies = &.{
                .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass = 0,
                .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .srcAccessMask = 0,
                .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            },
        }) catch |e| {
            logger.log(.Error, "Failed to create render pass", .{});

            return e;
        };

        const handle = device.create_graphics_pipeline(.{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = shader_stage_infos.len,
            .pStages = shader_stage_infos.ptr,
            .pVertexInputState = &vertex_input_state_info,
            .pInputAssemblyState = &input_assembly_state_info,
            .pViewportState = &viewport_state_info,
            .pRasterizationState = &rasterizer_state_info,
            .pMultisampleState = &multisampling_state_info,
            .pDynamicState = &dynamic_state_info,
            .pColorBlendState = &color_blend_state_info,
            .pDepthStencilState = &depth_stencil_state_info,
            .layout = layout,
            .renderPass = render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
        }) catch |e| {
            logger.log(.Error, "Failed to create graphics pipeline", .{});

            return e;
        };

        return .{
            .handle = handle,
            .layout = layout,
            .render_pass = render_pass,
            .descriptor = descriptor,
            .format = format,
            .depth_format = depth_format,
        };
    }

    pub fn destroy(self: *GraphicsPipeline, device: Device) void {
        self.descriptor.destroy(device);
        device.destroy_pipeline_layout(self.layout);
        device.destroy_render_pass(self.render_pass);
        device.destroy_pipeline(self.handle);
    }
};
