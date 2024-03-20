const std          = @import("std");

const _config      = @import("../util/configuration.zig");
const _collections = @import("../collections/collections.zig");

const State        = _config.State;
const ArrayList    = _collections.ArrayList;
const Allocator    = std.mem.Allocator;

const logger       = _config.Configuration.logger;

pub const EventSystem = struct {
    events: []Event,
    state: State,

    pub const Event = struct {
        listeners: ArrayList(Listener),
        emiters: ArrayList(Emiter),

        pub const Emiter = struct {
            value:         Argument,
            changed:       bool,
            reset_on_emit: bool,
        };

        const Type = enum {
            KeyPress,
            MouseWheel,
            MouseClick,
            MouseMove,
            WindowResize,
        };

        pub const Listener= struct {
            working: bool = false,
            ptr: *anyopaque,
            listen_fn: *const fn (*anyopaque, Argument) bool,

            fn listen(self: *Listener, argument: Argument) bool {
                self.working = true;
                defer self.working = false;

                return self.listen_fn(self.ptr, argument);
            }
        };

        fn new_listener(self: *Event, listener: Listener) !void {
            try self.listeners.push(listener);
        }

        fn new_emiter(self: *Event, reset_on_emit: bool) !*Emiter {
            const emiter: Emiter = .{
                .changed = false,
                .reset_on_emit = reset_on_emit,
                .value = .{ .u32  = .{0, 0} },
            };

            try self.emiters.push(emiter);
            return self.emiters.get_last_mut();
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

    pub fn new(allocator: Allocator) !EventSystem {
        const n = @typeInfo(Event.Type).Enum.fields.len;
        var events = try allocator.alloc(Event, n);

        for (0..n) |i| {
            events[i] = .{
                .listeners = try ArrayList(Event.Listener).init(allocator, 1),
                .emiters   = try ArrayList(Event.Emiter).init(allocator, 1),
            };
        }

        return .{
            .events = events,
            .state  = .Running,
        };
    }

    pub fn add_listener(self: *EventSystem, handle: Event.Listener, code: Event.Type) !void {
        try self.events[@intFromEnum(code)].new_listener(handle);
    }

    pub fn add_emiter(self: *EventSystem, code: Event.Type, reset_on_emit: bool) !*Event.Emiter {
        return try self.events[@intFromEnum(code)].new_emiter(reset_on_emit);
    }

    pub fn input(self: *EventSystem) void {
        for (self.events) |*event| {
            for (event.emiters.items) |*emiter| {
                if (emiter.changed) {
                    event.listen(emiter.value);
                    emiter.changed = !emiter.reset_on_emit;
                }
            }
        }
    }

    fn fire(self: *EventSystem, event_type: Event.Type, argument: Argument) void {
        const code = @intFromEnum(event_type);

        if (self.events.len <= code) {
            logger.log(.Error, "Event for code '{}' not found", .{code});

            return;
        }

        self.events[code].listen(argument);
    }
};
