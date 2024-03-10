const std = @import("std");
const _math = @import("math.zig");
const _collections = @import("collections.zig");

const ArrayList = _collections.ArrayList;
const Vec = _math.Vec;

pub const Io = struct {
    pub const Reader = struct {
        file: std.fs.File,
        failed: bool = false,

        pub fn read(self: *Reader, comptime size: u32) [size] u8 {
            var buffer: [size] u8 = undefined;
            _ = self.file.read(&buffer) catch blk: {
                self.failed = true;
                break :blk 0;
            };

            return buffer;
        }

        pub fn pos(self: Reader) u64 {
            return self.file.getPos() catch 0;
        }

        pub fn seek(self: Reader, offset: usize) void {
            self.file.seekTo(offset) catch {
                std.debug.print("failed to seek\n", .{});
            };
        }

        pub fn new(file_name: []const u8) !Reader {
            return .{
                .file = try std.fs.cwd().openFile(file_name, .{}),
            };
        }

        pub fn shutdown(self: Reader) void {
            self.file.close();
        }
    };
    pub fn read_file(file_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();
        const end_pos = try file.getEndPos();

        return try file.readToEndAlloc(allocator, end_pos);
    }
};
