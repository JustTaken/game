const Log = @import("log.zig");
const std = @import("std");

pub const Configuration = struct {
    pub const application_name: []const u8 = "Engine";
    pub const default_width: u32 = 800;
    pub const default_height: u32 = 600;
    pub const version: u32 = 1;
    pub const logger = Log.Log {
        .level = .Debug,
    };
};

pub const State = enum {
    Stoped,
    Running,
    Closing,
    Suspended,
};

pub const Io = struct {
    pub fn read_file(file_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();
        const end_pos = try file.getEndPos();

        return try file.readToEndAlloc(allocator, end_pos);
    }
};
