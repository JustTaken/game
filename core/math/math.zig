const std = @import("std");

pub const TO_DEGREE = 180.0 / std.math.pi;
pub const TO_RAD = std.math.pi / 180.0;

pub fn abs(number: anytype, T: type) !T {
    return switch (@typeInfo(@TypeOf(number))) {
        .Int, .ComptimeInt => if (number >= 0) @intCast(number) else @intCast(- number),
        else => return error.NotANumber,
    };
}

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
            [4]f32 { x, 0.0, 0.0, 0.0},
            [4]f32 {0.0, y, 0.0, 0.0},
            [4]f32 {0.0, 0.0, z, 0.0},
            [4]f32 {0.0, 0.0, 0.0, 1.0}
        };
    }

    pub fn x_rotate(theta: f32) [4][4]f32 {
        var cos = std.math.cos(theta);
        var sin = std.math.sin(theta);

        if (cos * cos < 0.01) {
            cos = 0;
        }
        if (sin * sin < 0.01) {
            sin = 0;
        }

        return .{
            [4]f32 { 1.0, 0.0, 0.0, 0.0 },
            [4]f32 { 0.0, cos, sin, 0.0 },
            [4]f32 { 0.0, - sin, cos, 0.0 },
            [4]f32 { 0.0, 0.0, 0.0, 1.0 },
        };
    }

    pub inline fn y_rotate(theta: f32) [4][4]f32 {
        var cos = std.math.cos(theta);
        var sin = std.math.sin(theta);

        if (cos * cos < 0.001) {
            cos = 0;
        }
        if (sin * sin < 0.001) {
            sin = 0;
        }

        return .{
            [4]f32 { cos, 0.0, - sin, 0.0 },
            [4]f32 { 0.0, 1.0, 0.0, 0.0 },
            [4]f32 { sin, 0.0, cos, 0.0 },
            [4]f32 { 0.0, 0.0, 0.0, 1.0 },
        };
    }

    pub inline fn ortogonal(vec: Vec) [4][4]f32 {
        return .{
            [4]f32 {vec.x * vec.x, vec.x * vec.y - vec.z, vec.x * vec.z + vec.y, 0.0},
            [4]f32 {vec.y * vec.x + vec.z, vec.y * vec.y, vec.y * vec.z - vec.x, 0.0},
            [4]f32 {vec.z * vec.x - vec.y, vec.z * vec.y + vec.x, vec.z * vec.z, 0.0},
            [4]f32 {0.0, 0.0, 0.0, 1.0},
        };
    }

    pub inline fn rotate(theta: f32, vec: Vec) [4][4]f32 {
        const norm = vec.normalize();
        const cos = std.math.cos(theta);
        const sin = std.math.sin(theta);

        return .{
            [4]f32 {cos + norm.x * norm.x * (1 - cos), norm.y * norm.x * (1 - cos) + norm.z * sin, norm.z * norm.x * (1 - cos) + norm.y * sin, 0.0},
            [4]f32 {norm.x * norm.y * (1 - cos) - norm.z * sin, cos + norm.y * norm.y * (1 - cos), norm.z * norm.y * (1 - cos) - norm.x * sin, 0.0},
            [4]f32 {norm.x * norm.z * (1 - cos) + norm.y * sin, norm.y * norm.z * (1 - cos) + norm.x * sin, cos + norm.z * norm.z * (1 - cos), 0.0},
            [4]f32 {0.0, 0.0, 0.0, 1.0},
        };
    }

    pub inline fn translate(x: f32, y: f32, z: f32) [4][4]f32 {
        return .{
            [4]f32 {1.0, 0.0, 0.0, 0.0},
            [4]f32 {0.0, 1.0, 0.0, 0.0},
            [4]f32 {0.0, 0.0, 1.0, 0.0},
            [4]f32 { x, y, z, 1.0},
        };
    }

    pub inline fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) [4][4]f32 {
        const top = 1.0 / std.math.tan(fovy * 0.5);
        const r = far / (far - near);

        return [4][4]f32 {
            [4]f32 {top / aspect, 0.0, 0.0, 0.0},
            [4]f32 { 0.0, top, 0.0, 0.0},
            [4]f32 { 0.0, 0.0, r, 1.0},
            [4]f32 { 0.0, 0.0, -r * near, 0.0},
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
