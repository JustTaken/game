const std = @import("std");

const _vulkan = @import("vulkan/vulkan.zig");
const _configuration = @import("../util/configuration.zig");
const _game = @import("../game.zig");
const _event = @import("../event.zig");
const _platform = @import("../platform/platform.zig");

const Vulkan = _vulkan.Vulkan;
const Game = _game.Game;
const Emiter = _event.EventSystem.Event.Emiter;
const Compositor = _platform.Compositor;
const Platform = _platform.Platform;

const logger = _configuration.Configuration.logger;

pub fn Backend(comptime compositor: Compositor, comptime renderer: Renderer) type {
    return struct {
        renderer: T,
        platform: P,

        const Self = @This();

        pub const T = Renderer.get(renderer);
        pub const P = Platform(compositor);

        pub fn new() !Self {
            const platform = P.init() catch |e| {
                logger.log(.Error, "Could not initialize platform", .{});

                return e;
            };


            const backend_renderer = T.new(P, platform) catch |e| {
                logger.log(.Error, "Failed to initialize renderer", .{});

                return e;
            };

            return .{
                .renderer = backend_renderer,
                .platform = platform,
            };
        }

        pub fn draw(self: *Self, game: *Game) !void {
            if (try self.renderer.draw(game)) {
                self.platform.commit();
            }

            try self.platform.update_events();
        }

        pub fn sync(self: *Self) void {
            self.renderer.clock();
        }

        pub fn register_window_emiter(self: *Self, emiter: *Emiter) void {
            self.renderer.window.register_emiter(emiter);
        }

        pub fn shutdown(self: *Self) void {
            self.renderer.shutdown();
            self.platform.deinit();
        }
    };
}

pub const Renderer = enum {
    Vulkan,
    OpenGL, // TODO: Make this work
    X12, // TODO: Make this work

    fn get(self: Renderer) type {
        return switch (self) {
            .Vulkan => Vulkan,
            .OpenGL => Vulkan, // TODO: Change to OpenGL in the future
            .X12    => Vulkan, // TODO: Change to X12 in the future
        };
    }
};
