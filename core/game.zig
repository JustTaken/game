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
        for (0..5) |i| {
            try object_handle.add_object(.{
                .model = Matrix.translate(0.0, 0.0, @as(f32, @floatFromInt(i)) * 2),
                .color = Matrix.scale(0.1, @as(f32, @floatFromInt(i)) * 0.1, 0.3),
                .typ = .Cube,
            });
        }

        try object_handle.add_object(.{
            .model = Matrix.translate(2.0, 2.0, 1.0),
            .color = Matrix.scale(0.1, 0.1, 0.7),
            .typ = .Cone,
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

    pub inline fn handler(self: *ObjectHandle) EventSystem.Event.Listener {
        return .{
            .ptr = self,
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *ObjectHandle = @ptrCast(@alignCast(ptr));

        switch (argument.i32[0]) {
            Platform.Right => {
                self.update_object(.{
                    .data = .{ .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(0.1, 0.0, 0.0)), },
                    .id = 0,
                }) catch { return false; };
            },

            Platform.Left => {
                self.update_object(.{
                    .data = .{ .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(-0.1, 0.0, 0.0)), },
                    .id = 0,
                }) catch { return false; };
            },

            Platform.Up => {
                self.update_object(.{
                    .data = .{ .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(0.0, 0.1, 0.0)), },
                    .id = 0,
                }) catch { return false; };
            },

            Platform.Down => {
                self.update_object(.{
                    .data = .{ .model = Matrix.mult(self.objects.items[0].model, Matrix.translate(0.0, -0.1, 0.0)), },
                    .id = 0,
                }) catch { return false; };
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
    view: [4][4]f32,
    eye: Vec,

    changed: bool = true,

    const y_rotation: [4][4]f32 = .{
        [4]f32 { 0.0, 0.0, 1.0, 0.0 },
        [4]f32 { 0.0, 1.0, 0.0, 0.0 },
        [4]f32 { -1.0, 0.0, 0.0, 0.0 },
        [4]f32 { 0.0, 0.0, 0.0, 1.0 },
    };

    const x_rotation: [4][4]f32 = .{
        [4]f32 { 1.0, 0.0, 0.0, 0.0 },
        [4]f32 { 0.0, 0.0, -1.0, 0.0 },
        [4]f32 { 0.0, 1.0, 0.0, 0.0 },
        [4]f32 { 0.0, 0.0, 0.0, 1.0 },
    };

    const fov: f32 = std.math.pi * 0.25; // 45º -> (45 * std.math.pi / 180.0)
    const near: f32 = 0.1;
    const far: f32 = 10.0;

    pub inline fn init(eye: Vec) Camera {
        const right_vec: Vec = .{.x = 1.0, .y = 0.0, .z = 0.0};
        const up_vec: Vec = .{.x = 0.0, .y = -1.0, .z = 0.0};
        const direction: Vec = .{.x = 0.0, .y = 0.0, .z = 1.0};

        return .{
            .eye = eye,
            .proj = Matrix.perspective(
                fov,
                @as(f32, @floatFromInt(configuration.default_width)) / @as(f32, @floatFromInt(configuration.default_height)),
                near,
                far
            ),
            .view = .{
                [4]f32 {right_vec.x, up_vec.x, direction.x, 0.0},
                [4]f32 {right_vec.y, up_vec.y, direction.y, 0.0},
                [4]f32 {right_vec.z, up_vec.z, direction.z, 0.0},
                [4]f32 {-eye.dot(right_vec), -eye.dot(up_vec), -eye.dot(direction), 1.0},
            },
        };
    }

    pub fn handler_resize(self: *Camera) EventSystem.Event.Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_resize,
        };
    }

    pub fn handler_keyboard(self: *Camera) EventSystem.Event.Listener {
        return .{
            .ptr= self,
            .listen_fn = listen_keyboard,
        };
    }

    pub fn handler_mouse(self: *Camera) EventSystem.Event.Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_mouse,
        };
    }

    pub fn listen_keyboard(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *Camera = @alignCast(@ptrCast(ptr));

        switch (argument.i32[0]) {
            Platform.Space => self.up(0.01),
            Platform.Control => self.down(0.01),
            Platform.W => self.foward(0.01),
            Platform.A => self.left(0.01),
            Platform.S => self.backward(0.01),
            Platform.D => self.right(0.01),
            Platform.C => self.centralize(),
            else => { },
        }

        return false;
    }

    pub fn listen_mouse(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *Camera = @alignCast(@ptrCast(ptr));
        // _ = argument;
        self.mouse(argument.f32[0] * 0.001, argument.f32[1] * 0.001);
        // self.mouse(0, 0);
        return false;
    }

    pub fn listen_resize(ptr: *anyopaque, argument: EventSystem.Argument) bool {
        const self: *Camera = @alignCast(@ptrCast(ptr));

        self.proj = Matrix.perspective(
            fov,
            @as(f32, @floatFromInt(argument.u32[0])) / @as(f32, @floatFromInt(argument.u32[1])),
            near,
            far
        );
        self.changed = true;

        return false;
    }

    fn mouse(self: *Camera, x: f32, y: f32) void {
        const MAX = 5;
        if (x > MAX or y > MAX) return;
        if (x < -MAX or y < -MAX) return;

        var direction = Vec {
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2],
        };

        var up_vec: Vec = .{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1],
        };

        var right_vec = Vec {
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0],
        };

        right_vec = right_vec.sum(right_vec.mult(y_rotation).scale(-x)).normalize();
        up_vec = up_vec.sum(direction.scale(-y)).normalize();
        direction = up_vec.cross(right_vec);
        up_vec = right_vec.cross(direction);

        self.view = .{
            [4]f32 { right_vec.x, up_vec.x, direction.x, 0.0 },
            [4]f32 { right_vec.y, up_vec.y, direction.y, 0.0 },
            [4]f32 { right_vec.z, up_vec.z, direction.z, 0.0 },
            [4]f32 { -self.eye.dot(right_vec), -self.eye.dot(up_vec), -self.eye.dot(direction), 1.0 },
        };

        self.changed = true;
    }

    fn centralize(self: *Camera) void {
        self.eye = .{
            .x = 0,
            .y = 0,
            .z = -1,
        };
        self.view = .{
            [4]f32 { 1.0, 0.0, 0.0, 0.0 },
            [4]f32 { 0.0, -1.0, 0.0, 0.0 },
            [4]f32 { 0.0, 0.0, 1.0, 0.0 },
            [4]f32 { 0.0, 0.0, 0.0, 1.0 },
        };

        self.changed = true;
    }

    fn foward(self: *Camera, speed: f32) void {
        self.eye.x += self.view[0][2] * speed;
        self.eye.y += self.view[1][2] * speed;
        self.eye.z += self.view[2][2] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }

    fn backward(self: *Camera, speed: f32) void {
        self.eye.x -= self.view[0][2] * speed;
        self.eye.y -= self.view[1][2] * speed;
        self.eye.z -= self.view[2][2] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }

    fn right(self: *Camera, speed: f32) void {
        self.eye.x += self.view[0][0] * speed;
        self.eye.y += self.view[1][0] * speed;
        self.eye.z += self.view[2][0] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }

    fn left(self: *Camera, speed: f32) void {
        self.eye.x -= self.view[0][0] * speed;
        self.eye.y -= self.view[1][0] * speed;
        self.eye.z -= self.view[2][0] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }

    fn up(self: *Camera, speed: f32) void {
        self.eye.x -= self.view[0][1] * speed;
        self.eye.y -= self.view[1][1] * speed;
        self.eye.z -= self.view[2][1] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }

    fn down(self: *Camera, speed: f32) void {
        self.eye.x += self.view[0][1] * speed;
        self.eye.y += self.view[1][1] * speed;
        self.eye.z += self.view[2][1] * speed;

        self.view[3][0] = -self.eye.dot(.{
            .x = self.view[0][0],
            .y = self.view[1][0],
            .z = self.view[2][0]
        });

        self.view[3][1] = -self.eye.dot(.{
            .x = self.view[0][1],
            .y = self.view[1][1],
            .z = self.view[2][1]
        });

        self.view[3][2] = -self.eye.dot(.{
            .x = self.view[0][2],
            .y = self.view[1][2],
            .z = self.view[2][2]
        });

        self.changed = true;
    }
};
