const std            = @import("std");

const _math          = @import("../math/math.zig");
const _object        = @import("../assets/object.zig");
const _event         = @import("../event/event.zig");
const _platform      = @import("../platform/platform.zig");
const _collections   = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _camera        = @import("camera.zig");
const _font          = @import("../assets/font.zig");

const Vec            = _math.Vec;
const Matrix         = _math.Matrix;

const ArrayList      = _collections.ArrayList;
const Allocator      = std.mem.Allocator;
const Camera         = _camera.Camera;

const ObjectHandler  = _object.ObjectHandler;
const ObjectType     = ObjectHandler.Type;

const EventSystem    = _event.EventSystem;
const Listener       = EventSystem.Event.Listener;
const Argument       = EventSystem.Argument;

const Platform       = _platform.Platform;
const KeyMap         = _platform.KeyMap;

const configuration  = _configuration.Configuration;

pub const Container = struct {
    object_handler: ObjectHandler,
    objects:   ArrayList(Object),
    updates:   ArrayList(Update),
    camera:    Camera,

    const Update = struct {
        change: Change,
        id:     u16,

        const Change = enum(u16) {
            color,
            model,
            new
        };

        const Data = struct {
            value:     [4][4]f32,
            change:    Change,
            operation: Operation,

            const Operation = enum {
                place,
                add,
            };
        };
    };

    const Object = struct {
        model: [4][4]f32,
        color: [4][4]f32,
        typ:   ObjectType,
        id:    u16,
    };

    fn add_object(self: *Container, object: Object) !void {
        try self.updates.push(.{ .change = .new, .id = @intCast(self.objects.items.len) });
        try self.objects.push(object);
    }

    fn update_object(self: *Container, data: Update.Data, id: u16) !void {
        const to_change: *[4][4]f32 = switch (data.change) {
            .model => &self.objects.items[id].model,
            .color => &self.objects.items[id].color,
            .new   => unreachable
        };

        const new_matrix = switch (data.operation) {
            .add   => Matrix.mult(data.value, to_change.*),
            .place => data.value,
        };

        to_change.* = new_matrix;

        try self.updates.push(.{
            .id     = id,
            .change = data.change
        });
    }

    pub fn update(self: *Container) !void {
        if (self.objects.items.len == 0) {
            try self.add_object(.{
                .model = Matrix.scale(1.0, 1.0, 1.0),
                .color = Matrix.scale(1.0, 1.0, 1.0),
                .typ   = .cone,
                .id    = undefined,
            });

            try self.add_object(.{
                .model = Matrix.translate(1.0, 0.0, 0.0),
                .color = Matrix.scale(0.0, 1.0, 1.0),
                .typ = .m,
                .id = undefined,
            });
        }
    }

    pub fn keyboard_listener(self: *Container) Listener {
        return .{
            .ptr       = self,
            .listen_fn = listen_keyboard,
        };
    }

    pub fn mouse_listener(self: *Container) Listener {
        return .{
            .ptr       = self,
            .listen_fn = listen_mouse,
        };
    }

    pub fn resize_listener(self: *Container) Listener {
        return .{
            .ptr       = self,
            .listen_fn = listen_resize,
        };
    }

    pub fn click_listener(self: *Container) Listener {
        return .{
            .ptr       = self,
            .listen_fn = listen_click,
        };
    }

    pub fn listen_keyboard(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_keyboard(argument);
    }

    pub fn listen_mouse(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_mouse(argument);
    }

    pub fn listen_resize(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_resize(argument);
    }

    pub fn listen_click(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_click(argument);
    }

    pub fn new(allocator: Allocator) !Container {

        return .{
            .object_handler = try ObjectHandler.new("assets/font/font.ttf", "assets", allocator),
            .objects        = try ArrayList(Object).init(allocator, 1),
            .updates        = try ArrayList(Update).init(allocator, 1),
            .camera         = Camera.init(.{
                .x =   0.0,
                .y =   0.0,
                .z = - 1.0,
            }),
        };
    }

    pub fn shutdown(self: *Container) void {
        self.objects.deinit();
        self.updates.deinit();
        self.object_handler.deinit();
    }
};
