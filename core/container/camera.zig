const std           = @import("std");

const _math         = @import("../math/math.zig");
const _config       = @import("../util/configuration.zig");
const _event        = @import("../event/event.zig");
const _platform     = @import("../platform/platform.zig");

const EventSystem   = _event.EventSystem;
const Argument      = EventSystem.Argument;
const Listener      = EventSystem.Event.Listener;
const KeyMap        = _platform.KeyMap;

const Vec           = _math.Vec;
const Matrix        = _math.Matrix;

const configuration = _config.Configuration;

pub const Camera = struct {
    proj: [4][4]f32,
    view: [4][4]f32,
    eye:  Vec,

    changed:  bool = true,
    clicking: bool = false,
    aspect:   f32,

    const Direction = enum {
        X,
        Y,
        Z,
    };

    const y_rotation: [4][4]f32 = .{
        [4]f32 {   0.0, 0.0, 1.0, 0.0 },
        [4]f32 {   0.0, 1.0, 0.0, 0.0 },
        [4]f32 { - 1.0, 0.0, 0.0, 0.0 },
        [4]f32 {   0.0, 0.0, 0.0, 1.0 },
    };

    const fov:  f32 = std.math.pi * 0.25;
    const near: f32 = 0.10;
    const far:  f32 = 10.0;
    pub fn init(eye: Vec) Camera {
        const right_vec: Vec = .{.x = 1.0, .y =   0.0, .z = 0.0};
        const up_vec:    Vec = .{.x = 0.0, .y = - 1.0, .z = 0.0};
        const direction: Vec = .{.x = 0.0, .y =   0.0, .z = 1.0};
        const aspect:    f32 = @as( f32, @floatFromInt(configuration.default_width)) / @as(f32, @floatFromInt(configuration.default_height));

        return .{
            .eye = eye,
            .aspect = aspect,
            .proj = Matrix.perspective(fov, aspect, near, far),
            .view = .{
                [4]f32 {right_vec.x, up_vec.x, direction.x, 0.0},
                [4]f32 {right_vec.y, up_vec.y, direction.y, 0.0},
                [4]f32 {right_vec.z, up_vec.z, direction.z, 0.0},
                [4]f32 {-eye.dot(right_vec), -eye.dot(up_vec), -eye.dot(direction), 1.0},
            },
        };
    }

    pub fn listen_keyboard(self: *Camera, argument: Argument) bool {
        for (argument.u16) |k| {
            if (k == 0) continue;
            const e = @as(KeyMap, @enumFromInt(k));

            switch (e) {
                .S       => self.move(- 0.1, .Z),
                .W       => self.move(  0.1, .Z),
                .A       => self.move(- 0.1, .X),
                .D       => self.move(  0.1, .X),
                .Space   => self.move(- 0.1, .Y),
                .Control => self.move(  0.1, .Y),
                else     => { continue; },
            }

            self.changed = true;
        }

        return false;
    }

    pub fn listen_mouse(self: *Camera, argument: Argument) bool {
        if (!self.clicking) return false;

        const x = @as(f32, @floatFromInt(argument.i32[0])) * 0.000015;
        const y = @as(f32, @floatFromInt(argument.i32[1])) * 0.000015 * self.aspect;

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
        up_vec    = up_vec.sum(direction.scale(-y)).normalize();
        direction = up_vec.cross(right_vec);
        up_vec    = right_vec.cross(direction);

        self.view = .{
            [4]f32 { right_vec.x, up_vec.x, direction.x, 0.0 },
            [4]f32 { right_vec.y, up_vec.y, direction.y, 0.0 },
            [4]f32 { right_vec.z, up_vec.z, direction.z, 0.0 },
            [4]f32 { -self.eye.dot(right_vec), -self.eye.dot(up_vec), -self.eye.dot(direction), 1.0 },
        };

        self.changed = true;

        return false;
    }

    pub fn listen_click(self: *Camera, argument: Argument) bool {
        self.clicking = argument.u32[0] == 1;

        return false;
    }

    pub fn listen_resize(self: *Camera, argument: Argument) bool {
        self.aspect  = @as(f32, @floatFromInt(argument.u32[0])) / @as(f32, @floatFromInt(argument.u32[1]));
        self.proj    = Matrix.perspective(fov, self.aspect, near, far);
        self.changed = true;

        return false;
    }

    inline fn move(self: *Camera, speed: f32, direction: Direction) void {
        const index = @intFromEnum(direction);

        self.eye.x += self.view[0][index] * speed;
        self.eye.y += self.view[1][index] * speed;
        self.eye.z += self.view[2][index] * speed;

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
    }
};
