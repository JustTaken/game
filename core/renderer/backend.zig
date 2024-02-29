const std = @import("std");
const _platform = @import("platform.zig");
const _configuration = @import("../util/configuration.zig");

const Platform = _platform.Platform;

const logger = _configuration.Configuration.logger;

pub fn Backend(comptime T: type) type {
    return struct {
        renderer: T,
        window: *Platform.Window,

        const Self = @This();

        pub fn new() !Self {
            const renderer = T.new() catch |e| {
                logger.log(.Error, "Failed to initialize renderer", .{});

                return e;
            };

            return .{
                .renderer = renderer,
                .window = renderer.window.handle,
            };
        }

        pub fn draw(self: *Self) !void {
            try self.renderer.draw();
        }

        pub fn shutdown(self: *Self) void {
            self.renderer.shutdown();
        }
    };
}

pub const Renderer = enum {
    Vulkan,
    OpenGL, // TODO: Make this work
    X12, // TODO: Make this work
};
