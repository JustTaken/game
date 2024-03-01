const std = @import("std");

const _game = @import("game.zig");
const _event = @import("event.zig");
const _config = @import("util/configuration.zig");
const _renderer = @import("renderer/backend.zig");
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
            .X12 => logger.log(.Fatal, "DirectX12 renderer not implemented yet", .{}),
        }

        unreachable;
    };

    return struct {
        game: Game,
        backend: Backend(T),
        event_system: EventSystem,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn new() Self {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();

            const game: Game = .{
                .name = Configuration.application_name,
                .window = .{
                    .width = Configuration.default_width,
                    .height = Configuration.default_height,
                },
            };

            const event_system = EventSystem.default(allocator) catch {
                logger.log(.Fatal, "Could not create event handle system", .{});

                unreachable;
            };

            const backend = Backend(T).new() catch {
                logger.log(.Fatal, "Failed to initialize backend", .{});

                unreachable;
            };

            logger.log(.Info, "Application successfully initialized", .{});

            return .{
                .game = game,
                .backend = backend,
                .event_system = event_system,
                .allocator = allocator,
            };
        }

        pub fn run(self: *Self) void {
            while (self.event_system.state != .Closing) {
                if (self.event_system.state != .Suspended) {
                    self.backend.draw() catch {
                        self.shutdown();
                        logger.log(.Fatal, "Unrecoverable problem occoured on frame, closing", .{});

                        unreachable;
                    };

                    self.game.update();
                    self.event_system.input(self.backend.window);
                }

            }

            self.shutdown();
        }

        pub fn shutdown(self: *Self) void {
            self.backend.shutdown();
        }
    };
}
