const std = @import("std");

const _io = @import("../io/io.zig");
const _collections = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _math = @import("../math/math.zig");
const _allocator = @import("../util/allocator.zig");

const ArrayList = _collections.ArrayList;
const Allocator = _allocator.Allocator;
const Reader = _io.Io.Reader;

const pow = _math.pow;
const fac = _math.fac;
const or_zero = _math.or_zero;

const interpolations: u32 = 4;

pub const Type = enum(u8) {
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z,
    // space, comma, coulon, semi_coulon,

    pub fn code(self: Type) u8 {
        return @intFromEnum(self) + 97;
        // return switch (self) {
        //     .space => ' ',
        //     .comma => ',',
        //     .coulon => '.',
        //     .semi_coulon => ';',
        //     else => @intFromEnum(self) + 97,
        // };
    }
};

pub const TrueTypeFont = struct {
    texture: []u8,
    glyphs: [@typeInfo(Type).Enum.fields.len]Glyph,

    allocator: *Allocator,

    width: u32,
    height: u32,

    const Glyph = struct {
        texture: []u8,
        texture_coords: [4][2]f32,
        vertex: [4][3]f32,
        index: [6]u16,

        width: u32,
        height: u32,

        const Point = struct {
            x: i16 = 0,
            y: i16 = 0,
            on_curve: bool,
        };

        fn calculate_line(from: [2]u32, to: [2]u32, width: u32, height: u32, texture: []u8) void {
            _ = height;
            const first_x = @min(from[0], to[0]);
            const last_x = from[0] + to[0] - first_x;

            const first_y = @min(from[1], to[1]);
            const last_y = from[1] + to[1] - first_y;

            const iter_max = @max(last_x - first_x, last_y - first_y);
            if (iter_max == 0) return;

            const x_m = @as(f32, @floatFromInt(@as(i32, @intCast(to[0])) - @as(i32, @intCast(from[0])))) / @as(f32, @floatFromInt(iter_max));
            const y_m = @as(f32, @floatFromInt(@as(i32, @intCast(to[1])) - @as(i32, @intCast(from[1])))) / @as(f32, @floatFromInt(iter_max));

            for (0..iter_max) |j| {
                const x: u32 = @as(u32, @intFromFloat(@as(f32, @floatFromInt(from[0])) + @round(@as(f32, @floatFromInt(j)) * x_m)));
                const y: u32 = @as(u32, @intFromFloat(@as(f32, @floatFromInt(from[1])) + @round(@as(f32, @floatFromInt(j)) * y_m)));

                texture[x + y * width] = 255;
            }
        }

        // fn compound(glyph_points: [5]i16, reader: Reader, factor: f32, allocator: *Allocator) !Glyph {
        //     const number_of_contours: u32 = @intCast(glyph_points[0]);
        //     _ = allocator;

        //     const arg_1_and_2_are_words: u16 = 0x0001;
        //     const args_are_xy_values: u16 = 0x0002;
        //     const round_xy_to_grid: u16 = 0x0004;
        //     const we_have_a_scale: u16 = 0x0008;
        //     const obsolete: u16 = 0x0010;
        //     const more_components: u16 = 0x0020;
        //     const we_have_an_x_and_y_scale = 0x0040;
        //     const we_have_a_two_by_two = 0x0080;
        //     const we_have_instructions = 0x0100;
        //     const use_my_metrics = 0x0200;
        //     const overlap_component = 0x0400;

        //     var flags: u16 = @bitCast(try reader.read(2));

        //     while (flags & more_components != 0) {
        //         var arg1: i16 = undefined;
        //         var arg2: i16 = undefined;

        //         flags = @bitCast(try reader.read(2));
        //         const index: u16 = @bitCast(try reader.read(2));
        //         var matrix: [6]i16 = .{ 1, 0, 0, 1, 0, 0 };
        //         var points: [2]i16 = .{ 0, 0 };

        //         if (flags & arg_1_and_2_are_words) {
        //             arg1 = @bitCast(try reader.read(2));
        //             arg2 = @bitCast(try reader.read(2));
        //         } else {
        //             arg1 = @as(u8, @bitCast(try reader.read(1)));
        //             arg2 = @as(u8, @bitCast(try reader.read(1)));
        //         }

        //         if (flags & args_are_xy_values != 0) {
        //             matrix[4] = arg1;
        //             matrix[5] = arg2;
        //         } else {
        //             points[0] = arg1;
        //             points[1] = arg2;
        //         }

        //         if (flags & we_have_a_scale) {
        //             matrix[0] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //             matrix[3] = matrix[0];
        //         } else if (flags & we_have_an_x_and_y_scale) {
        //             matrix[0] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //             matrix[3] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //         } else if (flags & we_have_a_two_by_two) {
        //             matrix[0] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //             matrix[1] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //             matrix[2] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //             matrix[3] = @as(u16, @bitCast(try reader.read(2))) / (@as(u16, 1) << 14);
        //         }

        //         if (flags & we_have_instructions) {
        //             const pos = reader.pos();
        //             const offset: u16 = @bitCast(try reader.read(2));
        //             reader.seek(pos + offset);
        //         }
        //     }
        // }

        fn simple(glyph_points: [5]i16, reader: Reader, factor: f32, allocator: *Allocator) !Glyph {
            const number_of_contours: u32 = @intCast(glyph_points[0]);
            if (number_of_contours == 0) return error.NoCountour;

            var contour_ends = try allocator.alloc(u16, number_of_contours);
            defer allocator.free(contour_ends);

            var points_len: u32 = 0;
            for (0..number_of_contours) |i| {
                const contour_end: u16 = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

                if (contour_end + 1 > points_len) {
                    points_len = contour_end + 1;
                }

                contour_ends[i] = contour_end;
            }

            const off = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const pos = reader.pos();

            reader.seek(off + pos);

            const on_curve: u8 = 0x01;
            const x_is_short: u8 = 0x02;
            const y_is_short: u8 = 0x04;
            const repeat: u8 = 0x08;
            const x_is_same: u8 = 0x10;
            const y_is_same: u8 = 0x20;

            var flags = try allocator.alloc(u8, points_len);
            defer allocator.free(flags);

            var i: u32 = 0;
            while (i < points_len) : (i += 1) {
                const flag: u8 = @bitCast(try reader.read(1));

                if (flag & repeat != 0) {
                    const repeat_count: u8 = @bitCast(try reader.read(1));
                    @memset(flags[i..i + repeat_count + 1], flag);

                    i += repeat_count;
                } else {
                    flags[i] = flag;
                }
            }

            var points = try allocator.alloc(Point, points_len);
            defer allocator.free(points);

            var x_value: i16 = 0;
            for (0..points_len) |k| {
                if (flags[k] & x_is_short != 0) {
                    const value: u8 = @bitCast(try reader.read(1));

                    if (flags[k] & x_is_same != 0) x_value += value
                    else x_value -= value;
                } else {
                    if (flags[k] & x_is_same == 0) x_value += @byteSwap(@as(i16, @bitCast(try reader.read(2))));
                }

                points[k].x = @as(i16, @intFromFloat(@floor(@as(f32, @floatFromInt(x_value)) * factor)));
                points[k].on_curve = flags[k] & on_curve != 0;
            }

            var y_value: i16 = 0;
            for (0..points_len) |k| {
                if (flags[k] & y_is_short != 0) {
                    const value: u8 = @bitCast(try reader.read(1));

                    if (flags[k] & y_is_same != 0) y_value += value
                    else y_value -= value;
                } else {
                    if (flags[k] & y_is_same == 0) y_value += @byteSwap(@as(i16, @bitCast(try reader.read(2))));
                }

                points[k].y = @as(i16, @intFromFloat(@floor(@as(f32, @floatFromInt(y_value)) * factor)));
            }

            const width: u32 = or_zero(glyph_points[3] - glyph_points[1]) + 1;
            const height: u32 = or_zero(glyph_points[4] - glyph_points[2]) + 1;
            const texture = try create_texture(width, height, contour_ends, points, glyph_points, allocator);

            return .{
                .width = width,
                .height = height,
                .texture = texture,

                .texture_coords = .{ .{0, 1}, .{1, 1}, .{0, 0}, .{1, 0} },
                .index = .{0, 1, 2, 2, 1, 3},
                .vertex = .{
                    .{- factor, factor, 0},
                    .{factor, factor, 0},
                    .{- factor, - factor, 0},
                    .{factor, - factor, 0},
                },
            };
        }

        fn create_texture(width: u32, height: u32, contour_ends: []u16, points: []Point, glyph_points: [5]i16, allocator: *Allocator) ![]u8 {
            const texture = try allocator.alloc(u8, width * height);
            @memset(texture, 0);

            var out_points: [20][2]u32 = undefined;
            var contour_start: u8 = 0;
            var contour_count: u8 = 0;

            for (contour_ends) |contour_end| {
                for (contour_start..contour_end + 1) |point| {
                    var index_of_next = if (point == contour_end) contour_start else point + 1;
                    if (!points[point].on_curve) continue;

                    var out_points_count: u32 = 0;

                    while (!points[index_of_next].on_curve) {
                        out_points[out_points_count] = .{
                            or_zero(points[index_of_next].x - glyph_points[1]),
                            or_zero(points[index_of_next].y - glyph_points[2])
                        };

                        out_points_count += 1;

                        if (index_of_next >= contour_end) index_of_next = contour_start
                        else index_of_next += 1;
                    }

                    const x0: u32 = or_zero(points[point].x - glyph_points[1]);
                    const y0: u32 = or_zero(points[point].y - glyph_points[2]);

                    const x1: u32 = or_zero(points[index_of_next].x - glyph_points[1]);
                    const y1: u32 = or_zero(points[index_of_next].y - glyph_points[2]);

                    var previous_x = x0;
                    var previous_y = y0;

                    if (out_points_count == 0) {
                        calculate_line(.{ x0, y0 }, .{ x1, y1 }, width, height, texture);
                    } else {
                        var coeficients: [22][2]u32 = undefined;
                        coeficients[0] = .{ x0, y0 };

                        @memcpy(coeficients[1..out_points_count + 1], out_points[0..out_points_count]);
                        coeficients[out_points_count + 1] = .{ x1, y1};

                        const len = out_points_count  + 2 - 1;

                        for (1..interpolations + 1) |iter| {
                            const t = @as(f32, @floatFromInt(iter)) / @as(f32, @floatFromInt(interpolations));

                            var ptx: u32 = 0;
                            var pty: u32 = 0;

                            for (0..len + 1) |index| {
                                const bin = @as(f32, @floatFromInt(fac(len))) / @as(f32, @floatFromInt(fac(index) * fac(len - index)));
                                const tm = pow(1 - t, @as(f32, @floatFromInt(len - index)));
                                const tt = pow(t, @as(f32, @floatFromInt(index)));

                                ptx += @as(u32, @intFromFloat(@round(bin * tm * tt * @as(f32, @floatFromInt(coeficients[index][0])))));
                                pty += @as(u32, @intFromFloat(@round(bin * tm * tt * @as(f32, @floatFromInt(coeficients[index][1])))));
                            }

                            if (pty >= height) pty = height - 1;
                            if (ptx >= width) ptx = width - 1;

                            calculate_line(.{previous_x, previous_y}, .{ptx, pty}, width, height, texture);

                            previous_x = ptx;
                            previous_y = pty;
                        }
                    }
                }

                contour_start = @intCast(contour_end + 1);
                contour_count += 1;
            }

            var point: [2]u16 = undefined;
            out: for (0..height) |y| {
                var count: i8 = 0;
                var last_x: u8 = 0;

                for (0..width) |x| {
                    if (texture[x + y * width] != 0) {
                        count += 1;

                        if (count == 2 and x - last_x > 1) {
                            point = .{ @intCast((x + last_x) / 2), @as(u16, @intCast(y * width)) };
                            break :out;
                        }

                        last_x = @intCast(x);
                    }
                }
            } else {
                return error.NoDumbPoint;
            }

            var points_to_fill = try allocator.alloc([2]u16, width * height);
            defer allocator.free(points_to_fill);

            points_to_fill[0] = point;
            texture[point[0] + point[1]] = 255;

            var len: u32 = 1;
            var last: u32 = 0;
            const w: u16 = @intCast(width);

            while (true) {
                const right = .{ points_to_fill[last][0] + 1, points_to_fill[last][1] };
                if (texture[right[0] + right[1]] == 0) {
                    points_to_fill[len] = right;
                    texture[right[0] + right[1]] = 255;
                    len += 1;
                }
                const left = .{ points_to_fill[last][0] - 1, points_to_fill[last][1] };
                if (texture[left[0] + left[1]] == 0) {
                    points_to_fill[len] = left;
                    texture[left[0] + left[1]] = 255;
                    len += 1;
                }
                const down = .{ points_to_fill[last][0], points_to_fill[last][1] +  w};
                if (texture[down[0] + down[1]] == 0) {
                    points_to_fill[len] = down;
                    texture[down[0] + down[1]] = 255;
                    len += 1;
                }
                const up = .{ points_to_fill[last][0], points_to_fill[last][1] - w};
                if (texture[up[0] + up[1]] == 0) {
                    points_to_fill[len] = up;
                    texture[up[0] + up[1]] = 255;
                    len += 1;
                }

                last += 1;

                if (last >= len) break;
            }

            return texture;
        }

        fn new(tables: []const Table, reader: Reader, header: Header, size: u8, index: usize, allocator: *Allocator) !Glyph {
            const offset: u32 = blk: {
                var off: u32 = 0;

                if (header.index_to_loc_format == 1 ) {
                    reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 4);
                    off = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
                } else {
                    reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 2);
                    off = @byteSwap(@as(u16, @bitCast(try reader.read(2)))) * 2;
                }

                break :blk tables[@intFromEnum(Table.Type.Glyph)].offset + off;
            };

            reader.seek(offset);

            const number_of_contours = @byteSwap(@as(i16, @bitCast(try reader.read(2))));
            const x_min = @byteSwap(@as(i16, @bitCast(try reader.read(2))));
            const y_min = @byteSwap(@as(i16, @bitCast(try reader.read(2))));
            const x_max = @byteSwap(@as(i16, @bitCast(try reader.read(2))));
            const y_max = @byteSwap(@as(i16, @bitCast(try reader.read(2))));

            const factor: f32 = @as(f32, @floatFromInt(size)) / @as(f32, @floatFromInt(header.units_pem));
            const points: [5]i16 = .{
                number_of_contours,
                @as(i16, @intFromFloat(@round(@as(f32, @floatFromInt(x_min)) * factor))),
                @as(i16, @intFromFloat(@round(@as(f32, @floatFromInt(y_min)) * factor))),
                @as(i16, @intFromFloat(@round(@as(f32, @floatFromInt(x_max)) * factor))),
                @as(i16, @intFromFloat(@round(@as(f32, @floatFromInt(y_max)) * factor))),
            };

            if (points[0] < 0) {
                return error.CannotReadCompoundGlyphYet;
            } else {
                return try simple(points, reader, factor, allocator);
            }
        }
    };

    const Header = struct {
        version: u32,
        font_revision: u32,
        checksum_adjustment: u32,
        magic_number: u32,
        flags: u16,
        units_pem: u16,
        created: u64,
        modified: u64,
        xMin: u16,
        xMax: u16,
        yMin: u16,
        yMax: u16,
        mac_style: u16,
        lowest_rec_ppem: u16,
        font_direction_hint: u16,
        index_to_loc_format: u16,
        glyph_data_format: u16,

        fn new(reader: Reader) !Header {
            const version = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const font_revision = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const checksum_adjustment = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const magic_number = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const flags = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const units_pem = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const created = @byteSwap(@as(u64, @bitCast(try reader.read(8))));
            const modified = @byteSwap(@as(u64, @bitCast(try reader.read(8))));
            const xMin = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const xMax = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const yMin = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const yMax = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const mac_style = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const lowest_rec_ppem = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const font_direction_hint = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const index_to_loc_format = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const glyph_data_format = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

            if (magic_number != 0x5f0f3cf5) return error.WrongMagicNumber;

            return .{
                .version = @bitCast(version / (@as(u32, @intCast(1)) << 16)),
                .font_revision = @bitCast(font_revision / (@as(u32, @intCast(1)) << 16)),
                .checksum_adjustment = checksum_adjustment,
                .magic_number = magic_number,
                .flags = flags,
                .units_pem = units_pem,
                .created = created,
                .modified = modified,
                .xMin = @bitCast(@as(u16, @intCast(xMin))),
                .yMin = @bitCast(@as(u16, @intCast(yMin))),
                .xMax = @bitCast(@as(u16, @intCast(xMax))),
                .yMax = @bitCast(@as(u16, @intCast(yMax))),
                .mac_style = mac_style,
                .lowest_rec_ppem = lowest_rec_ppem,
                .font_direction_hint = @bitCast(@as(u16, @intCast(font_direction_hint))),
                .index_to_loc_format = @bitCast(@as(u16, @intCast(index_to_loc_format))),
                .glyph_data_format = @bitCast(@as(u16, @intCast(glyph_data_format))),
            };
        }
    };

    pub const Cmap = struct {
        end_code: ArrayList(u32),
        start_code: ArrayList(u32),
        id_delta: ArrayList(i16),
        glyph_id: ArrayList(u32),
        format: u8,

        fn format4(reader: Reader, allocator: *Allocator) !Cmap {
            const length = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const language = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const segment_count = @byteSwap(@as(u16, @bitCast(try reader.read(2)))) / 2;

            _ = length;
            _ = language;

            _ = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            _ = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            _ = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

            var end_code = try ArrayList(u32).init(allocator, segment_count);
            var start_code = try ArrayList(u32).init(allocator, segment_count);
            var id_delta = try ArrayList(i16).init(allocator, segment_count);
            var glyph_id = try ArrayList(u32).init(allocator, segment_count);

            for (0..segment_count) |_| { try end_code.push(@byteSwap(@as(u16, @bitCast(try reader.read(2))))); }
            if (@byteSwap(@as(u16, @bitCast(try reader.read(2)))) != 0) return error.ReservedPadNotZero;
            for (0..segment_count) |_| { try start_code.push(@byteSwap(@as(u16, @bitCast(try reader.read(2))))); }
            for (0..segment_count) |_| { try id_delta.push(@bitCast(@as(u16, @intCast(@byteSwap(@as(u16, @bitCast(try reader.read(2)))))))); }
            for (0..segment_count) |_| {
                const range_offset = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

                if (range_offset != 0) {
                    try glyph_id.push(@as(u32, @intCast(reader.pos())) - 2 + range_offset);
                } else {
                    try glyph_id.push(0);
                }
            }

            return .{
                .format = 4,
                .start_code = start_code,
                .end_code = end_code,
                .id_delta = id_delta,
                .glyph_id = glyph_id,
            };
        }

        fn format12(reader: Reader, allocator: *Allocator) !Cmap {
            if (@byteSwap(@as(u16, @bitCast(try reader.read(2)))) != 0) return error.ReservedPadNotZero;

            const length = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const language = @byteSwap(@as(u32, @bitCast(try reader.read(4))));

            _ = length;
            _ = language;

            const group_count = @byteSwap(@as(u32, @bitCast(try reader.read(4))));

            var start_code = try ArrayList(u32).init(allocator, group_count);
            var end_code = try ArrayList(u32).init(allocator, group_count);
            var glyph_code = try ArrayList(u32).init(allocator, group_count);

            for (0..group_count) |_| {
                try start_code.push(@byteSwap(@as(u32, @bitCast(try reader.read(4)))));
                try end_code.push(@byteSwap(@as(u32, @bitCast(try reader.read(4)))));
                try glyph_code.push(@byteSwap(@as(u32, @bitCast(try reader.read(4)))));
            }

            return .{
                .format = 12,
                .start_code = start_code,
                .end_code = end_code,
                .glyph_id = glyph_code,
                .id_delta = try ArrayList(i16).init(allocator, 0),
            };
        }

        fn get_index(self: Cmap, reader: Reader, char: u8) !u32 {
            if (self.format == 4) {
                for (0..self.start_code.items.len) |j| {
                    if (self.start_code.items[j] <= char and self.end_code.items[j] >= char) {
                        const index = blk: {
                            if (self.glyph_id.items[j] != 0) {
                                const index_offset = self.glyph_id.items[j] + 2 * (char - self.start_code.items[j]);

                                reader.seek(index_offset);
                                break :blk @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                            } else {
                                break :blk @as(u32, @intCast(self.id_delta.items[j] + char));
                            }
                        };

                        return index;
                    }
                }
            } else {
                for (0..self.start_code.items.len) |i| {
                    if (self.start_code.items[i] <= char and self.end_code.items[i] >= char) {
                        const index_offset = char - self.start_code.items[i];
                        return self.glyph_id.items[i] + index_offset;
                    }
                }
            }

            return error.GlyphIndexNotFound;
        }

        fn new(reader: Reader, allocator: *Allocator) !Cmap {
            const format = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

            if (format == 4) {
                return try format4(reader, allocator);
            } else if (format == 12) {
                return try format12(reader, allocator);
            }

            return error.FormatNotSupported;
        }

        fn deinit(self: *Cmap) void {
            self.id_delta.deinit();
            self.start_code.deinit();
            self.end_code.deinit();
            self.glyph_id.deinit();
        }
    };

    const Table = struct {
        name: [4]u8,
        checksum: u32,
        offset: u32,
        length: u32,

        const Type = enum {
            Map,
            Glyph,
            Header,
            HorizontalHeader,
            HorizontalMetrics,
            Location,
            Max,
            Name,
            PostScript,

            fn from_name(name: []const u8) !Table.Type {
                if (std.mem.eql(u8, name[0..], "cmap")) return Table.Type.Map
                else if (std.mem.eql(u8, name[0..], "glyf")) return Table.Type.Glyph
                else if (std.mem.eql(u8, name[0..], "head")) return Table.Type.Header
                else if (std.mem.eql(u8, name[0..], "hhea")) return Table.Type.HorizontalHeader
                else if (std.mem.eql(u8, name[0..], "htmx")) return Table.Type.HorizontalMetrics
                else if (std.mem.eql(u8, name[0..], "loca")) return Table.Type.Location
                else if (std.mem.eql(u8, name[0..], "maxp")) return Table.Type.Max
                else if (std.mem.eql(u8, name[0..], "name")) return Table.Type.Name
                else if (std.mem.eql(u8, name[0..], "post")) return Table.Type.PostScript
                else return error.TableNotRegistred;
            }
        };

        fn new(reader: Reader) !Table {
            return .{
                .name = try reader.read(4),
                .checksum = @byteSwap(@as(u32, @bitCast(try reader.read(4)))),
                .offset = @byteSwap(@as(u32, @bitCast(try reader.read(4)))),
                .length = @byteSwap(@as(u32, @bitCast(try reader.read(4)))),
            };
        }
    };

    pub fn new(file_path: []const u8, size: u8, allocator: *Allocator) !TrueTypeFont {
        const start = try std.time.Instant.now();

        const reader = try Reader.new(file_path);
        defer reader.shutdown();

        var header: Header = undefined;
        var glyphs_count: u32 = undefined;
        var map_table: Cmap = undefined;

        const position = reader.pos();
        reader.seek(position + 4);

        const num_tables = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

        reader.seek(position + 12);

        var tables: [@typeInfo(Table.Type).Enum.fields.len]Table = undefined;
        const pos = reader.pos();

        for (0..num_tables) |k| {
            reader.seek(pos + k * @sizeOf(Table));

            const table = try Table.new(reader);
            const typ = Table.Type.from_name(&table.name) catch continue;

            tables[@intFromEnum(typ)] = table;

            switch (typ) {
                .Header => {
                    reader.seek(table.offset);
                    header = try Header.new(reader);
                },
                .Max => {
                    reader.seek(table.offset + 4);
                    glyphs_count = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                },
                .Map => {
                    reader.seek(table.offset);

                    const version = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                    const number_subtables = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                    const table_pos = reader.pos();

                    _ = version;

                    for (0..number_subtables) |i| {
                        reader.seek(table_pos + 8 * i);

                        const id = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                        const specific_id = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
                        const offset = @byteSwap(@as(u32, @bitCast(try reader.read(4))));

                        if (specific_id != 0 and specific_id != 4 and specific_id != 3) continue;
                        if (id != 0) continue;

                        reader.seek(table.offset + offset);
                        map_table = Cmap.new(reader, allocator) catch {
                            continue;
                        };

                        break;
                    }
                },
                else => {}
            }
        }

        var glyphs: [@typeInfo(Type).Enum.fields.len]Glyph = undefined;

        for (0..@typeInfo(Type).Enum.fields.len) |i| {
            const typ: Type = @enumFromInt(i);
            const index = try map_table.get_index(reader, typ.code());

            glyphs[i] = try Glyph.new(&tables, reader, header, size, index, allocator);
        }

        map_table.deinit();
        const end = try std.time.Instant.now();
        std.debug.print("elapsed: {}\n", .{end.since(start) / 1000});

        const i = @intFromEnum(Type.z);
        // for (0..glyphs[i].height) |y| {
        //     glyphs[i].texture[(y + 1) * glyphs[i].width - 1] = 255;
        //     glyphs[i].texture[y * glyphs[i].width] = 255;
        // }

        // @memset(glyphs[i].texture[0..glyphs[i].width], 255);
        // @memset(glyphs[i].texture[(glyphs[i].height - 1) * glyphs[i].width..glyphs[i].height * glyphs[i].width - 1], 255);

        return .{
            .glyphs = glyphs,
            .texture = glyphs[i].texture,
            .allocator = allocator,
            .width = glyphs[i].width,
            .height = glyphs[i].height,
        };
    }

    pub fn deinit(self: *TrueTypeFont) void {
        for (self.glyphs) |glyph| {
            self.allocator.free(glyph.texture);
        }
    }
};
