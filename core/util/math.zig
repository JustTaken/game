const std = @import("std");

pub const Vec = struct {
    x: f32,
    y: f32,
    z: f32,

    pub inline fn sum(self: Vec, other: Vec) Vec {
        return .{
            .x = other.x + self.x,
            .y = other.y + self.y,
            .z = other.z + self.z,
        };
    }

    pub inline fn sub(self: Vec, other: Vec) Vec {
        return .{
            .x = other.x - self.x,
            .y = other.y - self.y,
            .z = other.z - self.z,
        };
    }

    pub inline fn dot(self: Vec, other: Vec) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub inline fn angle(self: Vec, other: Vec) f32 {
        const value: f32 = self.normalize().dot(other.normalize());
        return std.math.acos(value);
    }

    pub inline fn cross(self: Vec, other: Vec) Vec {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub inline fn len(self: Vec) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn normalize(self: Vec) Vec {
        const length: f32 = self.len();
        return .{
            .x = self.x / length,
            .y = self.y / length,
            .z = self.z / length,
        };
    }

    pub inline fn scale(vec: Vec, alpha: f32) Vec {
        return .{
            .x = vec.x * alpha,
            .y = vec.y * alpha,
            .z = vec.z * alpha,
        };
    }

    pub inline fn mult(vec: Vec, matrix: [4][4]f32) Vec {
        return .{
            .x = matrix[0][0] * vec.x + matrix[1][0] * vec.y + matrix[2][0] * vec.z,
            .y = matrix[0][1] * vec.x + matrix[1][1] * vec.y + matrix[2][1] * vec.z,
            .z = matrix[0][2] * vec.x + matrix[1][2] * vec.y + matrix[2][2] * vec.z,
        };
    }

    pub inline fn hash(self: Vec) u32 {
        return @as(u32, @intFromFloat(self.x * self.x + self.y * self.y + self.z * self.z));
    }

    pub inline fn equal(self: Vec, other: Vec) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z;
    }
};

pub const Matrix = struct {
    handle: [4][4]f32,

    pub inline fn scale(x: f32, y: f32, z: f32) [4][4]f32 {
        return .{
            [4]f32 {x, 0.0, 0.0, 0.0},
            [4]f32 {0.0, y, 0.0, 0.0},
            [4]f32 {0.0, 0.0, z, 0.0},
            [4]f32 {0.0, 0.0, 0.0, 1.0}
        };
    }

    pub inline fn rotate(theta: f32, vec: Vec) [4][4]f32 {
        const norm = vec.normalize();
        const cos = std.math.cos(theta);
        const sin = std.math.sin(theta);

        return .{
            [4]f32 {cos + norm.x * norm.x * (1 - cos), norm.y * norm.x * (1 - cos) + norm.z * sin, norm.z * norm.x * (1 - cos) - norm.y * sin,  0.0},
            [4]f32 {norm.x * norm.y * (1 - cos) - vec.z * sin, cos + norm.y * norm.y * (1 - cos),  norm.z * norm.y * (1 - cos) + norm.x * sin,  0.0},
            [4]f32 {norm.x * norm.z * (1 - cos) + norm.y * sin, norm.y * norm.z * (1 - cos) - norm.x * sin, cos + norm.z * norm.z * (1 - cos),  0.0},
            [4]f32 {0.0, 0.0, 0.0, 1.0},
        };
    }

    pub inline fn translate(x: f32, y: f32, z: f32) [4][4]f32 {
        return .{
            [4]f32 {1.0, 0.0, 0.0, 0.0},
            [4]f32 {0.0, 1.0, 0.0, 0.0},
            [4]f32 {0.0, 0.0, 1.0, 0.0},
            [4]f32 {x, y, z, 1.0},
        };
    }

    pub inline fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) [4][4]f32 {
        const top: f32 = std.math.tan(fovy * 0.5) * near;
        const bottom = -top;
        const right = top * aspect;
        const left = -right;

        return [4][4]f32 {
            [4]f32 {2 * near / (right - left), 0.0, 0.0, 0.0},
            [4]f32 {0.0, -2 * near / (top - bottom), 0.0, 0.0},
            [4]f32 {(right + left) / (right - left), (top + bottom) / (top - bottom), -(far + near) / (far - near), -1.0},
            [4]f32 {0.0, 0.0, -2 * far * near / (far - near), 0.0},
        };
    }

    pub inline fn mult(m1: [4][4]f32, m2: [4][4]f32) [4][4]f32 {
        return .{
            [4]f32 {m1[0][0] * m2[0][0] + m1[0][1] * m2[1][0] + m1[0][2] * m2[2][0] + m1[0][3] * m2[3][0], m1[0][0] * m2[0][1] + m1[0][1] * m2[1][1] + m1[0][2] * m2[2][1] + m1[0][3] * m2[3][1], m1[0][0] * m2[0][2] + m1[0][1] * m2[1][2] + m1[0][2] * m2[2][2] + m1[0][3] * m2[3][2], m1[0][0] * m2[0][3] + m1[0][1] * m2[1][3] + m1[0][2] * m2[2][3] + m1[0][3] * m2[3][3]},
            [4]f32 {m1[1][0] * m2[0][0] + m1[1][1] * m2[1][0] + m1[1][2] * m2[2][0] + m1[1][3] * m2[3][0], m1[1][0] * m2[0][1] + m1[1][1] * m2[1][1] + m1[1][2] * m2[2][1] + m1[1][3] * m2[3][1], m1[1][0] * m2[0][2] + m1[1][1] * m2[1][2] + m1[1][2] * m2[2][2] + m1[1][3] * m2[3][2], m1[1][0] * m2[0][3] + m1[1][1] * m2[1][3] + m1[1][2] * m2[2][3] + m1[1][3] * m2[3][3]},
            [4]f32 {m1[2][0] * m2[0][0] + m1[2][1] * m2[1][0] + m1[2][2] * m2[2][0] + m1[2][3] * m2[3][0], m1[2][0] * m2[0][1] + m1[2][1] * m2[1][1] + m1[2][2] * m2[2][1] + m1[2][3] * m2[3][1], m1[2][0] * m2[0][2] + m1[2][1] * m2[1][2] + m1[2][2] * m2[2][2] + m1[2][3] * m2[3][2], m1[2][0] * m2[0][3] + m1[2][1] * m2[1][3] + m1[2][2] * m2[2][3] + m1[2][3] * m2[3][3]},
            [4]f32 {m1[3][0] * m2[0][0] + m1[3][1] * m2[1][0] + m1[3][2] * m2[2][0] + m1[3][3] * m2[3][0], m1[3][0] * m2[0][1] + m1[3][1] * m2[1][1] + m1[3][2] * m2[2][1] + m1[3][3] * m2[3][1], m1[3][0] * m2[0][2] + m1[3][1] * m2[1][2] + m1[3][2] * m2[2][2] + m1[3][3] * m2[3][2], m1[3][0] * m2[0][3] + m1[3][1] * m2[1][3] + m1[3][2] * m2[2][3] + m1[3][3] * m2[3][3]},
        };
    }
};

pub const Camera = struct {
    up: Vec,
    eye: Vec,
    center: Vec,

    pub inline fn init(eye: Vec) Camera {
        return .{
            .eye = eye,
            .center = Vec.init(0.0, 0.0, 0.0),
            .up = Vec.init(0.0, -1.0, 0.0),
        };
    }

    pub inline fn view_matrix(self: *Camera) [4][4]f32 {
        const direction = Vec.sub(self.eye, self.center).normalize();
        const right = Vec.cross(direction, self.up.normalize()).normalize();

        self.up = Vec.cross(right, direction);

        return [4][4]f32 {
            [4]f32 {right.x, self.up.x, -direction.x, 0.0},
            [4]f32 {right.y, self.up.y, -direction.y, 0.0},
            [4]f32 {right.z, self.up.z, -direction.z, 0.0},
            [4]f32 {-Vec.dot(right, self.eye), -Vec.dot(self.up, self.eye), Vec.dot(direction, self.eye), 1.0},
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
    }

    fn move_foward(self: *Camera, speed: f32) void {
        const delta = Vec.sub(self.eye, self.center).normalize().scale(speed * 10.0);
        self.eye = Vec.sum(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
    }

    fn move_backward(self: *Camera, speed: f32) void {
        const delta = Vec.sub(self.eye, self.center).normalize().scale(speed * 10.0);
        self.eye = Vec.sub(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
    }

    fn move_right(self: *Camera, speed: f32) void {
        const delta = Vec.cross(Vec.sub(self.eye, self.center), self.up).normalize().scale(speed * 10.0);
        self.eye = Vec.sum(delta, self.eye);
        self.center = Vec.sum(delta, self.center);
    }

    fn move_left(self: *Camera, speed: f32) void {
        const delta = Vec.cross(Vec.sub(self.eye, self.center), self.up).normalize().scale(speed * 10.0);
        self.eye = Vec.sub(delta, self.eye);
        self.center = Vec.sub(delta, self.center);
    }

    fn move_up(self: *Camera, speed: f32) void {
        self.eye = Vec.sub(self.up.normalize().scale(speed), self.eye);
        self.center = Vec.sub(self.up.normalize().scale(speed), self.center);
    }

    fn move_down(self: *Camera, speed: f32) void {
        self.eye = Vec.sum(self.up.normalize().scale(speed), self.eye);
        self.center = Vec.sum(self.up.normalize().scale(speed), self.center);
    }
};
