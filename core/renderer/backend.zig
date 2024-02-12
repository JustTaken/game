const std = @import("std");
const _utility = @import("../utility.zig");
const _wrapper = @import("wrapper.zig");

const Glfw = _wrapper.Glfw;
const Vulkan = _wrapper.Vulkan;

const Instance = Vulkan.Instance;
const Device = Vulkan.Device;
const Swapchain = Vulkan.Swapchain;
const Surface = Vulkan.Surface;
const Window = Vulkan.Window;
const GraphicsPipeline = Vulkan.GraphicsPipeline;
const CommandPool = Vulkan.CommandPool;
const Sync = Vulkan.Sync;
const Buffer = Vulkan.Buffer;

const configuration = _utility.Configuration;

var SNAP_ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const SNAP_ALLOCATOR = SNAP_ARENA.allocator();

pub const Backend = struct {
    instance: Instance,
    window: Window,
    device: Device,
    swapchain: Swapchain,
    graphics_pipeline: GraphicsPipeline,
    command_pool: CommandPool,
    sync: Sync,
    buffer: Buffer,

    pub fn new() !Backend {
        defer { _ = SNAP_ARENA.deinit(); }

        try Glfw.init();

        const instance = Instance.new(SNAP_ALLOCATOR) catch |e| {
            configuration.logger.log(.Error, "Failed to create instance", .{});

            return e;
        };

        const window = Window.new(instance, configuration.default_width, configuration.default_height) catch |e| {
            configuration.logger.log(.Error, "Failed to create window", .{});

            return e;
        };

        const device = Device.new(instance, window.surface, SNAP_ALLOCATOR) catch |e| {
            configuration.logger.log(.Error, "Failed to create device", .{});

            return e;
        };

        const swapchain = Swapchain.new(device, instance, window, null) catch |e| {
            configuration.logger.log(.Error, "Failed to create swapchain", .{});

            return e;
        };

        const graphics_pipeline = GraphicsPipeline.new(device, swapchain, SNAP_ALLOCATOR) catch |e| {
            configuration.logger.log(.Error, "Failed to create graphics_pipeline", .{});

            return e;
        };

        const command_pool = CommandPool.new(device) catch |e| {
            configuration.logger.log(.Error, "Failed to create command pool", .{});

            return e;
        };

        const sync = Sync.new(device) catch |e| {
            configuration.logger.log(.Error, "Failed to create sync objects", .{});

            return e;
        };

        const buffer = Buffer.new(device, instance) catch |e| {
            configuration.logger.log(.Error, "Failed to create vertex buffer", .{});

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
            .buffer = buffer,
        };
    }

    pub fn draw(self: *Backend) !void {
        const image_index = self.swapchain.acquire_next_image(self.device, self.sync) catch |e| {
            if (Swapchain.has_to_recreate(e)) {
                configuration.logger.log(.Debug, "Recreating swapchain", .{});

                self.swapchain.recreate(self.device, self.instance, self.graphics_pipeline, self.window) catch |e2| {
                    configuration.logger.log(.Error, "Recreate swapchain failed, quiting", .{});

                    return e2;
                };

                return;
            } else {
                configuration.logger.log(.Error, "Could not rescue the frame, dying", .{});

                return e;
            }
        };

        self.command_pool.record_command_buffer(self.instance, self.graphics_pipeline, self.swapchain, image_index) catch |e| {
            configuration.logger.log(.Error, "Backend failed to record command buffer", .{});

            return e;
        };

        self.swapchain.queue_pass(self.device, self.command_pool, self.sync, image_index) catch |e| {
            if (Swapchain.has_to_recreate(e)) {
                configuration.logger.log(.Debug, "Recreating swapchain", .{});

                self.swapchain.recreate(self.device, self.instance, self.graphics_pipeline, self.window) catch |e2| {
                    configuration.logger.log(.Error, "Recreate swapchain failed, quiting application", .{});

                    return e2;
                };

                return;
            } else {
                configuration.logger.log(.Error, "Could not handle current frame presentation, dying", .{});

                return e;
            }
        };

        self.sync.wait(self.device) catch {
            configuration.logger.log(.Warn, "CPU did not wait for the next frame", .{});
        };
    }

    pub fn shutdown(self: *Backend) void {
        self.sync.destroy(self.device);
        self.graphics_pipeline.destroy(self.device);
        self.swapchain.destroy(self.device);
        self.device.destroy();
        self.window.destroy(self.instance);
        self.instance.destroy();

        Glfw.shutdown();
    }
};
