const _config = @import("../../util/configuration.zig");
const _platform = @import("../../platform/platform.zig");
const _event = @import("../../event.zig");
const _instance = @import("instance.zig");

const Instance = _instance.Instance;

const Platform = _platform.Platform;
const Emiter = _event.EventSystem.Event.Emiter;

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Window = struct {
    handle: *Platform.Window,
    surface: c.VkSurfaceKHR,
    extent: c.VkExtent2D,
    emiter: *Emiter = undefined,

    pub fn new(instance: Instance, extent: ?c.VkExtent2D) !Window {
        const handle = Platform.create_window(extent, &configuration.application_name[0]) catch |e| {
            logger.log(.Error, "Platform failed to create window handle", .{});

            return e;
        };

        const surface = Platform.create_window_surface(instance.handle, handle, null) catch |e| {
            logger.log(.Error, "Failed to create window surface", .{});

            return e;
        };

        const window_extent = extent orelse blk: {
            break :blk Platform.get_framebuffer_size(handle);
        };

        return .{
            .handle = handle,
            .surface = surface,
            .extent = window_extent
        };
    }

    pub fn register_emiter(self: *Window, emiter: *Emiter) void {
        self.emiter = emiter;
    }

    pub fn destroy(self: Window, instance: Instance) void {
        instance.destroy_surface(self.surface);
        Platform.destroy_window(self.handle);
    }
};
