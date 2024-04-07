const std                = @import("std");

const _configuration     = @import("../../util/configuration.zig");
const _collections       = @import("../../collections/collections.zig");
const _math              = @import("../../math/math.zig");
const _platform          = @import("../../platform/platform.zig");
const _object            = @import("../../assets/object.zig");
const _container         = @import("../../container/container.zig");
const _font              = @import("../../assets/font.zig");
const _image             = @import("../../assets/image.zig");

const _command_pool      = @import("command_pool.zig");
const _device            = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");

const Device             = _device.Device;
const CommandPool        = _command_pool.CommandPool;
const Descriptor         = _graphics_pipeline.GraphicsPipeline.Descriptor;

const ArrayList          = _collections.ArrayList;
const Allocator          = std.mem.Allocator;
const Matrix             = _math.Matrix;
const Container          = _container.Container;
const ObjectHandler      = _object.ObjectHandler;
const Object             = ObjectHandler.Object;
const ObjectType         = ObjectHandler.Type;
const PngImage              = _image.PngImage;

const c                  = _platform.c;

pub const Data = struct {
    global: Global,
    models: []Model,
    allocator: Allocator,

    const Global = struct {
        buffer:         Buffer,
        mapped:         *Uniform,
        descriptor_set: c.VkDescriptorSet,

        const Uniform = struct {
            view: [4][4]f32,
            proj: [4][4]f32,
        };

        fn new(
            device:     Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
        ) !Global {
            const buffer = try Buffer.new(device, command_pool, Uniform, null,
                . {
                    .usage      = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    .len        = 1,
                });

            var mapped: *Uniform = undefined;

            try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
            mapped.view = Matrix.scale(1.0, 1.0, 1.0);
            mapped.proj = Matrix.scale(1.0, 1.0, 1.0);

            const descriptor_set = (try descriptor.allocate(device, .global, 1))[0];

            device.update_descriptor_sets(&.{
                .{
                    .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .dstSet           = descriptor_set,
                    .dstBinding       = 0,
                    .dstArrayElement  = 0,
                    .descriptorCount  = 1,
                    .pBufferInfo      = &.{
                        .buffer = buffer.handle,
                        .offset = 0,
                        .range  = @sizeOf(Uniform),
                    },
                }
            });

            return .{
                .buffer         = buffer,
                .mapped         = mapped,
                .descriptor_set = descriptor_set,
            };
        }

        fn destroy(self: Global, device: Device) void {
            device.unmap_memory(self.buffer.memory);
            self.buffer.destroy(device);
        }
    };

    pub const Texture = struct {
        image: c.VkImage,
        image_memory: c.VkDeviceMemory,
        image_view: c.VkImageView,
        sampler: c.VkSampler,

        fn new(
            device: Device,
            command_pool: CommandPool,
            image_path: []const u8,
            allocator: Allocator
        ) !Texture {
            const image = try PngImage.new(image_path, allocator);
            const len = image.pixels.len;
            const staging_buffer = try Buffer.new(device, command_pool, u8, null, .{
                .len = len,
            });

            var destine: *u8 = undefined;
            try device.map_memory(staging_buffer.memory, u8, len, @ptrCast(&destine));

            @memcpy(@as([*]u8, @ptrCast(@alignCast(destine))), image.pixels);
            device.unmap_memory(staging_buffer.memory);

            const texture_image = try device.create_image(.{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                .imageType = c.VK_IMAGE_TYPE_2D,
                .extent = .{
                    .width = image.width,
                    .height = image.height,
                    .depth = 1,
                },
                .mipLevels = 1,
                .arrayLayers = 1,
                .format = c.VK_FORMAT_R8G8B8A8_SRGB,
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
                            .width = image.width,
                            .height = image.height,
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
                .format = c.VK_FORMAT_R8G8B8A8_SRGB,
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
                .anisotropyEnable = c.VK_TRUE,
                .maxAnisotropy = device.physical_device_properties.limits.maxSamplerAnisotropy,
                .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
                .unnormalizedCoordinates = c.VK_FALSE,
                .compareEnable = c.VK_FALSE,
                .compareOp = c.VK_COMPARE_OP_ALWAYS,
                .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
                .mipLodBias = 0,
                .minLod = 0,
                .maxLod = 0,
            });

            return .{
                .image = texture_image,
                .image_memory = texture_memory,
                .image_view = texture_image_view,
                .sampler = texture_sampler,
            };
        }

        pub fn deinit(self: Texture, device: Device) void {
            device.destroy_image(self.image);
            device.free_memory(self.image_memory);
            device.destroy_sampler(self.sampler);
            device.destroy_image_view(self.image_view);
        }
    };

    pub const Model = struct {
        items:  ArrayList(Item),
        texture: Texture,

        index:  Buffer,
        vertex: Buffer,
        len:    u32,

        const Item = struct {
            mapped:         *Uniform,
            buffer:         Buffer,
            descriptor_set: c.VkDescriptorSet,

            const Uniform = struct {
                model: [4][4]f32,
                color: [4][4]f32,
            };

            fn new(
                device:     Device,
                command_pool: CommandPool,
                descriptor: *Descriptor,
                uniform:    Uniform,
                texture: Texture,
            ) !Item {
                var mapped: *Uniform = undefined;
                const buffer = try Buffer.new(device, command_pool, Uniform,  null,
                    .{
                        .usage      = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                        .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        .len = 1,
                    });

                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.* = uniform;

                const descriptor_set = (try descriptor.allocate(device, .model, 1))[0];

                device.update_descriptor_sets(&.{
                    .{
                        .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .dstSet           = descriptor_set,
                        .dstBinding       = 0,
                        .dstArrayElement  = 0,
                        .descriptorCount  = 1,
                        .pBufferInfo      = &.{
                            .buffer = buffer.handle,
                            .offset = 0,
                            .range  = @sizeOf(Uniform),
                        },
                    },
                    .{
                        .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .descriptorType   = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                        .dstSet           = descriptor_set,
                        .dstBinding       = 1,
                        .dstArrayElement  = 0,
                        .descriptorCount  = 1,
                        .pImageInfo       = &.{
                            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                            .imageView = texture.image_view,
                            .sampler = texture.sampler,
                        },
                    }
                });

                return .{
                    .descriptor_set = descriptor_set,
                    .mapped         = mapped,
                    .buffer         = buffer,
                };
            }

            fn destroy(self: Item, device: Device) void {
                device.unmap_memory(self.buffer.memory);
                self.buffer.destroy(device);
            }
        };

        pub const Vertex = struct {
            position: [3]f32,
            color:    [3]f32 = .{1.0, 1.0, 1.0},
            texture:  [2]f32,

            pub const binding_description: c.VkVertexInputBindingDescription = .{
                .binding   = 0,
                .stride    = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            };

            pub const attribute_descriptions = &[_]c.VkVertexInputAttributeDescription {
                .{
                    .binding  = 0,
                    .location = 0,
                    .format   = c.VK_FORMAT_R32G32B32_SFLOAT,
                    .offset   = @offsetOf(Vertex, "position"),
                },
                .{
                    .binding  = 0,
                    .location = 1,
                    .format   = c.VK_FORMAT_R32G32B32_SFLOAT,
                    .offset   = @offsetOf(Vertex, "color"),
                },
                .{
                    .binding  = 0,
                    .location = 2,
                    .format   = c.VK_FORMAT_R32G32_SFLOAT,
                    .offset   = @offsetOf(Vertex, "texture"),
                },
            };
        };

        fn new(
            device:    Device,
            command_pool: CommandPool,
            allocator: Allocator,
            object_handler: *ObjectHandler,
            typ:       ObjectType
        ) !Model {
            var object = try object_handler.create(typ);
            const Index = @TypeOf(object.index.items[0]);
            const index = try Buffer.new(device, command_pool, Index, object.index,
                .{
                    .usage      = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .len        = object.index.items.len,
                });

            var vertices = try ArrayList(Vertex).init(allocator, @intCast(object.vertex.items.len));
            defer vertices.deinit();

            std.debug.print("type: {any}\n", .{typ});
            for (0..object.vertex.items.len) |i| {
                try vertices.push(.{
                    .position = object.vertex.items[i],
                    .texture = object.texture.items[i],
                });
            }

            const vertex = try Buffer.new(device, command_pool, Vertex, vertices,
                .{
                    .usage      = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .len        = vertices.items.len,
                });

            const items = try ArrayList(Item).init(allocator, 1);
            const len: u32 = @intCast(object.index.items.len);

            object.deinit();
            const texture = try Texture.new(device, command_pool, "assets/image/image.png", allocator);

            return .{
                .index  = index,
                .vertex = vertex,
                .items  = items,
                .texture = texture,
                .len    = len
            };
        }

        fn add_item(
            self:       *Model,
            device:     Device,
            command_pool: CommandPool,
            descriptor: *Descriptor,
            uniform:    Item.Uniform
        ) !u16 {
            try self.items.push(try Item.new(device, command_pool, descriptor, uniform, self.texture));
            return @intCast(self.items.items.len - 1);
        }

        fn destroy(self: *Model, device: Device) void {
            if (self.len == 0) return;
            for (self.items.items) |item| {
                item.destroy(device);
            }

            self.texture.deinit(device);
            self.vertex.destroy(device);
            self.index.destroy(device);
            self.items.deinit();
        }
    };

    const Buffer = struct {
        handle: c.VkBuffer,
        memory: c.VkDeviceMemory,

        const Config = struct {
            usage:      ?c.VkBufferUsageFlags = null,
            properties: ?c.VkMemoryPropertyFlags = null,
            len:        usize,
        };

        fn new(
            device:     Device,
            command_pool: CommandPool,
            comptime T: type,
            data:       ?ArrayList(T),
            config:     Config,
        ) !Buffer {
            const usage      = config.usage orelse c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            const properties = config.properties orelse c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

            const buffer     = try device.create_buffer(.{
                .sType       = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size        = @sizeOf(T) * config.len,
                .usage       = usage,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            });

            const memory_requirements = device.get_buffer_memory_requirements(buffer);

            const index = for (0..device.memory_properties.memoryTypeCount) |i| {
                if ((memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (device.memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                    break i;
                }
            } else return error.NoMemoryRequirementsPassed;

            const memory = try device.allocate_memory(.{
                .sType           = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize  = memory_requirements.size,
                .memoryTypeIndex = @as(u32, @intCast(index)),
            });

            try device.bind_buffer_memory(buffer, memory);

            if (data) |b| {
                var dst: *T = undefined;
                const staging_buffer = try Buffer.new(device, command_pool,  T, null, .{
                    .len             = config.len,
                });

                try device.map_memory(staging_buffer.memory, T, config.len, @ptrCast(&dst));

                @memcpy(@as([*]T, @ptrCast(@alignCast(dst))), b.items);
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
        self:           *Data,
        device:         Device,
        descriptor:     *Descriptor,
        command_pool:   *CommandPool,
        container:      *Container,
    ) !void {
        if (container.updates.items.len > 0) {
            for (container.updates.items) |update| {
                const object = container.objects.items[update.id];
                const k = @intFromEnum(object.typ);

                if (self.models[k].len == 0) {
                    self.models[k] = try Model.new(device, command_pool.*, self.allocator, &container.object_handler, object.typ);
                }

                switch (update.change) {
                    .model => self.models[k].items.items[object.id].mapped.model = object.model,
                    .color => self.models[k].items.items[object.id].mapped.color = object.color,
                    .new   => {
                        container.objects.items[update.id].id = try self.models[k].add_item(device, command_pool.*, descriptor,
                        .{
                            .model = object.model,
                            .color = object.color,
                        });

                        command_pool.invalidate_all();
                    },
                }
            }

            try container.updates.clear();
        } if (container.camera.changed) {
            container.camera.changed = false;
            self.global.mapped.view  = container.camera.view;
            self.global.mapped.proj  = container.camera.proj;
        }
    }

    pub fn destroy(self: Data, device: Device) void {
        self.global.destroy(device);

        for (self.models) |*model| model.destroy(device);

        self.allocator.free(self.models);
    }

    pub fn new(device: Device, descriptor: *Descriptor, command_pool: CommandPool, allocator: Allocator) !Data {
        const models = try allocator.alloc(Model, @typeInfo(ObjectType).Enum.fields.len);

        @memset(models, .{
            .items  = undefined,
            .index  = undefined,
            .vertex = undefined,
            .texture = undefined,
            .len    = 0,
        });

        return .{
            .global    = try Global.new(device, command_pool, descriptor),
            .models    = models,
            .allocator = allocator,
        };
    }
};
