const std = @import("std");

const _collections = @import("util/collections.zig");
const _math = @import("util/math.zig");
const _assets = @import("renderer/assets.zig");
const _event = @import("event.zig");
const _platform = @import("renderer/platform.zig");
const _configuration = @import("util/configuration.zig");

const Vec = _math.Vec;
const Matrix = _math.Matrix;
const ArrayList = _collections.ArrayList;
const ObjectType = _assets.Object.Type;
const EventSystem = _event.EventSystem;
const Platform = _platform.Platform;
const configuration = _configuration.Configuration;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub const Game = struct {
    object_handle: ObjectHandle,
    camera: Camera,

    pub fn new() !Game {
        var object_handle = try ObjectHandle.new();
        try object_handle.add_object(.{
            .model = Matrix.scale(0.3, 0.3, 0.3),
            .color = Matrix.scale(0.1, 0.9, 0.3),
            .typ = .Plane,
        });

        return .{
            .object_handle = object_handle,
            .camera = Camera.init(.{
                .x = 0.0,
                .y = 0.0,
                .z = -1.0,
            }),
        };
    }

    pub fn update(self: *Game) !void {
        _ = self;

        // std.debug.print("proj: {d}\n", .{self.camera.proj});
    }

    pub fn shutdown(_: *Game) void {
        _ = arena.deinit();
    }

    fn render(_: *Game) !void {}
    fn on_resize(_: *Game) !void {}
};

pub const ObjectHandle = struct {
    objects: ArrayList(Object),
    to_update: ArrayList(Update),

    pub inline fn has_change(self: ObjectHandle) bool {
        return self.to_update.items.len > 0;
    }

    pub fn add_object(self: *ObjectHandle, object: Object) !void {
        try self.to_update.push(.{
            .data = .new,
            .id = self.objects.items.len,
        });
        try self.objects.push(object);
    }

    pub inline fn clear_updates(self: *ObjectHandle) !void {
        try self.to_update.clear();
    }

    pub fn handler(self: *ObjectHandle) EventSystem.Event.Listener {
        return .{
            .ptr = self,
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *ObjectHandle = @ptrCast(@alignCast(ptr));

        switch (argument.i32[0]) {
            Platform.KeyF => {
                self.update_object(.{
                    .data = .{
                        .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(0.0, 0.0, 0.01)),
                    },
                    .id = 0,
                }) catch {
                    return false;
                };
            },
            else => {},
        }

        return false;
    }

    fn update_object(self: *ObjectHandle, update: Update) !void {
        if (update.id >= self.objects.items.len) return error.OutOfLength;

        switch (update.data) {
            .color => |color| self.objects.items[update.id].color = color,
            .model => |model| self.objects.items[update.id].model = model,
            .new => unreachable,
        }

        try self.to_update.push(update);
    }

    fn new() !ObjectHandle {
        return .{
            .objects = try ArrayList(Object).init(allocator, 0),
            .to_update = try ArrayList(Update).init(allocator, 0),
        };
    }

    const Object = struct {
        model: [4][4]f32,
        color: [4][4]f32,
        typ: ObjectType,
        id: u16 = undefined,

        fn new(typ: ObjectType, model: [4][4]f32, color: [4][4]f32) Object {
            return .{
                .model = model,
                .color = color,
                .typ = typ,
            };
        }

        fn default() Object {
            return .{
                .model = Matrix.scale(0.5, 0.5, 0.5),
                .typ = ObjectType.Plane,
                .color = Matrix.scale(1.0, 1.0, 1.0),
            };
        }
    };

    const Update = struct {
        data: Data,
        id: usize,

        const Data = union(enum) {
            color: [4][4]f32,
            model: [4][4]f32,
            new: void,
        };
    };
};

pub const Camera = struct {
    proj: [4][4]f32,
    up: Vec,
    eye: Vec,
    center: Vec,

    changed: bool = true,

    pub inline fn init(eye: Vec) Camera {
        return .{
            .proj = Matrix.perspective(std.math.pi / 4.0, @as(f32, @floatFromInt(configuration.default_width)) / @as(f32, @floatFromInt(configuration.default_height)), 0.1, 10.0),
            .eye = eye,
            .center = .{
                .x = 0.0,
                .y = 0.0,
                .z = 0.0,
            },
            .up = .{
                .x = 0.0,
                .y = -1.0,
                .z = 0.0,
            },
        };
    }

    pub fn handler(self: *Camera) EventSystem.Event.Listener {
        return .{
            .ptr = self,
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *Camera = @alignCast(@ptrCast(ptr));

        self.proj = Matrix.perspective(std.math.pi / 4.0, @as(f32, @floatFromInt(argument.u32[0])) / @as(f32, @floatFromInt(argument.u32[1])), 0.1, 10.0);
        self.changed = true;

        return false;
    }

    pub inline fn view_matrix(self: *Camera) [4][4]f32 {
        const direction = Vec.sub(self.eye, self.center).normalize();
        const right = Vec.cross(direction, self.up).normalize();
        self.up = Vec.cross(right, direction);

        return [4][4]f32 {
            [4]f32 {right.x, self.up.x, direction.x, 0.0},
            [4]f32 {right.y, self.up.y, direction.y, 0.0},
            [4]f32 {right.z, self.up.z, direction.z, 0.0},
            [4]f32 {-self.eye.x, -self.eye.y, -self.eye.z, 1.0},
        };
    }

    fn mouse(self: *Camera, x: i32, y: i32) void {
        var direction = Vec.sub(self.eye, self.center);
        const right = Vec.cross(direction, self.up);

        const rotate = Matrix.mult(
            Matrix.rotate(
                @as(f32, @floatFromInt(x)) * std.math.pi * 0.1 / -180.0,
                self.up.normalize()
            ),
            Matrix.rotate(
                @as(f32, @floatFromInt(y)) * std.math.pi * 0.1 / -180.0,
                right.normalize()
            )
        );

        direction = Vec.mult(
            direction,
            rotate
        );

        self.center = Vec.sum(self.eye, direction);
        self.up = Vec.cross(right, direction).normalize();
        self.changed = true;
    }

    fn move_foward(self: *Camera, speed: f32) void {
        const delta = Vec.sub(self.eye, self.center).normalize().scale(speed * 10.0);
        self.eye = Vec.sum(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
        self.changed = true;
    }

    fn move_backward(self: *Camera, speed: f32) void {
        const delta = Vec.sub(self.eye, self.center).normalize().scale(speed * 10.0);
        self.eye = Vec.sub(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
        self.changed = true;
    }

    fn move_right(self: *Camera, speed: f32) void {
        const delta = Vec.cross(Vec.sub(self.eye, self.center), self.up).normalize().scale(speed * 10.0);
        self.eye = Vec.sum(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
        self.changed = true;
    }

    fn move_left(self: *Camera, speed: f32) void {
        const delta = Vec.cross(Vec.sub(self.eye, self.center), self.up).normalize().scale(speed * 10.0);
        self.eye = Vec.sub(delta, self.eye);
        self.center = Vec.sub(delta, self.center);
        self.changed = true;
    }

    fn move_up(self: *Camera, speed: f32) void {
        self.eye = Vec.sub(self.up.normalize().scale(speed), self.eye);
        self.center = Vec.sub(self.up.normalize().scale(speed), self.center);
        self.changed = true;
    }

    fn move_down(self: *Camera, speed: f32) void {
        self.eye = Vec.sum(self.up.normalize().scale(speed), self.eye);
        self.center = Vec.sum(self.up.normalize().scale(speed), self.center);
        self.changed = true;
    }
};
