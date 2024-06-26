const std = @import("std");

const _container = @import("../../container/container.zig");
const _platform = @import("../../platform/platform.zig");
const _config = @import("../../util/configuration.zig");
const _allocator = @import("../../util/allocator.zig");

const _sync = @import("sync.zig");
const _data = @import("data.zig");
const _window = @import("window.zig");
const _device = @import("device.zig");
const _instance = @import("instance.zig");
const _sawpchain = @import("swapchain.zig");
const _command_pool = @import("command_pool.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");

const Sync = _sync.Sync;
const Data = _data.Data;
const Device = _device.Device;
const Window = _window.Window;
const Instance = _instance.Instance;
const Swapchain = _sawpchain.Swapchain;
const CommandPool = _command_pool.CommandPool;
const GraphicsPipeline = _graphics_pipeline.GraphicsPipeline;

const Container = _container.Container;
const Allocator = _allocator.Allocator;
const Platform = _platform.Platform;

pub const Vulkan = struct {
    instance: Instance,
    window: Window,
    device: Device,
    graphics_pipeline: GraphicsPipeline,
    swapchain: Swapchain,
    sync: Sync,
    command_pool: CommandPool,
    data: Data,

    pub fn new(comptime P: type, platform: P, allocator: *Allocator) !Vulkan {
        const instance = try Instance.new(P);
        const window = try Window.new(try platform.create_surface(instance.handle));
        const device = try Device.new(instance, window.surface, allocator);
        var graphics_pipeline = try GraphicsPipeline.new(device, instance, window, allocator);
        const swapchain = try Swapchain.new(device, allocator, window, graphics_pipeline);
        const sync = try Sync.new(device);
        const command_pool = try CommandPool.new(device, swapchain, allocator);
        const data = try Data.new(device, &graphics_pipeline.descriptor, command_pool, allocator);

        return .{
            .instance = instance,
            .window = window,
            .device = device,
            .graphics_pipeline = graphics_pipeline,
            .swapchain = swapchain,
            .sync = sync,
            .command_pool = command_pool,
            .data = data,
        };
    }

    pub fn clock(self: *Vulkan) void {
        self.sync.update(self.device);
    }

    pub fn draw(self: *Vulkan, container: *Container) !bool {
        const scene_changed = container.updates.items.len > 0 or container.camera.changed;

        if (scene_changed) {
            try self.data.register_changes(
                self.device,
                &self.graphics_pipeline.descriptor,
                &self.command_pool,
                container
            );
        }

        if (self.window.resized or scene_changed or self.swapchain.force_redraw) {
            try self.swapchain.draw_next_frame(
                self.device,
                self.graphics_pipeline,
                &self.command_pool,
                &self.window,
                self.data,
                &self.sync
            );

            return true;
        }

        return false;
    }

    pub fn shutdown(self: *Vulkan) void {
        self.command_pool.destroy(self.device);
        self.data.destroy(self.device);
        self.sync.destroy(self.device);
        self.graphics_pipeline.destroy(self.device);
        self.swapchain.destroy(self.device);
        self.device.destroy();
        self.window.destroy(self.instance);
        self.instance.destroy();
    }
};
