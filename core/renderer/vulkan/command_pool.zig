const std = @import("std");

const _config = @import("../../util/configuration.zig");
const _collections = @import("../../collections/collections.zig");
const _platform = @import("../../platform/platform.zig");
const _allocator = @import("../../util/allocator.zig");

const _device = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");
const _swapchain = @import("swapchain.zig");
const _data = @import("data.zig");

const Swapchain = _swapchain.Swapchain;
const GraphicsPipeline = _graphics_pipeline.GraphicsPipeline;
const Device = _device.Device;
const Data = _data.Data;

const ArrayList = _collections.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = _allocator.Allocator;

const c = _platform.c;
const configuration = _config.Configuration;

pub const CommandPool = struct {
    handle: c.VkCommandPool,
    buffers: ArrayList(Buffer),
    allocator: *Allocator,

    const Buffer = struct {
        handle: c.VkCommandBuffer,
        is_valid: bool = false,
        id: u32,

        pub fn record(self: *Buffer, device: Device, pipeline: GraphicsPipeline, swapchain: Swapchain, data: Data) !void {
            try device.begin_command_buffer(self.handle, .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = 0,
                .pInheritanceInfo = null,
            });

            device.cmd_begin_render_pass(self.handle, .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .renderPass = pipeline.render_pass,
                .framebuffer = swapchain.framebuffers.items[self.id],
                .renderArea = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = swapchain.extent,
                },
                .clearValueCount = 2,
                .pClearValues = &[_] c.VkClearValue {
                    .{ .color = .{ .float32 = .{0.0, 0.0, 0.0, 1.0}, } },
                    .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } }
                },
            });

            device.cmd_set_viewport(self.handle, .{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(swapchain.extent.width)),
                .height = @as(f32, @floatFromInt(swapchain.extent.height)),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            });

            device.cmd_set_scissor(self.handle, .{
                .offset = .{ .x = 0, .y = 0},
                .extent = swapchain.extent,
            });

            device.cmd_bind_pipeline(self.handle, pipeline.handle);

            device.cmd_bind_descriptor_sets(
                self.handle, pipeline.layout, 0,
                &[_] c.VkDescriptorSet { data.global.descriptor_set },
                null
            );

            for (data.font.glyphs.items) |glyph| {
                device.cmd_bind_vertex_buffer(self.handle, glyph.vertex.handle);
                device.cmd_bind_index_buffer(self.handle, glyph.index.handle);

                device.cmd_bind_descriptor_sets(
                    self.handle, pipeline.layout, 1,
                    &[_] c.VkDescriptorSet { data.font.texture.descriptor_set, glyph.descriptor_set },
                    null
                );

                device.cmd_draw_indexed(self.handle, 6);
            }

            for (data.models) |model| {
                if (model.len == 0) continue;

                device.cmd_bind_vertex_buffer(self.handle, model.vertex.handle);
                device.cmd_bind_index_buffer(self.handle, model.index.handle);

                device.cmd_bind_descriptor_sets(
                    self.handle, pipeline.layout, 1,
                    &[_] c.VkDescriptorSet { model.texture.descriptor_set },
                    null
                );

                for (model.items.items) |item| {
                    device.cmd_bind_descriptor_sets(
                        self.handle, pipeline.layout, 2,
                        &[_] c.VkDescriptorSet { item.descriptor_set },
                        null
                    );
                    device.cmd_draw_indexed(self.handle, model.len);
                }
            }

            device.end_render_pass(self.handle);
            try device.end_command_buffer(self.handle);

            self.is_valid = true;
        }
    };

    pub fn invalidate_all(self: *CommandPool) void {
        for (0..self.buffers.items.len) |i| {
            self.buffers.items[i].is_valid = false;
        }
    }

    pub fn allocate_command_buffer(self: CommandPool, device: Device) !c.VkCommandBuffer {
        const command_buffer = try device.allocate_command_buffer(.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.handle,
            .commandBufferCount = 1,
        });

        try device.begin_command_buffer(command_buffer, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        });

        return command_buffer;
    }

    pub fn free_command_buffer(self: CommandPool, device: Device, command_buffer: c.VkCommandBuffer) !void {
        try device.end_command_buffer(command_buffer);
        try device.queue_submit(null, .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        });

        try device.queue_wait_idle(device.queues[0].handle);
        device.free_command_buffer(self.handle, command_buffer);
    }

    pub fn new(device: Device, swapchain: Swapchain, allocator: *Allocator) !CommandPool {
        const handle = try device.create_command_pool(.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = device.queues[0].family,
        });

        const count: u32 = @intCast(swapchain.framebuffers.items.len);
        var buffers = try ArrayList(Buffer).init(allocator, count);

        const bs = try device.allocate_command_buffers(allocator, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = handle,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = count,
        });

        defer allocator.free(bs);
        for (0..count) |i| {
            try buffers.push(.{
                .handle = bs[i],
                .id = @intCast(i),
            });
        }

        return .{
            .buffers = buffers,
            .handle = handle,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *CommandPool, device: Device) void {
        for (0..self.buffers.items.len) |i| {
            device.free_command_buffer(self.handle, self.buffers.items[i].handle);
        }

        self.buffers.deinit();

        device.destroy_command_pool(self.handle);
    }
};
