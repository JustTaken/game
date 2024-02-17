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

pub const Obj = struct {
    vertex: ArrayList(Vec),
    index: ArrayList(u16),

    pub fn new(file_name: []const u8, allocator: std.mem.Allocator) !Obj {
        var file = try std.fs.cwd().openFile(file_name, .{});
        defer file.close();

        var vertex_array = ArrayList(Vec).init(allocator);
        var index_array = ArrayList(u16).init(allocator);

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        var buffer: [100]u8 = undefined;

        while (true) {
            if (in_stream.readUntilDelimiterOrEof(&buffer, '\n') catch {
                break;
            }) |line| {
                if (line.len <= 3) continue;
                if (std.mem.eql(u8, line[0..2], &[_]u8 {118, 32})) {
                    var base: u32 = 2;
                    var index: u32 = 2;
                    var count: u8 = 0;
                    var numbers: [3]f32 = undefined;

                    for (line[2..]) |c| {
                        if (c == 32 or index == line.len - 1) {
                            numbers[count] = try std.fmt.parseFloat(f32, line[base..index]);

                            base = index + 1;
                            count += 1;
                        }

                        index += 1;
                    }

                    const vec = Vec {
                        .x = numbers[0],
                        .y = numbers[1],
                        .z = numbers[2],
                    };

                    try vertex_array.push(vec);
                } else if (std.mem.eql(u8, line[0..2], &[_]u8 {102, 32})) {
                    var base: usize = 2;
                    var count: u8 = 0;
                    var numbers: [12]u16 = undefined;
                    for (0..line[2..].len) |i| {
                        const index = i + 2;

                        if (line[index] == 32 or line[index] == 47) {
                            numbers[count] = try std.fmt.parseInt(u16, line[base..index], 10) - 1;

                            base = index + 1;
                            count += 1;
                        } else if (index == line.len - 1) {
                            numbers[count] = try std.fmt.parseInt(u16, line[base..index + 1], 10) - 1;
                        }
                    }

                    try index_array.push(numbers[0]);
                    try index_array.push(numbers[3]);
                    try index_array.push(numbers[6]);

                    try index_array.push(numbers[6]);
                    try index_array.push(numbers[9]);
                    try index_array.push(numbers[0]);
                }
            } else {
                break;
            }
        }

        return .{
            .vertex = vertex_array,
            .index = index_array,
        };
    }
};
