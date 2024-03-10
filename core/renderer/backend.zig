const std = @import("std");
const _platform = @import("platform.zig");
const _vulkan = @import("vulkan.zig");
const _configuration = @import("../util/configuration.zig");
const _game = @import("../game.zig");
const _event = @import("../event.zig");

const Platform = _platform.Platform;
const Vulkan = _vulkan.Vulkan;
const Game = _game.Game;
const Emiter = _event.EventSystem.Event.Emiter;

const logger = _configuration.Configuration.logger;

pub fn Backend(comptime renderer: Renderer) type {
    const T = blk: {
        switch (renderer) {
            .Vulkan => break :blk Vulkan,
            .OpenGL => logger.log(.Fatal, "OpenGL renderer not implemented yet", .{}),
            .X12    => logger.log(.Fatal, "DirectX12 renderer not implemented yet", .{}),
        }

        unreachable;
    };

    return struct {
        renderer: T,
        window: *Platform.Window,

        const Self = @This();

        pub fn new() !Self {
            const backend_renderer = T.new() catch |e| {
                logger.log(.Error, "Failed to initialize renderer", .{});

                return e;
            };

            return .{
                .renderer = backend_renderer,
                .window = backend_renderer.window.handle,
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
