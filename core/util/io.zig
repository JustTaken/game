const std = @import("std");
const _math = @import("math.zig");
const _collections = @import("collections.zig");

const ArrayList = _collections.ArrayList;
const Vec = _math.Vec;

pub const Io = struct {
    pub fn read_file(file_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();
        const end_pos = try file.getEndPos();

        return try file.readToEndAlloc(allocator, end_pos);
    }
};
