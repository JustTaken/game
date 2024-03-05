const std = @import("std");

const _collections = @import("../util/collections.zig");
const _math = @import("../util/math.zig");

const ArrayList = _collections.ArrayList;
const Vec = _math.Vec;

pub const TrueTypeFont = struct {
    glyphs: ArrayList(Glyph),
    tables: ArrayList(Table),
    header: Header,

    num_tables: u16,
    scalar_type: u32,
    range_shift: u16,
    search_range: u16,
    entry_selector: u16,

    const Glyph = struct {
        x_min: i16,
        y_min: i16,
        x_max: i16,
        y_max: i16,

        points: ArrayList(Point),
        contour_ends: ArrayList(i16),

        const Point = struct {
            x: i16 = 0,
            y: i16 = 0,

            on_curve: bool,
        };

        fn offset(tables: ArrayList(Table), file: std.fs.File, header: Header, index: usize) !u32 {
            var o: u32 = 0;
            var start_offset: u32 = undefined;

            for (tables.items) |table| {
                if (std.mem.eql(u8, table.name[0..], "loca")) {
                    if (header.index_to_loc_format == 1 ) {
                        var diff: [4]u8 = undefined;
                        try file.seekTo(table.offset + index * 4);
                        std.debug.assert(try file.read(&diff) == diff.len);
                        o = to_u32(diff);
                    } else {
                        var diff: [2]u8 = undefined;
                        try file.seekTo(table.offset + index * 2);
                        std.debug.assert(try file.read(&diff) == diff.len);
                        o = to_u16(diff) * 2;
                    }
                } else if (std.mem.eql(u8, table.name[0..], "glyf")) {
                    start_offset = table.offset;
                }
            }

            return start_offset + o;
        }

        fn coords(file: std.fs.File, byte_flag: u8, delta_flag: u8, flag: u8) !i16 {
            var value: i16 = 0;

            if ((flag & byte_flag) != 0) {
                if ((flag & delta_flag) != 0) {
                    var add: [1]u8 = undefined;
                    std.debug.assert(try file.read(&add) == add.len);
                    value += add[0];
                } else {
                    var add: [1]u8 = undefined;
                    std.debug.assert(try file.read(&add) == add.len);
                    value -= add[0];
                }
            } else if ((~flag & delta_flag) != 0) {
                var add: [2]u8 = undefined;
                std.debug.assert(try file.read(&add) == add.len);
                value += @as(i16, @bitCast(to_u16(add)));
            }

            return value;
        }

        fn simple(glyph_points: [5]i16, file: std.fs.File, allocator: std.mem.Allocator) !Glyph {
            const number_of_contours = glyph_points[0];

            const on_curve:  u8 = 0b00000001;
            const x_is_byte: u8 = 0b00000010;
            const y_is_byte: u8 = 0b00000100;
            const repeat:    u8 = 0b00001000;
            const x_delta:   u8 = 0b00010000;
            const y_delta:   u8 = 0b00100000;

            var contour_ends = try ArrayList(i16).init(allocator, null);
            var flags = try ArrayList(u8).init(allocator, null);
            var points = try ArrayList(Point).init(allocator, null);

            if (number_of_contours == 0) return error.NoCountour;

            var max: u16 = 0;
            for (0..@intCast(number_of_contours)) |_| {
                var contour: [2]u8 = undefined;
                std.debug.assert(try file.read(&contour) == contour.len);
                const new_contour = to_u16(contour);
                if (new_contour > max) {
                    max = new_contour;
                }
                try contour_ends.push(@bitCast(new_contour));
            }

            var o: [2]u8 = undefined;
            std.debug.assert(try file.read(&o) == o.len);

            const pos = try file.getPos();
            try file.seekTo(to_u16(o) + pos);

            var i: u32 = 0;
            while (i < max + 1) {
                var flag: [1]u8 = undefined;
                std.debug.assert(try file.read(&flag) == flag.len);
                try flags.push(flag[0]);
                try points.push(.{
                    .on_curve = (flag[0] & on_curve) > 0
                });

                if ((flag[0] & repeat) != 0) {
                    var repeat_count: [1]u8 = undefined;
                    std.debug.assert(try file.read(&repeat_count) == repeat_count.len);
                    i += repeat_count[0];

                    while (repeat_count[0] > 0) {
                        try flags.push(flag[0]);
                        try points.push(.{
                            .on_curve = (flag[0] & on_curve) > 0
                        });

                        repeat_count[0] -= 1;
                    }
                }

                i += 1;
            }

            for (0..max + 1) |k| {
                points.items[k].x = try coords(file, x_is_byte, x_delta, flags.items[k]);
                points.items[k].y = try coords(file, y_is_byte, y_delta, flags.items[k]);
            }

            return .{
                .x_min        = glyph_points[1],
                .y_min        = glyph_points[2],
                .x_max        = glyph_points[3],
                .y_max        = glyph_points[4],
                .points       = points,
                .contour_ends = contour_ends,
            };
        }

        fn new(tables: ArrayList(Table), file: std.fs.File, header: Header, allocator: std.mem.Allocator, index: usize) !Glyph {
            const o = try offset(tables, file, header, index);
            try file.seekTo(o);

            var number_of_contours: [2]u8 = undefined;
            var x_min:              [2]u8 = undefined;
            var y_min:              [2]u8 = undefined;
            var x_max:              [2]u8 = undefined;
            var y_max:              [2]u8 = undefined;

            std.debug.assert(try file.read(&number_of_contours) == number_of_contours.len);
            std.debug.assert(try file.read(&x_min) == x_min.len);
            std.debug.assert(try file.read(&y_min) == y_min.len);
            std.debug.assert(try file.read(&x_max) == x_max.len);
            std.debug.assert(try file.read(&y_max) == y_max.len);

            const points: [5]i16 = .{
                @as(i16, @bitCast(to_u16(number_of_contours))),
                @as(i16, @bitCast(to_u16(x_min))),
                @as(i16, @bitCast(to_u16(y_min))),
                @as(i16, @bitCast(to_u16(x_max))),
                @as(i16, @bitCast(to_u16(y_max))),
            };

            if (@as(i16, @bitCast(to_u16(number_of_contours))) == -1) {
                return error.CouldNotInitializeGlyph;
                // return try read_compound_glyph(glyph);
            } else {
                return try simple(points, file, allocator);
            }
        }
    };

    const Header = struct {
        xMin:                 i16,
        yMin:                 i16,
        xMax:                 i16,
        yMax:                 i16,
        flags:                u16,
        version:              i32,
        created:              u64,
        modified:             u64,
        mac_style:            u16,
        units_pem:            u16,
        magic_number:         u32,
        font_revision:        i32,
        lowest_rec_ppem:      u16,
        glyph_data_format:    i16,
        font_direction_hint:  i16,
        index_to_loc_format:  i16,
        checksum_adjustment:  u32,

        fn new(file: std.fs.File) !Header {
            var version:             [4]u8 = undefined;
            var font_revision:       [4]u8 = undefined;
            var checksum_adjustment: [4]u8 = undefined;
            var magic_number:        [4]u8 = undefined;
            var flags:               [2]u8 = undefined;
            var units_pem:           [2]u8 = undefined;
            var created:             [8]u8 = undefined;
            var modified:            [8]u8 = undefined;
            var xMin:                [2]u8 = undefined;
            var xMax:                [2]u8 = undefined;
            var yMin:                [2]u8 = undefined;
            var yMax:                [2]u8 = undefined;
            var mac_style:           [2]u8 = undefined;
            var lowest_rec_ppem:     [2]u8 = undefined;
            var font_direction_hint: [2]u8 = undefined;
            var index_to_loc_format: [2]u8 = undefined;
            var glyph_data_format:   [2]u8 = undefined;

            std.debug.assert(try file.read(&version)             == version.len);
            std.debug.assert(try file.read(&font_revision)       == font_revision.len);
            std.debug.assert(try file.read(&checksum_adjustment) == checksum_adjustment.len);
            std.debug.assert(try file.read(&magic_number)        == magic_number.len);
            std.debug.assert(try file.read(&flags)               == flags.len);
            std.debug.assert(try file.read(&units_pem)           == units_pem.len);
            std.debug.assert(try file.read(&created)             == created.len);
            std.debug.assert(try file.read(&modified)            == modified.len);
            std.debug.assert(try file.read(&xMin)                == xMin.len);
            std.debug.assert(try file.read(&xMax)                == xMax.len);
            std.debug.assert(try file.read(&yMin)                == yMin.len);
            std.debug.assert(try file.read(&yMax)                == yMax.len);
            std.debug.assert(try file.read(&mac_style)           == mac_style.len);
            std.debug.assert(try file.read(&lowest_rec_ppem)     == lowest_rec_ppem.len);
            std.debug.assert(try file.read(&font_direction_hint) == font_direction_hint.len);
            std.debug.assert(try file.read(&index_to_loc_format) == index_to_loc_format.len);
            std.debug.assert(try file.read(&glyph_data_format)   == glyph_data_format.len);

            std.debug.assert(to_u32(magic_number)                == 0x5f0f3cf5);

            return .{
                .version             = @bitCast(to_u32(version) / (@as(u32, @intCast(1)) << 16)),
                .font_revision       = @bitCast(to_u32(font_revision) / (@as(u32, @intCast(1)) << 16)),
                .checksum_adjustment = to_u32(checksum_adjustment),
                .magic_number        = to_u32(magic_number),
                .flags               = to_u16(flags),
                .units_pem           = to_u16(units_pem),
                .created             = get_date(created),
                .modified            = get_date(modified),
                .xMin                = @bitCast(to_u16(xMin)),
                .yMin                = @bitCast(to_u16(yMin)),
                .xMax                = @bitCast(to_u16(xMax)),
                .yMax                = @bitCast(to_u16(yMax)),
                .mac_style           = to_u16(mac_style),
                .lowest_rec_ppem     = to_u16(lowest_rec_ppem),
                .font_direction_hint = @bitCast(to_u16(font_direction_hint)),
                .index_to_loc_format = @bitCast(to_u16(index_to_loc_format)),
                .glyph_data_format   = @bitCast(to_u16(glyph_data_format)),
            };
        }
    };

    const Table = struct {
        name: [4]u8,
        checksum: u32,
        offset: u32,
        length: u32,

        fn new(file: std.fs.File) !Table {
            var name:     [4]u8 = undefined;
            var checksum: [4]u8 = undefined;
            var offset:   [4]u8 = undefined;
            var length:   [4]u8 = undefined;

            std.debug.assert(try file.read(&name )     == name .len);
            std.debug.assert(try file.read(&checksum ) == checksum .len);
            std.debug.assert(try file.read(&offset )   == offset .len);
            std.debug.assert(try file.read(&length )   == length .len);

            return .{
                .name     = name,
                .checksum = to_u32(checksum),
                .offset   = to_u32(offset),
                .length   = to_u32(length),
            };
        }
    };

    pub fn new(file_path: []const u8, allocator: std.mem.Allocator) !TrueTypeFont {
        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var header:        Header = undefined;
        var glyphs_count:   [2]u8 = undefined;
        var scalar_type:    [4]u8 = undefined;
        var num_tables:     [2]u8 = undefined;
        var search_range:   [2]u8 = undefined;
        var entry_selector: [2]u8 = undefined;
        var range_shift:    [2]u8 = undefined;

        std.debug.assert(try file.read(&scalar_type)    == scalar_type.len);
        std.debug.assert(try file.read(&num_tables)     == num_tables.len);
        std.debug.assert(try file.read(&search_range)   == search_range.len);
        std.debug.assert(try file.read(&entry_selector) == entry_selector.len);
        std.debug.assert(try file.read(&range_shift)    == range_shift.len);

        var tables = try ArrayList(Table).init(allocator, @intCast(to_u16(num_tables)));
        for (0..to_u16(num_tables)) |_| {
            const table = try Table.new(file);
            const pos = try file.getPos();
            try tables.push(table);

            if (std.mem.eql(u8, table.name[0..], "head")) {
                try file.seekTo(table.offset);
                header = try Header.new(file);
            } else if (std.mem.eql(u8, table.name[0..], "maxp")) {
                try file.seekTo(table.offset + 4);
                std.debug.assert(try file.read(&glyphs_count) == glyphs_count.len);
            }

            try file.seekTo(pos);
        }

        var glyphs = try ArrayList(Glyph).init(allocator, @intCast(to_u16(glyphs_count)));

        for (0..to_u16(glyphs_count)) |k| {
            try glyphs.push(Glyph.new(tables, file, header, allocator, k) catch {continue;});
        }

        return .{
            .header         = header,
            .tables         = tables,
            .glyphs         = glyphs,
            .num_tables     = to_u16(num_tables),
            .scalar_type    = to_u32(scalar_type),
            .range_shift    = to_u16(range_shift),
            .search_range   = to_u16(search_range),
            .entry_selector = to_u16(entry_selector),
        };
    }

    fn get_date(slice: [8]u8) u64 {
        var array1: [4]u8 = undefined;
        var array2: [4]u8 = undefined;

        @memcpy(&array1, slice[0..4]);
        @memcpy(&array2, slice[4..8]);

        return @as(u64, @intCast(to_u32(array1))) * 0x100000000 + to_u32(array2);
    }

    fn to_u32(slice: [4]u8) u32 {
        return @as(u32, @intCast(slice[0])) << 24 | @as(u32, @intCast(slice[1])) << 16 | @as(u32, @intCast(slice[2])) << 8 | @as(u32, @intCast(slice[3]));
    }

    fn to_u16(slice: [2]u8) u16 {
        return @as(u16, @intCast(slice[0])) << 8 | @as(u16, @intCast(slice[1]));
    }
};

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
