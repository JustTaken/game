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
        const size = try file.getEndPos();

        var vertex_array = try ArrayList(Vec).init(allocator, @intCast(size / 3));
        var index_array = try ArrayList(u16).init(allocator, @intCast(size));

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        var buffer: [100]u8 = undefined;

        while (true) {
            if (in_stream.readUntilDelimiterOrEof(&buffer, '\n') catch {
                break;
            }) |line| {
                if (line.len <= 3) continue;
                var split = std.mem.split(u8, line, &.{32});
                const first = split.first();

                if (std.mem.eql(u8, first, "v")) {
                    var numbers: [3]f32 = undefined;
                    var count: u32 = 0;

                    while (split.next()) |word| {
                        numbers[count] = try std.fmt.parseFloat(f32, word);
                        count += 1;
                    }

                    const vec = Vec{
                        .x = numbers[0],
                        .y = numbers[1],
                        .z = numbers[2],
                    };

                    try vertex_array.push(vec);
                } else if (std.mem.eql(u8, first, "f")) {
                    var count: u8 = 0;
                    var numbers: [12]u16 = undefined;

                    while (split.next()) |word| {
                        var ns = std.mem.split(u8, word, &.{47});

                        while (ns.next()) |n| {
                            numbers[count] = try std.fmt.parseInt(u16, n, 10) - 1;
                            count += 1;
                        }
                    }

                    try index_array.push(numbers[6]);
                    try index_array.push(numbers[3]);
                    try index_array.push(numbers[0]);

                    try index_array.push(numbers[0]);
                    try index_array.push(numbers[9]);
                    try index_array.push(numbers[6]);
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
