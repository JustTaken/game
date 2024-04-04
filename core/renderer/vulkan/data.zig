const std                = @import("std");

const _configuration     = @import("../../util/configuration.zig");
const _collections       = @import("../../collections/collections.zig");
const _math              = @import("../../math/math.zig");
const _platform          = @import("../../platform/platform.zig");
const _object            = @import("../../assets/object.zig");
const _container         = @import("../../container/container.zig");
const _font              = @import("../../assets/font.zig");

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
            descriptor: *Descriptor,
            allocator:  Allocator
        ) !Global {
            const buffer = try Buffer.new(device, Uniform, null,
                . {
                    .usage      = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    .allocator  = allocator,
                    .len        = 1,
                });

            var mapped: *Uniform = undefined;

            try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
            mapped.view = Matrix.scale(1.0, 1.0, 1.0);
            mapped.proj = Matrix.scale(1.0, 1.0, 1.0);

            const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

            device.update_descriptor_sets(.{
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
                .pImageInfo       = null,
                .pTexelBufferView = null,
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

    pub const Model = struct {
        items:  ArrayList(Item),

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
                descriptor: *Descriptor,
                uniform:    Uniform,
                allocator:  Allocator
            ) !Item {
                var mapped: *Uniform = undefined;
                const buffer = try Buffer.new(device, Uniform, null,
                    .{
                        .usage      = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                        .properties = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        .allocator  = allocator,
                        .len = 1,
                    });

                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.* = uniform;

                const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

                device.update_descriptor_sets(.{
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
                    .pImageInfo       = null,
                    .pTexelBufferView = null,
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
            };
        };

        fn new(
            device:    Device,
            allocator: Allocator,
            object_handler: *ObjectHandler,
            typ:       ObjectType
        ) !Model {
            var object = try object_handler.create(typ);

            const Index = @TypeOf(object.index.items[0]);
            const index = try Buffer.new(device, Index, object.index,
                .{
                    .usage      = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .allocator  = allocator,
                    .len        = object.index.items.len,
                });

            var vertices = try ArrayList(Vertex).init(allocator, @intCast(object.vertex.items.len));
            defer vertices.deinit();

            for (object.vertex.items) |vert| {
                try vertices.push(.{
                    .position = .{vert.x, vert.y, vert.z},
                });
            }

            const vertex = try Buffer.new(device, Vertex, vertices,
                .{
                    .usage      = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    .properties = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    .allocator  = allocator,
                    .len        = vertices.items.len,
                });

            const items = try ArrayList(Item).init(allocator, 1);
            const len: u32 = @intCast(object.index.items.len);
            object.deinit();

            return .{
                .index  = index,
                .vertex = vertex,
                .items  = items,
                .len    = len
            };
        }

        fn add_item(
            self:       *Model,
            device:     Device,
            descriptor: *Descriptor,
            allocator:  Allocator,
            uniform:    Item.Uniform
        ) !u16 {
            try self.items.push(try Item.new(device, descriptor, uniform, allocator));
            return @intCast(self.items.items.len - 1);
        }

        fn destroy(self: *Model, device: Device) void {
            if (self.len == 0) return;
            for (self.items.items) |item| {
                item.destroy(device);
            }

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
            allocator:  Allocator,
            len:        usize,
        };

        fn new(
            device:     Device,
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
                const staging_buffer = try Buffer.new(device, T, null, .{
                    .len             = config.len,
                    .allocator       = config.allocator,
                });

                try device.map_memory(staging_buffer.memory, T, config.len, @ptrCast(&dst));

                @memcpy(@as([*]T, @ptrCast(@alignCast(dst))), b.items);
                device.unmap_memory(staging_buffer.memory);

                const command_pool = try device.create_command_pool(.{
                    .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                    .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                    .queueFamilyIndex = device.queues[0].family,
                });

                const command_buffers = try device.allocate_command_buffers(config.allocator, .{
                    .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                    .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                    .commandPool        = command_pool,
                    .commandBufferCount = 1,
                });
                defer config.allocator.free(command_buffers);

                try device.begin_command_buffer(command_buffers[0], .{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
                });

                device.cmd_copy_buffer(command_buffers[0], staging_buffer.handle, buffer, .{
                    .srcOffset = 0,
                    .dstOffset = 0,
                    .size      = @sizeOf(T) * config.len,
                });

                try device.end_command_buffer(command_buffers[0]);
                try device.queue_submit(null, .{
                    .sType              = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .commandBufferCount = 1,
                    .pCommandBuffers    = &command_buffers[0],
                });

                try device.queue_wait_idle(device.queues[0].handle);

                device.free_command_buffer(command_pool, command_buffers[0]);
                device.destroy_buffer(staging_buffer.handle);
                device.free_memory(staging_buffer.memory);
                device.destroy_command_pool(command_pool);
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
                    self.models[k] = try Model.new(device, self.allocator, &container.object_handler, object.typ);
                }

                switch (update.change) {
                    .model => self.models[k].items.items[object.id].mapped.model = object.model,
                    .color => self.models[k].items.items[object.id].mapped.color = object.color,
                    .new   => {
                        container.objects.items[update.id].id = try self.models[k].add_item(device, descriptor, self.allocator,
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

        for (self.models) |*model| {
            model.destroy(device);
        }

        self.allocator.free(self.models);
    }

    pub fn new(device: Device, descriptor: *Descriptor, allocator: Allocator) !Data {
        const models = try allocator.alloc(Model, @typeInfo(ObjectType).Enum.fields.len);
        @memset(models, .{
            .items  = undefined,
            .index  = undefined,
            .vertex = undefined,
            .len    = 0,
        });

        return .{
            .global    = try Global.new(device, descriptor, allocator),
            .models    = models,
            .allocator = allocator,
        };
    }
};
