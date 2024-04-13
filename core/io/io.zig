const std = @import("std");

const _math = @import("../math/math.zig");
const _collections = @import("../collections/collections.zig");
const _allocator = @import("../util/allocator.zig");

const ArrayList = _collections.ArrayList;
const Vec = _math.Vec;
const Allocator = _allocator.Allocator;

pub const Io = struct {
    pub const Reader = struct {
        file: std.fs.File,

        pub fn new(file_name: []const u8) !Reader {
            return .{
                .file = try std.fs.cwd().openFile(file_name, .{}),
            };
        }

        pub fn read(self: Reader, comptime size: u32) ![size] u8 {
            var buffer: [size] u8 = undefined;
            if (try self.file.read(&buffer) < size) return error.DidNotReadAllBytes;

            return buffer;
        }

        pub fn read_alloc(self: Reader, size: u32, allocator: *Allocator) ![]u8 {
            const array: []u8 = try allocator.alloc(u8, size);
            if (try self.file.read(array) < size) return error.IncompleteContent;

            return array;
        }

        pub fn pos(self: Reader) u64 {
            return self.file.getPos() catch 0;
        }

        pub fn seek(self: Reader, offset: usize) void {
            self.file.seekTo(offset) catch {};
        }

        pub fn shutdown(self: Reader) void {
            self.file.close();
        }
    };

    pub fn read_file(file_name: []const u8, allocator: *Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();

        const end_pos = try file.getEndPos();
        const content = try allocator.alloc(u8, end_pos);
        if (try file.read(content) < end_pos) return error.InclompleteContent;

        return content;
    }
};
