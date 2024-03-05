const std = @import("std");
const _collections = @import("util/collections.zig");
const _math = @import("util/math.zig");
const _assets = @import("renderer/assets.zig");
const _event = @import("event.zig");
const _platform = @import("renderer/platform.zig");

const Vec = _math.Vec;
const Matrix = _math.Matrix;
const ArrayList = _collections.ArrayList;
const ObjectType = _assets.Object.Type;
const EventSystem = _event.EventSystem;
const Platform = _platform.Platform;

const TO_RAD = _math.TO_RAD;
var colors: [3]f32 = .{0, 0, 0};

pub const Game = struct {
    object_handle: ObjectHandle,
    camera: Camera,

    pub fn new() !Game {
        var object_handle = try ObjectHandle.new();
        std.debug.print("before the crash\n", .{});
        try object_handle.objects.push(ObjectHandle.Object.default());

        return .{
            .object_handle = object_handle,
            .camera = Camera.init(.{
                .x = 0.0,
                .y = 0.0,
                .z = 1.0,
            }),
        };
    }

    pub fn update(self: *Game) !void {
        _ = self;
        // if (frames == 0) {
        //     try self.object_handle.add_object(ObjectHandle.Object.default());
        // } else if (frames % 2 == 0) {
        //     const index = 0;
        //     std.debug.print("len: {d}\n", .{self.object_handle.objects.items.len});
        //     try self.object_handle.update_object(.{
        //         .data = .{
        //             .model = Matrix.mult(Matrix.rotate(0.001, .{
        //                 .x = 0.0,
        //                 .y = 0.0,
        //                 .z = 1.0,
        //                 }), self.object_handle.objects.items[index].model),
        //         },
        //         .id = index,
        //     });
        // } else {
        //     const index = 0;

        //     colors[2] += 0.1;

        //     if (colors[2] >= 1.0) {
        //         colors[2] = 0;
        //         colors[1] += 0.1;
        //         if (colors[1] >= 1.0) {
        //             colors[1] = 0;
        //             colors[0] += 0.1;
        //             if (colors[0] >= 1.0) {
        //                 colors[0] = 0;
        //             }
        //         }
        //     }

        //     const matrix = Matrix.scale(colors[0], colors[1], colors[2]);

        //     try self.object_handle.update_object(.{
        //         .data = .{
        //             .color = matrix
        //         },
        //         .id = index,
        //     });
        // }
    }

    fn render(_: *Game) !void {}
    fn on_resize(_: *Game) !void {}
};

pub const ObjectHandle = struct {
    objects: ArrayList(Object),
    to_update: ArrayList(Update),

    pub fn has_change(self: ObjectHandle) bool {
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

    pub fn handler(self: *ObjectHandle) EventSystem.Event.Handler {
        return .{
            .ptr = @ptrCast(@alignCast(self)),
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *ObjectHandle = @ptrCast(@alignCast(ptr));
        std.debug.print("new len: {any}\n", .{self.objects.items.len});

        switch (argument.i32[0]) {
            Platform.KeyF => {
                // self.update_object(.{
                //     .data = .{
                //         .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(0.01, 0.0, 0.0)),
                //     },
                //     .id = 0,
                // }) catch {
                //     return false;
                // }
            },
            else => {},
        }

        return false;
    }

    fn update_object(self: *ObjectHandle, update: Update) !void {
        if (update.id > self.objects.items.len) return error.OutOfLength;

        switch (update.data) {
            .color => |color| self.objects.items[update.id].color = color,
            .model => |model| self.objects.items[update.id].model = model,
            .new => unreachable,
        }

        try self.to_update.push(update);
    }

    fn new() !ObjectHandle {
        var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
        const allocator = gpa.allocator();
        const objects = try ArrayList(Object).init(allocator, null);

        return .{
            .objects = objects,
            .to_update = try ArrayList(Update).init(allocator, 1),
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
    up: Vec,
    eye: Vec,
    center: Vec,

    changed: bool = true,

    pub inline fn init(eye: Vec) Camera {
        return .{
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

    pub fn handler(self: *Camera) EventSystem.Event.Handler {
        return .{
            .ptr = self,
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *Camera = @alignCast(@ptrCast(ptr));
        _ = self;
        switch (argument.i32[0]) {
            else => {},
        }

        return false;
    }


    pub inline fn view_matrix(self: *Camera) [4][4]f32 {
        const direction = Vec.sub(self.eye, self.center).normalize();
        const right = Vec.cross(direction, self.up.normalize()).normalize();

        self.up = Vec.cross(right, direction);

        return [4][4]f32 {
            [4]f32 {right.x, self.up.x, -direction.x, 0.0},
            [4]f32 {right.y, self.up.y, -direction.y, 0.0},
            [4]f32 {right.z, self.up.z, -direction.z, 0.0},
            [4]f32 {-Vec.dot(right, self.eye), -Vec.dot(self.up, self.eye), -Vec.dot(direction, self.eye), 1.0},
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
