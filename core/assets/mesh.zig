const std          = @import("std");

const _collections = @import("../collections/collections.zig");
const _math        = @import("../math/math.zig");
const _object      = @import("object.zig");

const Allocator    = std.mem.Allocator;
const ArrayList    = _collections.ArrayList;
const Object       = _object.ObjectHandler.Object;

pub const Mesh = struct {
    pub const Type = enum {
        cube,
        cone,
        plane,
    };

    pub fn new(typ: Type, allocator: Allocator) !Object {
        const path           = try std.mem.concat(allocator, u8, &.{"assets/objects/", @tagName(typ), ".obj"});
        defer allocator.free(path);

        var file             = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        const size: u32      = @intCast(try file.getEndPos());

        var vertex_array     = try ArrayList([3]f32).init(allocator, size / 3);
        var texture_data    = try ArrayList([2]f32).init(allocator, size / 3);
        var index_array      = try ArrayList(u16).init(allocator, size);

        var texture_array = try allocator.alloc([2]f32, size / 3);
        defer allocator.free(texture_array);

        var buf_reader       = std.io.bufferedReader(file.reader());
        var in_stream        = buf_reader.reader();

        while (true) {
            if (in_stream.readUntilDelimiterOrEof(&buffer, '\n') catch { break; }) |line| {
                if (line.len <= 3) continue;

                var split = std.mem.splitSequence(u8, line, &.{32});
                const first = split.first();

                if (std.mem.eql(u8, first, "v")) {
                    var numbers: [3]f32 = undefined;
                    var count:      u32 = 0;

                    while (split.next()) |word| {
                        numbers[count] = try std.fmt.parseFloat(f32, word);
                        count         += 1;
                    }

                    try vertex_array.push(.{ numbers[0], numbers[1], numbers[2] });
                } else if (std.mem.eql(u8, first, "vt")) {
                    var numbers: [2]f32 = undefined;
                    var count:      u32 = 0;

                    while (split.next()) |word| {
                        numbers[count] = try std.fmt.parseFloat(f32, word);
                        count         += 1;
                    }

                    try texture_data.push(.{numbers[0], numbers[1]});
                } else if (std.mem.eql(u8, first, "f")) {
                    var count: u32 = 0;
                    var numbers    = try ArrayList(u16).init(allocator, 12);

                    while (split.next()) |word| {
                        var number_split = std.mem.splitSequence(u8, word, &.{47});

                        while (number_split.next()) |n| {
                            try numbers.push(try std.fmt.parseInt(u16, n, 10) - 1);
                        }

                        count += 1;
                    }

                    if (count > 4) {
                        for (1..count - 1) |i| {
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(numbers.items[0]);
                            try index_array.push(numbers.items[i * 3]);

                            texture_array[numbers.items[(i + 1) * 3 + 1]] = texture_data.items[numbers.items[(i + 1) * 3 + 1]];
                            texture_array[numbers.items[0 + 1]] = texture_data.items[numbers.items[0 + 1]];
                            texture_array[numbers.items[i * 3 + 1]] = texture_data.items[numbers.items[i * 3 + 1]];
                        }
                    } else if (count % 3 == 0) {
                        for (0..count / 3) |i| {
                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);

                            texture_array[numbers.items[(i + 0) * 3]] = texture_data.items[numbers.items[(i + 0) * 3 + 1]];
                            texture_array[numbers.items[(i + 1) * 3]] = texture_data.items[numbers.items[(i + 1) * 3 + 1]];
                            texture_array[numbers.items[(i + 2) * 3]] = texture_data.items[numbers.items[(i + 2) * 3 + 1]];
                        }
                    } else if (count % 4 == 0) {
                        for (0..count / 4) |i| {
                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 1) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);

                            try index_array.push(numbers.items[(i + 0) * 3]);
                            try index_array.push(numbers.items[(i + 2) * 3]);
                            try index_array.push(numbers.items[(i + 3) * 3]);

                            texture_array[numbers.items[(i + 0) * 3]] = texture_data.items[numbers.items[(i + 0) * 3 + 1]];
                            texture_array[numbers.items[(i + 1) * 3]] = texture_data.items[numbers.items[(i + 1) * 3 + 1]];
                            texture_array[numbers.items[(i + 2) * 3]] = texture_data.items[numbers.items[(i + 2) * 3 + 1]];

                            texture_array[numbers.items[(i + 0) * 3]] = texture_data.items[numbers.items[(i + 0) * 3 + 1]];
                            texture_array[numbers.items[(i + 2) * 3]] = texture_data.items[numbers.items[(i + 2) * 3 + 1]];
                            texture_array[numbers.items[(i + 3) * 3]] = texture_data.items[numbers.items[(i + 3) * 3 + 1]];
                        }
                    }

                    numbers.deinit();
                }
            } else {
                break;
            }
        }

        try texture_data.clear();
        try texture_data.push_slice(texture_array);

        return .{
            .index  = index_array,
            .vertex = vertex_array,
            .texture = texture_data,
        };
    }
};

