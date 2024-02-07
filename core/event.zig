const std = @import("std");
const _utility = @import("utility.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

const logger = _utility.Configuration.logger;

pub const EventSystem = struct {
    events: [@intCast(@intFromEnum(Event.Type.Max))]Event,
    clock: f64,

    pub const Event = struct {
        handlers: []Handler,
        allocator: std.mem.Allocator,
        typ: Type,

        pub const Handler = struct {
            ptr: *anyopaque,
            listen_fn: *const fn (*anyopaque, Argument) bool,

            fn listen(self: Handler, argument: Argument) bool {
                return self.listen_fn(self.ptr, argument);
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

    const Press = c.GLFW_PRESS;

    const keys = [_]i32 {
        c.GLFW_KEY_F,
    };

    fn get_key(window: *c.GLFWwindow, key: i32) i32 {
        return c.glfwGetKey(window, key);
    }

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
            .clock = c.glfwGetTime(),
        };
    }

    pub fn input(self: *EventSystem, window: *c.GLFWwindow) void {
        c.glfwPollEvents();

        const current_time = c.glfwGetTime();
        const delta = current_time - self.clock;

        self.clock = current_time;
        _ = delta;

        for (keys) |key| {
            if (get_key(window, key) == Press) {
                self.fire(Event.Type.KeyPress, .{ .i32 = .{ key, Press} }) catch {
                    logger.log(.Error, "Could not fire event", .{});
                };
            }
        }
    }

    fn fire(self: EventSystem, event_type: Event.Type, argument: Argument) !void {
        const code = @intFromEnum(event_type);

        if (self.events.len <= code) {
            logger.log(.Error, "Event for code '{}' not found", .{code});
            return error.EventNotFound;
        }

        for (self.events[code].handlers) |handler| {
            if(handler.listen(argument)) break;
        }
    }
};

