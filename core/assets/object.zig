const std = @import("std");

const _collections = @import("../collections/collections.zig");
const _math = @import("../math/math.zig");
const _font = @import("font.zig");
const _mesh = @import("mesh.zig");

const Vec = _math.Vec;
const Allocator = std.mem.Allocator;
const ArrayList = _collections.ArrayList;
const TrueTypeFont = _font.TrueTypeFont;
const Mesh = _mesh.Mesh;

pub const ObjectHandler = struct {
    font: TrueTypeFont,
    object_path: []const u8,
    allocator: Allocator,

    pub const Object = struct {
        index: ArrayList(u16),
        vertex: ArrayList([3]f32),
        texture: ArrayList([2]f32),

        pub fn deinit(self: *Object) void {
            self.index.deinit();
            self.vertex.deinit();
            self.texture.deinit();
        }
    };

    pub fn new(font_path: []const u8, object_path: []const u8, allocator: Allocator) !ObjectHandler {
        return .{
            .font = try TrueTypeFont.new(font_path, allocator),
            .object_path = object_path,
            .allocator = allocator,
        };
    }

    pub fn create(self: *ObjectHandler, typ: Mesh.Type) !Object {
        return switch (typ) {
            .cube => Mesh.new(.cube, self.allocator),
            .cone => Mesh.new(.cone, self.allocator),
            .plane => Mesh.new(.plane, self.allocator),
            else => try self.font.glyph_object(@enumFromInt(@intFromEnum(typ))),
        };
    }

    pub fn deinit(self: *ObjectHandler) void {
        self.font.deinit();
    }
};
