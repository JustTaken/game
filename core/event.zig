const std = @import("std");

const _config = @import("util/configuration.zig");
const _wrapper = @import("renderer/wrapper.zig");

const Glfw = _wrapper.Glfw;
const State = _config.State;

const logger = _config.Configuration.logger;

pub const EventSystem = struct {
    events: [@intCast(@intFromEnum(Event.Type.Max))]Event,
    clock: f64,
    state: State,

    pub const Event = struct {
        handlers: []Handler,
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

            inline fn shutdown(self: Handler) void {
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

        fn new_handler(self: Event, handler: Handler) !void {
            self.allocator.realoc(self.handlers, self.handlers.len + 1);
            self.handlers[self.handlers.len] = handler;
        }

        fn shutdown(self: Event) void {
            for (self.handlers) |handler| {
                handler.shutdown();
            }
        }

        fn listen(self: *Event, argument: Argument) void {
            for (0..self.handlers.len) |i| {
                if(self.handlers[i].listen(argument)) break;
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

    const Press = Glfw.Press;

    const keys = [_]i32 {
        Glfw.KeyF,
    };

    pub fn default(allocator: std.mem.Allocator) !EventSystem {
        const n = @intFromEnum(Event.Type.Max);
        var events: [n]Event= undefined;

        for (0..n) |i| {
            events[i] = .{
                .handlers = try allocator.alloc(Event.Handler, 0),
                .allocator = allocator,
                .typ = @enumFromInt(i),
            };
        }

        return .{
            .events = events,
            .clock = Glfw.get_time(),
            .state = .Running,
        };
    }

    pub fn input(self: *EventSystem, window: *Glfw.Window) void {
        Glfw.poll_events();

        const current_time = Glfw.get_time();

        self.clock = current_time;

        if (Glfw.window_should_close(window)) {
            self.state = .Closing;
            logger.log(.Debug, "Total time passed inside the game {} seconds", .{self.clock});
        }

        for (keys) |key| {
            if (Glfw.get_key(window, key) == Press) {
                self.fire(Event.Type.KeyPress, .{ .i32 = .{ key, Press} }) catch {
                    logger.log(.Error, "Could not fire event", .{});
                };
            }
        }
    }

    fn fire(self: *EventSystem, event_type: Event.Type, argument: Argument) !void {
        const code = @intFromEnum(event_type);

        if (self.events.len <= code) {
            logger.log(.Error, "Event for code '{}' not found", .{code});

            return error.EventNotFound;
        }

        self.events[code].listen(argument);
    }

    pub fn shutdown(self: EventSystem) void {
        for (self.events) |event| {
            event.shutdown();
        }
    }

};
