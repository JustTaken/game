const std            = @import("std");

const _config        = @import("../../util/configuration.zig");
const _collections   = @import("../../collections/collections.zig");
const _io            = @import("../../io/io.zig");
const _platform      = @import("../../platform/platform.zig");

const _instance      = @import("instance.zig");
const _device        = @import("device.zig");
const _window        = @import("window.zig");
const _data          = @import("data.zig");

const Window         = _window.Window;
const Device         = _device.Device;
const Instance       = _instance.Instance;
const Data           = _data.Data;

const Platform       = _platform.Platform;
const ArrayList      = _collections.ArrayList;
const Io             = _io.Io;

const Allocator      = std.mem.Allocator;

const c              = _platform.c;
const configuration  = _config.Configuration;

pub const GraphicsPipeline = struct {
    handle:       c.VkPipeline,
    layout:       c.VkPipelineLayout,
    format:       c.VkSurfaceFormatKHR,
    render_pass:  c.VkRenderPass,
    depth_format: c.VkFormat,
    descriptor:   Descriptor,

    pub const Descriptor = struct {
        pools:     ArrayList(Pool),
        layouts:   ArrayList(c.VkDescriptorSetLayout),
        allocator: Allocator,
        size_each: u32,

        const Pool = struct {
            handle:                c.VkDescriptorPool,
            descriptor_sets:       ArrayList(c.VkDescriptorSet),
            descriptor_set_layout: c.VkDescriptorSetLayout,

            fn new(device: Device, allocator: Allocator, layout: c.VkDescriptorSetLayout, size: u32) !Pool {
                const handle = try device.create_descriptor_pool(.{
                    .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                    .poolSizeCount = 1,
                    .pPoolSizes    = &.{
                        .type            = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .descriptorCount = size,
                    },
                    .maxSets       = size,
                });

                return .{
                    .handle                = handle,
                    .descriptor_sets       = try ArrayList(c.VkDescriptorSet).init(allocator, size),
                    .descriptor_set_layout = layout,
                };
            }

            fn allocate(self: *Pool, device: Device, count: u32, allocator: Allocator) ![]const c.VkDescriptorSet {
                if (self.descriptor_sets.items.len + count >= self.descriptor_sets.capacity) {
                    return error.NoSpace;
                }

                const layouts = try allocator.alloc(c.VkDescriptorSetLayout, count);
                defer allocator.free(layouts);

                @memset(layouts, self.descriptor_set_layout);

                const descriptor_sets = try device.allocate_descriptor_sets(.{
                    .sType              = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                    .descriptorPool     = self.handle,
                    .descriptorSetCount = count,
                    .pSetLayouts        = layouts.ptr,
                }, allocator);

                defer allocator.free(descriptor_sets);
                const len = self.descriptor_sets.items.len;

                try self.descriptor_sets.push_slice(descriptor_sets);

                return self.descriptor_sets.items[len..descriptor_sets.len + len];
            }

            fn destroy(self: *Pool, device: Device) void {
                // device.free_descriptor_sets(self.handle, self.descriptor_sets.items.len, self.descriptor_sets.items) catch {};
                device.destroy_descriptor_pool(self.handle);
                self.descriptor_sets.deinit();
            }
        };

        fn new(size_each: u32, allocator: Allocator) !Descriptor {
            return .{
                .pools     = try ArrayList(Pool).init(allocator, 1),
                .layouts   = try ArrayList(c.VkDescriptorSetLayout).init(allocator, 1),
                .size_each = size_each,
                .allocator = allocator,
            };
        }

        fn add_layout(self: *Descriptor, layout: c.VkDescriptorSetLayout) !usize {
            const id = self.layouts.items.len;
            try self.layouts.push(layout);

            return id;
        }

        pub fn allocate(self: *Descriptor, device: Device, layout_id: usize, count: u32) ![]const c.VkDescriptorSet {
            const descriptor_sets = blk: for (0..self.pools.items.len) |i| {
                const sets = self.pools.items[i].allocate(device, count, self.allocator) catch {
                    continue;
                };

                break :blk sets;
            } else {
                try self.pools.push(try Pool.new(device, self.allocator, self.layouts.items[layout_id], self.size_each));
                break :blk try self.pools.items[self.pools.items.len - 1].allocate(device, count, self.allocator);
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

            self.layouts.deinit();
            self.pools.deinit();
        }
    };

    pub fn new(device: Device, instance: Instance, window: Window, allocator: Allocator) !GraphicsPipeline {
        const vert_code = try Io.read_file("assets/shader/vert.spv", allocator);

        defer allocator.free(vert_code);

        const frag_code = try Io.read_file("assets/shader/frag.spv", allocator);

        defer allocator.free(frag_code);

        const vert_module = try device.create_shader_module(.{
            .sType    = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pCode    = @as([*]const u32, @ptrCast(@alignCast(vert_code))),
            .codeSize = vert_code.len,
        });

        defer device.destroy_shader_module(vert_module);

        const frag_module = try device.create_shader_module(.{
            .sType    = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = frag_code.len,
            .pCode    = @as([*]const u32, @ptrCast(@alignCast(frag_code))),
        });

        defer device.destroy_shader_module(frag_module);

        const shader_stage_infos = &[_]c.VkPipelineShaderStageCreateInfo {
            .{
                .sType  = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage  = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = vert_module,
                .pName  = "main",
            },
            .{
                .sType  = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage  = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = frag_module,
                .pName  = "main",
            },
        };

        const dynamic_states = &[_]c.VkDynamicState { c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
            .sType             = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pDynamicStates    = dynamic_states.ptr,
            .dynamicStateCount = dynamic_states.len,
        };

        const vertex_input_state_info: c.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pVertexBindingDescriptions      = &Data.Model.Vertex.binding_description,
            .vertexBindingDescriptionCount   = 1,
            .pVertexAttributeDescriptions    = Data.Model.Vertex.attribute_descriptions.ptr,
            .vertexAttributeDescriptionCount = Data.Model.Vertex.attribute_descriptions.len,
        };

        const input_assembly_state_info: c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport_state_info: c.VkPipelineViewportStateCreateInfo = .{
            .sType         = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports    = &.{
                .x        = 0.0,
                .y        = 0.0,
                .width    = @floatFromInt(window.width),
                .height   = @floatFromInt(window.height),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            },
            .scissorCount = 1,
            .pScissors     = &.{
                .offset = .{.x = 0, .y = 0},
                .extent = .{
                    .width  = window.width,
                    .height = window.height,
                }
            },
        };

        const rasterizer_state_info: c.VkPipelineRasterizationStateCreateInfo = .{
            .sType                   = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .cullMode                = c.VK_CULL_MODE_BACK_BIT,
            .frontFace               = c.VK_FRONT_FACE_CLOCKWISE,
            .polygonMode             = c.VK_POLYGON_MODE_LINE,
            .depthBiasEnable         = c.VK_FALSE,
            .depthClampEnable        = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .lineWidth               = 1.0,
            .depthBiasClamp          = 0.0,
            .depthBiasConstantFactor = 0.0,
        };

        const multisampling_state_info: c.VkPipelineMultisampleStateCreateInfo = .{
            .sType                 = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .pSampleMask           = null,
            .alphaToOneEnable      = c.VK_FALSE,
            .sampleShadingEnable   = c.VK_FALSE,
            .rasterizationSamples  = c.VK_SAMPLE_COUNT_1_BIT,
            .alphaToCoverageEnable = c.VK_FALSE,
            .minSampleShading      = 1.0,
        };

        const color_blend_state_info: c.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOp         = c.VK_LOGIC_OP_COPY,
            .logicOpEnable   = c.VK_FALSE,
            .blendConstants  = .{ 0.0, 0.0, 0.0, 0.0 },
            .attachmentCount = 1,
            .pAttachments    = &.{
                .blendEnable         = c.VK_FALSE,
                .colorWriteMask      = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                .colorBlendOp        = c.VK_BLEND_OP_ADD,
                .alphaBlendOp        = c.VK_BLEND_OP_ADD,
            },
        };

        const depth_stencil_state_info: c.VkPipelineDepthStencilStateCreateInfo = .{
            .sType                 = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .maxDepthBounds        = 1.0,
            .minDepthBounds        = 0.0,
            .depthCompareOp        = c.VK_COMPARE_OP_LESS,
            .depthTestEnable       = c.VK_TRUE,
            .depthWriteEnable      = c.VK_TRUE,
            .stencilTestEnable     = c.VK_FALSE,
            .depthBoundsTestEnable = c.VK_FALSE,
        };

        const descriptor_set_layout = try device.create_descriptor_set_layout(.{
            .sType        = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 1,
            .pBindings    = &[_]c.VkDescriptorSetLayoutBinding {
                .{
                    .binding            = 0,
                    .stageFlags         = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .descriptorType     = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount    = 1,
                    .pImmutableSamplers = null,
                },
            }
        });

        const layout = try device.create_pipeline_layout(.{
            .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pSetLayouts            = &[_] c.VkDescriptorSetLayout {descriptor_set_layout, descriptor_set_layout},
            .setLayoutCount         = 2,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges    = null,
        });

        var descriptor = try Descriptor.new(16, allocator);

        _ = try descriptor.add_layout(descriptor_set_layout);

        const formats = try instance.get_physical_device_surface_formats(device.physical_device, window.surface, allocator);

        defer allocator.free(formats);

        const format = for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) break format;
        } else formats[0];

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
        } else return error.DepthFormat;

        const render_pass = try device.create_render_pass(.{
            .sType           = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 2,
            .pAttachments    = &[_] c.VkAttachmentDescription {
                .{
                    .format         = format.format,
                    .samples        = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp         = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp        = c.VK_ATTACHMENT_STORE_OP_STORE,
                    .finalLayout    = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                    .initialLayout  = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .stencilLoadOp  = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                },
                .{
                    .format         = depth_format,
                    .samples        = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp         = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp        = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .finalLayout    = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                    .initialLayout  = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .stencilLoadOp  = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                }
            },
            .subpassCount          = 1,
            .pSubpasses            = &.{
                .pipelineBindPoint    = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .colorAttachmentCount = 1,
                .pColorAttachments    = &.{
                    .attachment = 0,
                    .layout     = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                },
                .pDepthStencilAttachment = &.{
                    .attachment = 1,
                    .layout     = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                },
            },
            .dependencyCount       = 1,
            .pDependencies         = &.{
                .srcSubpass    = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass    = 0,
                .srcAccessMask = 0,
                .srcStageMask  = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .dstStageMask  = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            },
        });

        const handle = try device.create_graphics_pipeline(.{
            .sType               = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = shader_stage_infos.len,
            .pStages             = shader_stage_infos.ptr,
            .pVertexInputState   = &vertex_input_state_info,
            .pInputAssemblyState = &input_assembly_state_info,
            .pViewportState      = &viewport_state_info,
            .pRasterizationState = &rasterizer_state_info,
            .pMultisampleState   = &multisampling_state_info,
            .pDynamicState       = &dynamic_state_info,
            .pColorBlendState    = &color_blend_state_info,
            .pDepthStencilState  = &depth_stencil_state_info,
            .layout              = layout,
            .renderPass          = render_pass,
            .subpass             = 0,
            .basePipelineHandle  = null,
        });

        return .{
            .handle       = handle,
            .layout       = layout,
            .format       = format,
            .render_pass  = render_pass,
            .depth_format = depth_format,
            .descriptor   = descriptor,
        };
    }

    pub fn destroy(self: *GraphicsPipeline, device: Device) void {
        self.descriptor.destroy(device);
        device.destroy_pipeline_layout(self.layout);
        device.destroy_render_pass(self.render_pass);
        device.destroy_pipeline(self.handle);
    }
};
