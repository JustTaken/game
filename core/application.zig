const std = @import("std");

const _game = @import("game.zig");
const _event = @import("event.zig");
const _config = @import("util/configuration.zig");
const _renderer = @import("renderer/backend.zig");
const _wrapper = @import("renderer/wrapper.zig");
const _math = @import("util/math.zig");

const Game = _game.Game;
const State = _config.State;
const Backend = _renderer.Backend;
const EventSystem = _event.EventSystem;
const configuration = _config.Configuration;
const Vec = _math.Vec;

pub const Application = struct {
    game: Game,
    backend: Backend,
    event_system: EventSystem,

    allocator: std.mem.Allocator,

    pub const logger = configuration.logger;

    pub fn new() Application {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        const game: Game = .{
            .window = .{
                .width = configuration.default_width,
                .height = configuration.default_height,
            },
            .name = configuration.application_name,
        };

        const event_system = EventSystem.default(allocator) catch {
            logger.log(.Fatal, "Could not create event handle system", .{});
            unreachable;
        };

        const backend = Backend.new() catch {
            logger.log(.Fatal, "Failed to initialize backend", .{});
            unreachable;
        };


       return .{
            .game = game,
            .backend = backend,
            .event_system = event_system,
            .allocator = allocator,
        };
    }

    pub fn run(self: *Application) void {
        while (self.event_system.state != .Closing) {
            if (self.event_system.state != .Suspended) {
                self.backend.draw() catch {
                    configuration.logger.log(.Error, "Unrecoverable problem occoured on frame", .{});
                    self.event_system.state = .Closing;
                };

                self.game.update();
                self.event_system.input(self.backend.get_window());
            }
        }

        self.shutdown();
    }

    pub fn shutdown(self: *Application) void {
        self.backend.shutdown();
    }
};
