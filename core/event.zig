const std = @import("std");

const _config = @import("util/configuration.zig");
const _platform  = @import("renderer/platform.zig");
const _game = @import("game.zig");
const _collections = @import("util/collections.zig");

const Platform = _platform.Platform;
const State = _config.State;
const Game = _game.Game;
const ArrayList = _collections.ArrayList;
const logger = _config.Configuration.logger;
const ObjectHandle = _game.ObjectHandle;

pub const EventSystem = struct {
    events: []Event,
    state: State,
    clock: f64,

    pub const Event = struct {
        handlers: ArrayList(Handler),
        allocator: std.mem.Allocator,
        typ: Type,

        pub const Handler = struct {
            working: bool = false,
            ptr: *anyopaque,
            listen_fn: *const fn (*anyopaque, Argument) bool,

            fn listen(self: *Handler, argument: Argument) bool {
                self.working = true;
                defer self.working = false;
                return self.listen_fn(self.ptr, argument);
            }

            fn shutdown(self: Handler) void {
                while (self.working) {}
            }
        };

        const Type = enum {
            KeyPress,
            KeyRelease,
            MouseRight,
            MouseWheel,
            MouseLeft,

            Max,
        };

        fn new_handler(self: *Event, handler: Handler) !void {
            try self.handlers.push(handler);
        }

        fn shutdown(self: Event) void {
            for (self.handlers.items) |handler| {
                handler.shutdown();
            }
        }

        fn listen(self: *Event, argument: Argument) void {
            for (0..self.handlers.items.len) |i| {
                if(self.handlers.items[i].listen(argument)) break;
            }
        }
    };

    pub const Argument = union {
        i32: [2]i32,
        u32: [2]u32,
        f32: [2]f32,

        i16: [4]i16,
        u16: [4]u16,
        f16: [4]f16,

        i8: [16]i8,
        u8: [16]u8,
    };

    const Press = Platform.Press;
    const keys = [_]i32 {
        Platform.KeyF,
    };

    pub fn new(game: *Game, allocator: std.mem.Allocator) !EventSystem {
        const n = @intFromEnum(Event.Type.Max);
        var events = try allocator.alloc(Event, n);

        for (0..n) |i| {
            events[i] = .{
                .handlers = try ArrayList(Event.Handler).init(allocator, 0),
                .allocator = allocator,
                .typ = @enumFromInt(i),
            };
        }

        try events[@intFromEnum(Event.Type.KeyPress)].new_handler(game.object_handle.handler());
        // try events[@intFromEnum(Event.Type.KeyPress)].new_handler(game.camera.handler());
        // const obj: *ObjectHandle = @alignCast(@ptrCast(events[@intFromEnum(Event.Type.KeyPress)].handlers.items[0].ptr));
        // logger.log(.Debug, "tamanhao: {any}", .{obj.objects.items[0]});

        return .{
            .events = events,
            .state = .Running,
            .clock = Platform.get_time(),
        };
    }

    pub fn add_listener(self: *EventSystem, handle: Event.Handler, code: Event.Handler.Type) !void {
        try self.events[@intFromEnum(code)].new_handler(handle);
    }

    pub fn input(self: *EventSystem, window: *Platform.Window) void {
        Platform.poll_events();
        const current_time = Platform.get_time();
        self.clock = current_time;

        for (keys) |key| {
            if (Platform.get_key(window, key) == Press) {
                self.fire(Event.Type.KeyPress, .{ .i32 = .{ key, Press} });
            }
        }

        if (Platform.window_should_close(window)) self.state = .Closing;
    }

    fn fire(self: *EventSystem, event_type: Event.Type, argument: Argument) void {
        const code = @intFromEnum(event_type);

        if (self.events.len <= code) {
            logger.log(.Error, "Event for code '{}' not found", .{code});

            return;
        }

        self.events[code].listen(argument);
    }

    pub fn shutdown(self: EventSystem) void {
        for (self.events) |event| {
            event.shutdown();
        }
    }
};
