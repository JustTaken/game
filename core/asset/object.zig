const std = @import("std");

const _collections = @import("../util/collections.zig");
const _math = @import("../util/math.zig");

const ArrayList = _collections.ArrayList;
const Vec = _math.Vec;

pub const Object = struct {
    vertex: ArrayList(Vec),
    index: ArrayList(u16),

    pub const Type = enum {
        Cube,
        Cone,
        Plane,

        None,

        fn path(self: Type) []const u8 {
            return switch (self) {
                .Cube => "assets/cube.obj",
                .Cone => "assets/cone.obj",
                .Plane => "assets/plane.obj",
                .None => "",
            };
        }
    };

    pub fn new(typ: Type, allocator: std.mem.Allocator) !Object {
        var file = try std.fs.cwd().openFile(typ.path(), .{});
        defer file.close();
        const size = try file.getEndPos();

        var vertex_array = try ArrayList(Vec).init(allocator, @intCast(size / 3));
        var index_array = try ArrayList(u16).init(allocator, @intCast(size));

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();
        var buffer: [1024]u8 = undefined;

        while (true) {
            if (in_stream.readUntilDelimiterOrEof(&buffer, '\n') catch {
                break;
            }) |line| {
                if (line.len <= 3) continue;
                var split = std.mem.splitSequence(u8, line, &.{32});
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
                    var count: u32 = 0;
                    var numbers = try ArrayList(u16).init(allocator, 12);

                    while (split.next()) |word| {
                        var ns = std.mem.splitSequence(u8, word, &.{47});

                        while (ns.next()) |n| {
                            try numbers.push(try std.fmt.parseInt(u16, n, 10) - 1);
                        }

                        count += 1;
                    }

                    if (count > 4) { // Any figure with more than 4 vertices may be a circle - i hope -, so calculate the center vertex and do your stuff
                        var distance: f32 = 0;
                        const first_vec = vertex_array.items[numbers.items[0]];
                        var last_vec: Vec = undefined;
                        for (1..count / 2 + 1) |i| {
                            const v = vertex_array.items[numbers.items[i * 3]];
                            const mult = first_vec.dot(v);

                            if (mult >= distance) {
                                distance = mult;
                                last_vec = v;
                            }
                        }

                        const center = first_vec.sum(last_vec.sub(vertex_array.items[numbers.items[0]]).scale(0.5));
                        try vertex_array.push(center);

                        for (0..count - 1) |i| {
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(@intCast(vertex_array.items.len - 1));
                            try index_array.push(numbers.items[i * 3]);
                        }
                    } else if (count % 3 == 0) {
                        for (0..count / 3) |i| {
                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);
                        }
                    } else if (count % 4 == 0) {
                        for (0..count / 4) |i| {
                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);

                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);
                            try index_array.push(numbers.items[(i + 3) * 3]);
                        }
                    }
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
