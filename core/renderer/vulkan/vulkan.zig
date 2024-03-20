const std                = @import("std");

const _container         = @import("../../container/container.zig");
const _platform          = @import("../../platform/platform.zig");
const _config            = @import("../../util/configuration.zig");

const _sync              = @import("sync.zig");
const _data              = @import("data.zig");
const _window            = @import("window.zig");
const _device            = @import("device.zig");
const _instance          = @import("instance.zig");
const _sawpchain         = @import("swapchain.zig");
const _command_pool      = @import("command_pool.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");

const Sync               = _sync.Sync;
const Data               = _data.Data;
const Device             = _device.Device;
const Window             = _window.Window;
const Instance           = _instance.Instance;
const Swapchain          = _sawpchain.Swapchain;
const CommandPool        = _command_pool.CommandPool;
const GraphicsPipeline   = _graphics_pipeline.GraphicsPipeline;

const Container          = _container.Container;
const Allocator          = std.mem.Allocator;
const Platform           = _platform.Platform;
const logger             = _config.Configuration.logger;

pub const Vulkan = struct {
    sync:              Sync,
    data:              Data,
    window:            Window,
    device:            Device,
    instance:          Instance,
    swapchain:         Swapchain,
    command_pool:      CommandPool,
    graphics_pipeline: GraphicsPipeline,

    pub fn new(comptime P: type, platform: P, allocator: Allocator) !Vulkan {
        const instance = Instance.new(P) catch |e| {
            logger.log(.Error, "Failed to create instance", .{});
            return e;
        };

        const window = Window.new(platform.create_surface(instance.handle) catch |e| {
                logger.log(.Error, "Failed to create surface", .{});
                return e;
            }) catch |e| {
            logger.log(.Error, "Failed to create window", .{});
            return e;
        };

        const device = Device.new(instance, window.surface, allocator) catch |e| {
            logger.log(.Error, "Failed to create device", .{});
            return e;
        };

        var graphics_pipeline = GraphicsPipeline.new(device, instance, window, allocator) catch |e| {
            logger.log(.Error, "Failed to create graphics_pipeline", .{});
            return e;
        };

        const swapchain = Swapchain.new(device, allocator, instance, window, graphics_pipeline) catch |e| {
            logger.log(.Error, "Failed to create swapchain", .{});
            return e;
        };

        const sync = Sync.new(device) catch |e| {
            logger.log(.Error, "Failed to create sync objects", .{});
            return e;
        };

        const data = Data.new(device, &graphics_pipeline.descriptor, allocator) catch |e| {
            logger.log(.Error, "Failed to create objects data", .{});
            return e;
        };

        const command_pool = CommandPool.new(device, swapchain) catch |e| {
            logger.log(.Error, "Failed to create command pool", .{});
            return e;
        };

        return .{
            .sync              = sync,
            .data              = data,
            .device            = device,
            .window            = window,
            .swapchain         = swapchain,
            .instance          = instance,
            .command_pool      = command_pool,
            .graphics_pipeline = graphics_pipeline,
        };
    }

    pub fn clock(self: *Vulkan) void {
        self.sync.update(self.device);
    }

    pub fn draw(self: *Vulkan, container: *Container) !bool {
        const scene_changed = container.updates.items.len > 0 or container.camera.changed;

        if (scene_changed) {
            self.data.register_changes(
                self.device,
                &self.graphics_pipeline.descriptor,
                &self.command_pool,
                container
            ) catch |e| {
                logger.log(.Error, "Failed to register changes in frame", .{});

                return e;
            };

        }

        if (self.window.resized or scene_changed or self.swapchain.force_redraw) {
            if (try self.swapchain.draw_next_frame(
                self.device,
                self.graphics_pipeline,
                &self.command_pool,
                self.data,
                &self.sync
            ) or self.window.resized
            ) {
                try self.swapchain.recreate(
                    self.device,
                    self.instance,
                    self.graphics_pipeline,
                    self.window,
                    &self.command_pool
                );

                self.window.resized = false;
            } else {
                self.sync.changed = true;
                self.swapchain.force_redraw = false;

                return true;
            }
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
