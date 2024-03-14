const std = @import("std");


const _config = @import("../../util/configuration.zig");
const _collections = @import("../../util/collections.zig");
const _math = @import("../../util/math.zig");
const _platform = @import("../../platform/platform.zig");
const _object = @import("../../asset/object.zig");
const _game = @import("../../game.zig");

const _command_pool = @import("command_pool.zig");
const _device = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");

const Device = _device.Device;
const GraphicsPipeline = _graphics_pipeline.GraphicsPipeline;
const CommandPool = _command_pool.CommandPool;

const ArrayList = _collections.ArrayList;
const Matrix = _math.Matrix;
const Object = _object.Object;
const Game = _game.Game;
const ObjectHandle = _game.ObjectHandle;

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Data = struct {
    global: Global,
    models: []Model,
    arena: std.heap.ArenaAllocator,

    const Global = struct {
        buffer: Buffer,
        mapped: *Uniform,
        descriptor_set: c.VkDescriptorSet,

        const Uniform = struct {
            view: [4][4]f32,
            proj: [4][4]f32,
        };

        fn new(
            device: Device,
            memory_properties: c.VkPhysicalDeviceMemoryProperties,
            descriptor: *GraphicsPipeline.Descriptor,
            allocator: std.mem.Allocator
        ) !Global {
            const buffer = try Buffer.new(
                device,
                memory_properties,
                c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                Uniform,
                null,
                1,
                allocator
            );

            var mapped: *Uniform = undefined;
            try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
            mapped.view = Matrix.scale(1.0, 1.0, 1.0);
            mapped.proj = Matrix.scale(1.0, 1.0, 1.0);

            const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

            device.update_descriptor_sets(.{
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
                .pImageInfo = null,
                .pTexelBufferView = null,
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

    pub const Model = struct {
        items: ArrayList(Item) = undefined,

        index: Buffer = undefined,
        vertex: Buffer = undefined,
        len: u32 = 0,

        const Item = struct {
            descriptor_set: c.VkDescriptorSet,
            mapped: *Uniform,
            buffer: Buffer,

            const Uniform = struct {
                model: [4][4]f32,
                color: [4][4]f32,
            };

            fn set_model(self: *Item, uniform: Uniform) !void {
                @memcpy(@as([*]Uniform, @ptrCast(@alignCast(self.mapped))), &[_]Uniform { uniform });
            }

            fn new(
                device: Device,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                descriptor: *GraphicsPipeline.Descriptor,
                uniform: Uniform,
                allocator: std.mem.Allocator
            ) !Item {
                var mapped: *Uniform = undefined;
                const buffer = try Buffer.new(
                    device,
                    memory_properties,
                    c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    Uniform,
                    null,
                    1,
                    allocator,
                );

                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.* = uniform;

                const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

                device.update_descriptor_sets(.{
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
                    .pImageInfo = null,
                    .pTexelBufferView = null,
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

        pub const Vertex = struct {
            position: [3]f32,
            color: [3]f32 = .{1.0, 1.0, 1.0},

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
            };
        };

        fn new(
            device: Device,
            memory_properties: c.VkPhysicalDeviceMemoryProperties,
            allocator: std.mem.Allocator,
            typ: Object.Type
        ) !Model {
            const object = try Object.new(typ, allocator);
            const Index = @TypeOf(object.index.items[0]);
            const index = try Buffer.new(
                device,
                memory_properties,
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                Index,
                object.index,
                object.index.items.len,
                allocator,
            );

            var vertices = try ArrayList(Vertex).init(allocator, @intCast(object.vertex.items.len));
            for (object.vertex.items) |vert| {
                try vertices.push(.{
                    .position = .{vert.x, vert.y, vert.z},
                });
            }

            const vertex = try Buffer.new(
                device,
                memory_properties,
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                Vertex,
                vertices,
                vertices.items.len,
                allocator
            );

            const items = try ArrayList(Item).init(allocator, 1);

            return .{
                .index = index,
                .vertex = vertex,
                .items = items,
                .len = @intCast(object.index.items.len)
            };
        }

        fn add_item(
            self: *Model,
            device: Device,
            memory_properties: c.VkPhysicalDeviceMemoryProperties,
            uniform: Item.Uniform,
            descriptor: *GraphicsPipeline.Descriptor,
            allocator: std.mem.Allocator
        ) !u16 {
            try self.items.push(try Item.new(device, memory_properties, descriptor, uniform, allocator));
            return @intCast(self.items.items.len - 1);
        }

        fn destroy(self: Model, device: Device) void {
            if (self.len == 0) return;
            for (self.items.items) |item| {
                item.destroy(device);
            }

            self.vertex.destroy(device);
            self.index.destroy(device);
        }
    };

    const Buffer = struct {
        handle: c.VkBuffer,
        memory: c.VkDeviceMemory,

        fn new(
            device: Device,
            memory_properties: c.VkPhysicalDeviceMemoryProperties,
            opt_usage: ?c.VkBufferUsageFlags,
            opt_properties: ?c.VkMemoryPropertyFlags,
            comptime T: type,
            data: ?ArrayList(T),
            len: usize,
            allocator: std.mem.Allocator,
        ) !Buffer {
            const usage = opt_usage orelse c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            const properties = opt_properties orelse c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

            const buffer = try device.create_buffer(.{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = @sizeOf(T) * len,
                .usage = usage,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            });

            const memory_requirements = device.get_buffer_memory_requirements(buffer);

            const index = blk: for (0..memory_properties.memoryTypeCount) |i| {
                if ((memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                    break :blk i;
                }
            } else {
                logger.log(.Error, "Could not find memory type that suit the need of buffer allocation", .{});
                return error.NoMemoryRequirementsPassed;
            };

            const memory = try device.allocate_memory(.{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = memory_requirements.size,
                .memoryTypeIndex = @as(u32, @intCast(index)),
            });

            try device.bind_buffer_memory(buffer, memory);

            if (data) |b| {
                const staging_buffer = try Buffer.new(device, memory_properties, null, null, T, null, len, allocator);
                var dst: *T = undefined;
                try device.map_memory(staging_buffer.memory, T, len, @ptrCast(&dst));
                @memcpy(@as([*]T, @ptrCast(@alignCast(dst))), b.items);
                device.unmap_memory(staging_buffer.memory);

                const command_pool = device.create_command_pool(.{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                    .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                    .queueFamilyIndex = device.queues[0].family,
                }) catch |e| {
                    logger.log(.Error, "Failed to create command pool", .{});

                    return e;
                };

                const command_buffers = device.allocate_command_buffers(.{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                    .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                    .commandPool = command_pool,
                    .commandBufferCount = 1,
                }, allocator) catch |e| {
                    logger.log(.Error, "Failed to allocate command buffer", .{});

                    return e;
                };

                try device.begin_command_buffer(command_buffers[0], .{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
                });

                device.cmd_copy_buffer(command_buffers[0], staging_buffer.handle, buffer, .{
                    .srcOffset = 0,
                    .dstOffset = 0,
                    .size = @sizeOf(T) * len,
                });

                try device.end_command_buffer(command_buffers[0]);
                try device.queue_submit(
                    .{
                        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                        .commandBufferCount = 1,
                        .pCommandBuffers = &command_buffers[0],
                    }, null,
                );

                try device.queue_wait_idle(device.queues[0].handle);

                device.free_command_buffer(command_pool, command_buffers[0]);
                device.destroy_buffer(staging_buffer.handle);
                device.free_memory(staging_buffer.memory);
                allocator.free(command_buffers);
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

    pub fn new(device: Device, memory_properties: c.VkPhysicalDeviceMemoryProperties, descriptor: *GraphicsPipeline.Descriptor) !Data {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();

        const models = try allocator.alloc(Model, @intFromEnum(Object.Type.None));
        @memset(models, .{});

        return .{
            .global = try Global.new(device, memory_properties, descriptor, allocator),
            .models = models,
            .arena = arena,
        };
    }

    pub fn register_changes(
        self: *Data,
        device: Device,
        memory_properties: c.VkPhysicalDeviceMemoryProperties,
        descriptor: *GraphicsPipeline.Descriptor,
        command_pool: *CommandPool,
        game: *Game,
    ) !void {
        const allocator = self.arena.allocator();

        if (game.object_handle.has_change()) {
            for (game.object_handle.to_update.items) |update| {
                const object = game.object_handle.objects.items[update.id];
                const k = @intFromEnum(object.typ);

                if (self.models[k].len == 0) {
                    self.models[k] = try Model.new(device, memory_properties, allocator, object.typ);
                }

                switch (update.data) {
                        .model => |model| self.models[k].items.items[object.id].mapped.model = model,
                        .color => |color| self.models[k].items.items[object.id].mapped.color = color,
                        .new => {
                            game.object_handle.objects.items[update.id].id = try self.models[k].add_item(device, memory_properties, .{
                                .model = object.model,
                                .color = object.color,
                            }, descriptor, allocator);

                            command_pool.invalidate_all();
                        },
                }
            }

            try game.object_handle.clear_updates();
        } if (game.camera.changed) {
            game.camera.changed = false;
            self.global.mapped.view = game.camera.view;
            self.global.mapped.proj = game.camera.proj;
        }
    }

    pub fn destroy(self: Data, device: Device) void {
        self.global.destroy(device);

        for (self.models) |model| {
            model.destroy(device);
        }

        _ = self.arena.deinit();
    }
};
