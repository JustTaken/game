const std = @import("std");

const _config = @import("util/configuration.zig");
const _platform  = @import("platform/platform.zig");
const _game = @import("game.zig");
const _collections = @import("util/collections.zig");
const _backend = @import("renderer/backend.zig");

const Platform = _platform.Platform;
const State = _config.State;
const ArrayList = _collections.ArrayList;
const logger = _config.Configuration.logger;
const ObjectHandle = _game.ObjectHandle;
const Game = _game.Game;
const Backend = _backend.Backend;
const Renderer = _backend.Renderer;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub const EventSystem = struct {
    events: []Event,
    state: State,
    arena: std.heap.ArenaAllocator,

    var cursor: Cursor = .{
        .x = 0,
        .y = 0,
        .changed = false,
    };

    pub const Cursor = struct {
        x: f32,
        y: f32,
        changed: bool,
    };

    pub const Event = struct {
        listeners: ArrayList(Listener),
        emiters: ArrayList(Emiter),

        pub const Listener= struct {
            working: bool = false,
            ptr: *anyopaque,
            listen_fn: *const fn (*anyopaque, Argument) bool,

            fn listen(self: *Listener, argument: Argument) bool {
                self.working = true;
                defer self.working = false;
                return self.listen_fn(self.ptr, argument);
            }

            fn shutdown(self: Listener) void {
                while (self.working) {}
            }
        };

        pub const Emiter = struct {
            changed: bool,
            value: Argument,
        };

        const Type = enum {
            KeyPress,
            MouseWheel,
            MouseClick,
            MouseMove,
            WindowResize,

            Max,
        };

        fn new_listener(self: *Event, listener: Listener) !void {
            try self.listeners.push(listener);
        }

        fn new_emiter(self: *Event) !*Emiter {
            const emiter: Emiter = .{
                .changed = false,
                .value = .{ .u32  = .{0, 0} },
            };

            try self.emiters.push(emiter);
            return self.emiters.get_last_mut();
        }

        fn shutdown(self: Event) void {
            for (self.listeners.items) |listener| {
                listener.shutdown();
            }
        }

        fn listen(self: *Event, argument: Argument) void {
            for (0..self.listeners.items.len) |i| {
                if(self.listeners.items[i].listen(argument)) break;
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

        i8: [8]i8,
        u8: [8]u8,
    };

    pub fn new() !EventSystem {
        const n = @intFromEnum(Event.Type.Max);
        var events = try allocator.alloc(Event, n);

        for (0..n) |i| {
            events[i] = .{
                .listeners = try ArrayList(Event.Listener).init(allocator, 1),
                .emiters = try ArrayList(Event.Emiter).init(allocator, 1),
            };
        }

        return .{
            .events = events,
            .state = .Running,
            .arena = arena,
        };
    }

    pub fn add_listener(self: *EventSystem, handle: Event.Listener, code: Event.Type) !void {
        try self.events[@intFromEnum(code)].new_listener(handle);
    }

    pub fn add_emiter(self: *EventSystem, code: Event.Type) !*Event.Emiter {
        return try self.events[@intFromEnum(code)].new_emiter();
    }

    pub fn cursor_changed(window: ?*Platform.Window, x: f64, y: f64) callconv (.C) void {
        cursor = .{
            .x = @floatCast(x),
            .y = @floatCast(y),
            .changed = true,
        };

        Platform.set_cursor_position(window, 0.0, 0.0);
    }

    pub fn input(self: *EventSystem) void {
        for (0..self.events.len) |i| {
            for (0..self.events[i].emiters.items.len) |k| {
                if (self.events[i].emiters.items[k].changed) {
                    self.events[i].listen(self.events[i].emiters.items[k].value);
                    if (i != 0) {
                        self.events[i].emiters.items[k].changed = false;
                    }
                }
            }
        }

        // if (cursor.changed) {
        //     self.fire(Event.Type.MouseMove, .{ .f32 = .{ cursor.x, cursor.y } });

        //     cursor.changed = false;
        // }

        // for (keys) |key| {
            // if (Platform.get_key(window, key) == Press) {
                // self.fire(Event.Type.KeyPress, .{ .i32 = .{ key, Press} });
            // }
        // }

        // if (Platform.window_should_close(window)) self.state = .Closing;
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

        _ = self.arena.deinit();
    }
};
