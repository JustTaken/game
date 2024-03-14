const std = @import("std");

const _config = @import("../../util/configuration.zig");
const _platform = @import("../../platform/platform.zig");
const _game = @import("../../game.zig");

const _instance = @import("instance.zig");
const _window = @import("window.zig");
const _device = @import("device.zig");
const _sawpchain = @import("swapchain.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");
const _command_pool = @import("command_pool.zig");
const _sync = @import("sync.zig");
const _data = @import("data.zig");

const Instance = _instance.Instance;
const Window = _window.Window;
const Device = _device.Device;
const Swapchain = _sawpchain.Swapchain;
const GraphicsPipeline = _graphics_pipeline.GraphicsPipeline;
const CommandPool = _command_pool.CommandPool;
const Sync = _sync.Sync;
const Data = _data.Data;

const Platform = _platform.Platform;
const Game = _game.Game;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Vulkan = struct {
    instance: Instance,
    window: Window,
    device: Device,
    swapchain: Swapchain,
    graphics_pipeline: GraphicsPipeline,
    command_pool: CommandPool,
    sync: Sync,
    data: Data,

    pub fn new() !Vulkan {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();

        defer { _ = arena.deinit(); }

        try Platform.init();

        const instance = Instance.new() catch |e| {
            logger.log(.Error, "Failed to create instance", .{});

            return e;
        };

        const window = Window.new(instance, .{.width = configuration.default_width, .height = configuration.default_height }) catch |e| {
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

        const swapchain = Swapchain.new(device, null, instance, window, graphics_pipeline) catch |e| {
            logger.log(.Error, "Failed to create swapchain", .{});

            return e;
        };

        const sync = Sync.new(device, window) catch |e| {
            logger.log(.Error, "Failed to create sync objects", .{});

            return e;
        };

        const data = Data.new(device, instance.get_physical_device_memory_properties(device.physical_device), &graphics_pipeline.descriptor) catch |e| {
            logger.log(.Error, "Failed to create objects data", .{});

            return e;
        };

        const command_pool = CommandPool.new(device, swapchain) catch |e| {
            logger.log(.Error, "Failed to create command pool", .{});

            return e;
        };

        return .{
            .instance = instance,
            .window = window,
            .device = device,
            .swapchain = swapchain,
            .graphics_pipeline = graphics_pipeline,
            .command_pool = command_pool,
            .sync = sync,
            .data = data,
        };
    }

    pub fn draw(self: *Vulkan, game: *Game) !void {
        self.sync.update(self.device);

        if (game.object_handle.has_change() or game.camera.changed) {
            self.data.register_changes(self.device, self.instance.get_physical_device_memory_properties(self.device.physical_device), &self.graphics_pipeline.descriptor, &self.command_pool, game) catch |e| {
                logger.log(.Error, "Failed to register changes in frame", .{});

                return e;
            };

            try self.swapchain.draw_next_frame(self.device, self.instance, self.graphics_pipeline, &self.window, &self.command_pool, self.data, &self.sync);
        }
    }

    pub fn shutdown(self: *Vulkan) void {
        self.command_pool.destroy(self.device);
        self.data.destroy(self.device);
        self.sync.destroy(self.device);
        self.graphics_pipeline.destroy(self.device);
        self.swapchain.destroy(self.device, true);
        self.device.destroy();
        self.window.destroy(self.instance);
        self.instance.destroy();

        Platform.shutdown();
    }
};
