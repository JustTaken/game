const std = @import("std");
const _game = @import("game.zig");
const _event = @import("event.zig");
const _utility = @import("utility.zig");
const _renderer = @import("renderer/backend.zig");

const Game = _game.Game;
const State = _utility.State;
const Backend = _renderer.Backend;
const EventSystem = _event.EventSystem;
const configuration = _utility.Configuration;

pub const Application = struct {
    game: Game,
    backend: Backend,
    event_system: EventSystem,

    allocator: std.mem.Allocator,
    state: State = .Suspended,

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
            logger.log(.Fatal, "Could not create event handler system", .{});
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
            .state = .Running,
        };
    }

    pub fn run(self: *Application) void {
        while (self.state != .Closing) {
            if (self.state != .Suspended) {
                // self.event_system.input(self.backend.window.handler);
                self.game.update();

                self.state = .Closing;
            }
        }

        self.shutdown();
    }

    pub fn shutdown(self: *Application) void {
        self.backend.shutdown();
    }
};

pub const Test = struct {
    const Self = @This();
    pub fn listen(ptr: *anyopaque, code: u8) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = code;
    }

    fn handler(self: *Self) EventSystem.Event.Handler {
        return .{
            .ptr = self,
            .listen_fn = listen,
        };
    }
};
