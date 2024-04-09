const std = @import("std");

const _configuration = @import("../../util/configuration.zig");
const _collections = @import("../../collections/collections.zig");
const _math = @import("../../math/math.zig");
const _platform = @import("../../platform/platform.zig");
const _mesh = @import("../../assets/mesh.zig");
const _container = @import("../../container/container.zig");
const _font = @import("../../assets/font.zig");
const _image = @import("../../assets/image.zig");

const _command_pool = @import("command_pool.zig");
const _device = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");

const Device = _device.Device;
const CommandPool = _command_pool.CommandPool;
const Descriptor = _graphics_pipeline.GraphicsPipeline.Descriptor;

const ArrayList = _collections.ArrayList;
const Allocator = std.mem.Allocator;
const Matrix = _math.Matrix;
const Container = _container.Container;
const Mesh = _mesh.Mesh;
const ObjectType = _mesh.Mesh.Type;
const PngImage = _image.PngImage;
const FontManager = _font.FontManager;

const c = _platform.c;

pub const Data = struct {
    global: Global,
    models: []Model,
    font: Font,
    allocator: Allocator,

    const Global = struct {
        buffer: Buffer,
        mapped: *Uniform,
        descriptor_set: c.VkDescriptorSet,

        fn new(
            device: Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
        ) !Global {
            const buffer = try Buffer.new(device, command_pool, Uniform, null,
                . {
                    .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    .len = 1,
                });

            var mapped: *Uniform = undefined;

            try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
            mapped.model = Matrix.scale(1.0, 1.0, 1.0);
            mapped.color = Matrix.scale(1.0, 1.0, 1.0);

            const descriptor_set = (try descriptor.allocate(device, .global, 1))[0];

            device.update_descriptor_sets(&.{
                .{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .dstSet = descriptor_set,
                    .dstBinding = 0,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .pBufferInfo = &.{
                        .buffer = buffer.handle,
                        .offset = 0,
                        .range = @sizeOf(Uniform),
                    },
                }
            });

            return .{
                .buffer = buffer,
                .mapped = mapped,
                .descriptor_set = descriptor_set,
            };
        }

        fn destroy(self: Global, device: Device) void {
            device.unmap_memory(self.buffer.memory);
            self.buffer.destroy(device);
        }
    };

    const Uniform = struct {
        model: [4][4]f32,
        color: [4][4]f32,
    };

    pub const Font = struct {
        glyphs: ArrayList(Glyph),
        texture: Texture,
        initialized: bool,

        const Glyph = struct {
            vertex: Buffer,
            index: Buffer,

            descriptor_set: c.VkDescriptorSet,
            mapped: *Uniform,
            uniform: Buffer,

            fn new(
                device: Device,
                command_pool: CommandPool,
                descriptor: *Descriptor,
                allocator: Allocator,
                vertex: []const [3]f32,
                texture_coords: []const [2]f32,
                index: []const u16,
                uniform: Uniform,
            ) !Glyph {
                var mapped: *Uniform = undefined;
                const buffer = try Buffer.new(device, command_pool, Uniform, null,
                    .{
                        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                        .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                        .len = 1,
                    });

                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.* = uniform;

                const descriptor_set = (try descriptor.allocate(device, .instance, 1))[0];
                device.update_descriptor_sets(&.{
                    .{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .dstSet = descriptor_set,
                        .dstBinding = 0,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .pBufferInfo = &.{
                            .buffer = buffer.handle,
                            .offset = 0,
                            .range = @sizeOf(Uniform),
                        },
                    },
                });

                const index_buffer = try Buffer.new(device, command_pool, u16, index,
                    .{
                        .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                        .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                        .len = 6,
                });

                const vertices = try allocator.alloc(Vertex, 4);
                defer allocator.free(vertices);
                for (vertices, 0..) |*v, i| {
                    v.* = .{
                        .position = vertex[i],
                        .texture = texture_coords[i],
                    };
                }

                const vertex_buffer = try Buffer.new(device, command_pool, Vertex, vertices,
                .{
                    .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .len = vertices.len,
                });

                return .{
                    .mapped = mapped,
                    .vertex = vertex_buffer,
                    .index = index_buffer,
                    .descriptor_set = descriptor_set,
                    .uniform = buffer,
                };
            }

            fn destroy(self: Glyph, device: Device) void {
                device.unmap_memory(self.uniform.memory);
                self.vertex.destroy(device);
                self.uniform.destroy(device);
                self.index.destroy(device);
            }
        };

        fn add_glyph(self: *Font, glyph: Glyph) !u16 {
            const id = self.glyphs.items.len;
            try self.glyphs.push(glyph);

            return @intCast(id);
        }

        fn new(
            device: Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
            font_manager: FontManager,
            allocator: Allocator
        ) !Font {
            const texture = try Texture.new(device, command_pool, descriptor, .{
                .format = c.VK_FORMAT_R8_UNORM,
                .pixels = font_manager.texture,
                .width = font_manager.width,
                .height = font_manager.height,
                .anisotropy = false,
            });

            return .{
                .texture = texture,
                .glyphs = try ArrayList(Glyph).init(allocator, 1),
                .initialized = true,
            };
        }

        fn destroy(self: Font, device: Device) void {
            for (self.glyphs.items) |glyph| {
                glyph.destroy(device);
            }

            self.texture.destroy(device);
        }
    };

    pub const Texture = struct {
        image: c.VkImage,
        image_memory: c.VkDeviceMemory,
        image_view: c.VkImageView,
        sampler: c.VkSampler,
        descriptor_set: c.VkDescriptorSet,

        const Configuration = struct {
            format: c.VkFormat,
            pixels: []const u8,
            width: u32,
            height: u32,
            anisotropy: bool,
        };

        fn new(
            device: Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
            config: Configuration,
        ) !Texture {
            const staging_buffer = try Buffer.new(device, command_pool, u8, null, .{
                .len = config.pixels.len,
                .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            });

            var destine: *u8 = undefined;
            try device.map_memory(staging_buffer.memory, u8, config.pixels.len, @ptrCast(&destine));

            @memcpy(@as([*]u8, @ptrCast(@alignCast(destine))), config.pixels);
            device.unmap_memory(staging_buffer.memory);

            const texture_image = try device.create_image(.{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                .imageType = c.VK_IMAGE_TYPE_2D,
                .extent = .{
                    .width = config.width,
                    .height = config.height,
                    .depth = 1,
                },
                .mipLevels = 1,
                .arrayLayers = 1,
                .format = config.format,
                .tiling = c.VK_IMAGE_TILING_OPTIMAL,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .flags = 0,
            });

            const mem_requirements = device.get_image_memory_requirements(texture_image);
            const memory_index = for (0..device.memory_properties.memoryTypeCount) |i| {
                if ((mem_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (device.memory_properties.memoryTypes[i].propertyFlags & c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) == c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
                    break i;
                }
            } else return error.NoMemoryRequirementsPassed;

            const texture_memory = try device.allocate_memory(.{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = mem_requirements.size,
                .memoryTypeIndex = @intCast(memory_index),
            });

            try device.bind_image_memory(texture_image, texture_memory);
            const barrier_command_buffer = try command_pool.allocate_command_buffer(device);
            device.cmd_pipeline_barrier(
            barrier_command_buffer,
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_TRANSFER_BIT, null, null, &.{
            .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .image = texture_image,
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .srcAccessMask = 0,
                .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
            }});
            try command_pool.free_command_buffer(device, barrier_command_buffer);

            const copy_command_buffer = try command_pool.allocate_command_buffer(device);
            device.cmd_copy_buffer_to_image(
                copy_command_buffer,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_COPY_BUFFER_TO_IMAGE_INFO_2,
                    .srcBuffer = staging_buffer.handle,
                    .dstImage = texture_image,
                    .dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    .regionCount = 1,
                    .pRegions = &.{
                        .sType = c.VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2,
                        .bufferOffset = 0,
                        .bufferRowLength = 0,
                        .bufferImageHeight = 0,
                        .imageSubresource = .{
                            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                            .mipLevel = 0,
                            .baseArrayLayer = 0,
                            .layerCount = 1,
                        },
                        .imageOffset = .{
                            .x = 0,
                            .y = 0,
                            .z = 0,
                        },
                        .imageExtent = .{
                            .width = config.width,
                            .height = config.height,
                            .depth = 1,
                        },
                    }
                }
            );

            try command_pool.free_command_buffer(device, copy_command_buffer);

            const second_barrier_command_buffer = try command_pool.allocate_command_buffer(device);
            device.cmd_pipeline_barrier(second_barrier_command_buffer,
                c.VK_PIPELINE_STAGE_TRANSFER_BIT,
                c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, null, null, &.{
                .{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                    .oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    .newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                    .image = texture_image,
                    .subresourceRange = .{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                    .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
                    .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
            }});
            try command_pool.free_command_buffer(device, second_barrier_command_buffer);

            staging_buffer.destroy(device);

            const texture_image_view = try device.create_image_view(.{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = texture_image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = config.format,
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                }
            });

            const texture_sampler = try device.create_sampler(.{
                .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                .magFilter = c.VK_FILTER_LINEAR,
                .minFilter = c.VK_FILTER_LINEAR,
                .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
                .anisotropyEnable = if (config.anisotropy) c.VK_TRUE else c.VK_FALSE,
                .maxAnisotropy = if (config.anisotropy) device.physical_device_properties.limits.maxSamplerAnisotropy else 1,
                .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
                .unnormalizedCoordinates = c.VK_FALSE,
                .compareEnable = c.VK_FALSE,
                .compareOp = c.VK_COMPARE_OP_ALWAYS,
                .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
                .mipLodBias = 0,
                .minLod = 0,
                .maxLod = 0,
            });

            const descriptor_set = (try descriptor.allocate(device, .model, 1))[0];

            device.update_descriptor_sets(&.{
                .{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .dstSet = descriptor_set,
                    .dstBinding = 0,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .pImageInfo = &.{
                        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                        .imageView = texture_image_view,
                        .sampler = texture_sampler,
                    },
                }
            });

            return .{
                .image = texture_image,
                .image_memory = texture_memory,
                .image_view = texture_image_view,
                .sampler = texture_sampler,
                .descriptor_set = descriptor_set,
            };
        }

        pub fn destroy(self: Texture, device: Device) void {
            device.destroy_image(self.image);
            device.free_memory(self.image_memory);
            device.destroy_sampler(self.sampler);
            device.destroy_image_view(self.image_view);
        }
    };

    pub const Vertex = struct {
        position: [3]f32,
        color: [3]f32 = .{1.0, 1.0, 1.0},
        texture: [2]f32,

        pub const binding_description: c.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        pub const attribute_descriptions = &[_]c.VkVertexInputAttributeDescription {
            .{
                .binding = 0,
                .location = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
            .{
                .binding = 0,
                .location = 2,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "texture"),
            },
        };
    };

    pub const Model = struct {
        items: ArrayList(Item),
        texture: Texture,

        index: Buffer,
        vertex: Buffer,
        len: u32,

        const Item = struct {
            mapped: *Uniform,
            buffer: Buffer,
            descriptor_set: c.VkDescriptorSet,

            fn new(
                device: Device,
                command_pool: CommandPool,
                descriptor: *Descriptor,
                uniform: Uniform,
            ) !Item {
                var mapped: *Uniform = undefined;
                const buffer = try Buffer.new(device, command_pool, Uniform, null,
                    .{
                        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                        .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        .len = 1,
                    });

                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.* = uniform;

                const descriptor_set = (try descriptor.allocate(device, .instance, 1))[0];
                device.update_descriptor_sets(&.{
                    .{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .dstSet = descriptor_set,
                        .dstBinding = 0,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .pBufferInfo = &.{
                            .buffer = buffer.handle,
                            .offset = 0,
                            .range = @sizeOf(Uniform),
                        },
                    },
                });

                return .{
                    .descriptor_set = descriptor_set,
                    .mapped = mapped,
                    .buffer = buffer,
                };
            }

            fn destroy(self: Item, device: Device) void {
                device.unmap_memory(self.buffer.memory);
                self.buffer.destroy(device);
            }
        };

        fn new(
            device: Device,
            command_pool: CommandPool,
            mesh: Mesh,
            texture: Texture,
            allocator: Allocator,
        ) !Model {
            const Index = @TypeOf(mesh.index.items[0]);
            const index = try Buffer.new(device, command_pool, Index, mesh.index.items,
                .{
                    .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .len = mesh.index.items.len,
                });

            var vertices = try ArrayList(Vertex).init(allocator, @intCast(mesh.vertex.items.len));
            defer vertices.deinit();

            for (0..mesh.vertex.items.len) |i| {
                try vertices.push(.{
                    .position = mesh.vertex.items[i],
                    .texture = mesh.texture.items[i],
                });
            }

            const vertex = try Buffer.new(device, command_pool, Vertex, vertices.items,
                .{
                    .usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .len = vertices.items.len,
                });

            const items = try ArrayList(Item).init(allocator, 1);
            const len: u32 = @intCast(mesh.index.items.len);

            return .{
                .index = index,
                .vertex = vertex,
                .items = items,
                .texture = texture,
                .len = len
            };
        }

        fn add_item(
            self: *Model,
            device: Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
            uniform: Uniform
        ) !u16 {
            const id = self.items.items.len;
            try self.items.push(try Item.new(device, command_pool, descriptor, uniform));

            return @intCast(id);
        }

        fn destroy(self: *Model, device: Device) void {
            if (self.len == 0) return;
            for (self.items.items) |item| {
                item.destroy(device);
            }

            self.texture.destroy(device);
            self.vertex.destroy(device);
            self.index.destroy(device);
            self.items.deinit();
        }
    };

    const Buffer = struct {
        handle: c.VkBuffer,
        memory: c.VkDeviceMemory,

        const Config = struct {
            usage: c.VkBufferUsageFlags,
            properties: c.VkMemoryPropertyFlags,
            len: usize,
        };

        fn new(
            device: Device,
            command_pool: CommandPool,
            comptime T: type,
            data: ?[]const T,
            config: Config,
        ) !Buffer {
            const buffer = try device.create_buffer(.{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = @sizeOf(T) * config.len,
                .usage = config.usage,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            });

            const memory_requirements = device.get_buffer_memory_requirements(buffer);

            const index = for (0..device.memory_properties.memoryTypeCount) |i| {
                if ((memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (device.memory_properties.memoryTypes[i].propertyFlags & config.properties) == config.properties) {
                    break i;
                }
            } else return error.NoMemoryRequirementsPassed;

            const memory = try device.allocate_memory(.{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = memory_requirements.size,
                .memoryTypeIndex = @as(u32, @intCast(index)),
            });

            try device.bind_buffer_memory(buffer, memory);

            if (data) |b| {
                var dst: *T = undefined;
                const staging_buffer = try Buffer.new(device, command_pool, T, null, .{
                    .len = config.len,
                    .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                });

                try device.map_memory(staging_buffer.memory, T, config.len, @ptrCast(&dst));

                @memcpy(@as([*]T, @ptrCast(@alignCast(dst))), b);
                device.unmap_memory(staging_buffer.memory);

                const command_buffer = try command_pool.allocate_command_buffer(device);
                device.cmd_copy_buffer(command_buffer, staging_buffer.handle, buffer, .{
                    .srcOffset = 0,
                    .dstOffset = 0,
                    .size = @sizeOf(T) * config.len,
                });
                try command_pool.free_command_buffer(device, command_buffer);

                staging_buffer.destroy(device);
            }

            return .{
                .handle = buffer,
                .memory = memory,
            };
        }

        fn destroy(self: Buffer, device: Device) void {
            device.destroy_buffer(self.handle);
            device.free_memory(self.memory);
        }
    };

    pub fn register_changes(
        self: *Data,
        device: Device,
        descriptor: *Descriptor,
        command_pool: *CommandPool,
        container: *Container,
    ) !void {
        if (container.updates.items.len > 0) {
            for (container.updates.items) |update| {
                switch (update.type) {
                    .font => {
                        const k = @intFromEnum(update.type.font);

                        if (!self.font.initialized) {
                            self.font = try Font.new(
                                device,
                                command_pool.*,
                                descriptor,
                                container.font_manager,
                                self.allocator,
                            );
                        }

                        const object_glyph = container.glyphs.items[update.id];
                        switch (update.change) {
                            .model => self.font.glyphs.items[object_glyph.id].mapped.model = object_glyph.model,
                            .color => self.font.glyphs.items[object_glyph.id].mapped.color = object_glyph.color,
                            .new => {
                                const model_glyph = container.font_manager.glyphs[k];
                                const glyph = try Font.Glyph.new(
                                    device,
                                    command_pool.*,
                                    descriptor,
                                    self.allocator,
                                    &model_glyph.vertex,
                                    &model_glyph.texture_coords,
                                    &model_glyph.index,
                                    .{ .model = object_glyph.model, .color = object_glyph.color }
                                );
                                container.glyphs.items[update.id].id = try self.font.add_glyph(glyph);
                            }
                        }
                    },
                    .mesh => {
                        const k = @intFromEnum(update.type.mesh);
                        const object = container.objects.items[update.id];

                        if (self.models[k].len == 0) {
                            var mesh = try Mesh.new(update.type.mesh, self.allocator);
                            const image = try PngImage.new("assets/image/image2.png", self.allocator);
                            const texture = try Texture.new(device, command_pool.*, descriptor, .{
                                .pixels = image.pixels,
                                .width = image.width,
                                .height = image.height,
                                .format = c.VK_FORMAT_R8G8B8A8_SRGB,
                                .anisotropy = true,
                            });

                            self.models[k] = try Model.new(device, command_pool.*, mesh, texture, self.allocator);

                            mesh.deinit();
                        }

                        switch (update.change) {
                            .model => self.models[k].items.items[object.id].mapped.model = object.model,
                            .color => self.models[k].items.items[object.id].mapped.color = object.color,
                            .new => {
                                container.objects.items[update.id].id = try self.models[k].add_item(device, command_pool.*, descriptor,
                                .{
                                    .model = object.model,
                                    .color = object.color,
                                });

                                command_pool.invalidate_all();
                            },
                        }
                    }
                }
            }

            try container.updates.clear();
        } if (container.camera.changed) {
            container.camera.changed = false;
            self.global.mapped.model = container.camera.view;
            self.global.mapped.color = container.camera.proj;
        }
    }

    pub fn destroy(self: Data, device: Device) void {
        self.global.destroy(device);
        self.font.destroy(device);

        for (self.models) |*model| model.destroy(device);
        self.allocator.free(self.models);
    }

    pub fn new(
        device: Device,
        descriptor: *Descriptor,
        command_pool: CommandPool,
        allocator: Allocator
    ) !Data {
        const models = try allocator.alloc(Model, @typeInfo(ObjectType).Enum.fields.len);
        const font: Font = .{
            .glyphs = undefined,
            .texture = undefined,
            .initialized = false,
        };

        @memset(models, .{
            .items = undefined,
            .index = undefined,
            .vertex = undefined,
            .texture = undefined,
            .len = 0,
        });

        return .{
            .global = try Global.new(device, command_pool, descriptor),
            .models = models,
            .font = font,
            .allocator = allocator,
        };
    }
};
