const std = @import("std");

const _game = @import("game.zig");
const _event = @import("event.zig");
const _config = @import("util/configuration.zig");
const _renderer = @import("renderer/backend.zig");
const _font = @import("asset/font.zig");
const _vulkan =  @import("renderer/vulkan.zig");

const Game = _game.Game;
const Vulkan = _vulkan.Vulkan;
const Backend = _renderer.Backend;
const Renderer = _renderer.Renderer;
const EventSystem = _event.EventSystem;
const Configuration = _config.Configuration;

pub const logger = Configuration.logger;

pub fn Application(comptime renderer: Renderer) type {
    const T = blk: {
        switch (renderer) {
            .Vulkan => break :blk Vulkan,
            .OpenGL => logger.log(.Fatal, "OpenGL renderer not implemented yet", .{}),
            .X12    => logger.log(.Fatal, "DirectX12 renderer not implemented yet", .{}),
        }

        unreachable;
    };

    return struct {
        game: Game,
        backend: Backend(T),
        event_system: EventSystem,

        const Self = @This();

        pub fn new(allocator: std.mem.Allocator) Self {
            const game: Game = Game.new(allocator) catch {
                logger.log(.Fatal, "Could not create game instance", .{});

                unreachable;
            };

            const event_system: EventSystem = EventSystem.new() catch {
                logger.log(.Fatal, "Could not create event handle system", .{});

                unreachable;
            };


            const backend: Backend(T) = Backend(T).new() catch {
                logger.log(.Fatal, "Failed to initialize backend", .{});

                unreachable;
            };

            logger.log(.Info, "Application successfully initialized", .{});

            return .{
                .game = game,
                .backend = backend,
                .event_system = event_system,
            };
        }

        pub fn run(self: *Self) void {
            self.event_system.init(self.backend.window, &self.game, T, &self.backend);
            while (self.event_system.state != .Closing) {
                if (self.event_system.state != .Suspended) {
                    self.backend.draw(&self.game) catch {
                        self.shutdown();
                        logger.log(.Fatal, "Unrecoverable problem occoured on frame, closing", .{});

                        unreachable;
                    };

                    self.game.update() catch {
                        self.shutdown();
                        logger.log(.Fatal, "Unrecoverable problem at game instance update", .{});

                        unreachable;

                    };
                    self.event_system.input(self.backend.window);
                }
            }

            self.shutdown();
        }

        pub fn shutdown(self: *Self) void {
            self.game.shutdown();
            self.event_system.shutdown();
            self.backend.shutdown();
        }
    };
}
