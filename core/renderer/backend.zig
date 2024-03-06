const std = @import("std");
const _platform = @import("platform.zig");
const _configuration = @import("../util/configuration.zig");
const _game = @import("../game.zig");
const _event = @import("../event.zig");

const Platform = _platform.Platform;
const Game = _game.Game;
const Emiter = _event.EventSystem.Event.Emiter;

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

        pub fn draw(self: *Self, game: *Game) !void {
            try self.renderer.draw(game);
        }

        pub fn register_window_emiter(self: *Self, emiter: *Emiter) void {
            self.renderer.window.register_emiter(emiter);
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
