const std = @import("std");

const _collections = @import("../util/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _io = @import("../util/io.zig");

const ArrayList = _collections.ArrayList;
const Reader = _io.Io.Reader;
const logger = _configuration.Configuration.logger;

pub const TrueTypeFont = struct {
    glyphs: ArrayList(Glyph),
    tables: []Table,
    header: Header,
    allocator: std.mem.Allocator,

    num_tables: u32,
    scalar_type: u32,
    range_shift: u32,
    search_range: u32,
    entry_selector: u32,

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

        fn offset(tables: []const Table, reader: *Reader, header: Header, index: usize) u32 {
            var off: u32 = 0;

            if (header.index_to_loc_format == 1 ) {
                reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 4);
                off = convert(&reader.read(4));
            } else {
                reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 2);
                off = convert(&reader.read(2)) * 2;
            }

            return tables[@intFromEnum(Table.Type.Glyph)].offset + off;
        }

        fn coords(reader: *Reader, byte_flag: u8, delta_flag: u8, flag: u8) i16 {
            var value: i16 = 0;

            if ((flag & byte_flag) != 0) {
                const v = reader.read(1)[0];

                if ((flag & delta_flag) != 0) {
                    value += v;
                } else {
                    value -= v;
                }
            } else if ((~flag & delta_flag) != 0) {
                value += @bitCast(@as(u16, @intCast(convert(&reader.read(2)))));
            }

            return value;
        }

        fn simple(glyph_points: [5]i16, reader: *Reader, allocator: std.mem.Allocator) !Glyph {
            const number_of_contours = glyph_points[0];

            const on_curve:  u8 = 0b00000001;
            const x_is_byte: u8 = 0b00000010;
            const y_is_byte: u8 = 0b00000100;
            const repeat:    u8 = 0b00001000;
            const x_delta:   u8 = 0b00010000;
            const y_delta:   u8 = 0b00100000;

            var contour_ends = ArrayList(i16).init(allocator, @intCast(number_of_contours)) catch |e| {
                logger.log(.Error, "Failed to initlize array list of countours", .{});

                return e;
            };

            var max: u32 = 0;
            for (0..contour_ends.items.len) |_| {
                const new_contour = convert(&reader.read(2));
                if (new_contour > max) {
                    max = new_contour;
                }

                contour_ends.push(@bitCast(@as(u16, @intCast(new_contour)))) catch |e| {
                    logger.log(.Error, "Array list refuses to receive one more item", .{});

                    return e;
                };
            }

            var flags = ArrayList(u8).init(allocator, max) catch |e| {
                logger.log(.Error, "Failed to initlize array list of flags", .{});

                return e;
            };

            defer flags.deinit();

            var points = ArrayList(Point).init(allocator, max) catch |e| {
                logger.log(.Error, "Failed to initlize array list of points", .{});

                return e;
            };

            if (number_of_contours <= 0) return error.NoCountour;

            const off = convert(&reader.read(2));

            const pos = reader.pos();
            reader.seek(off + pos);

            var i: u32 = 0;
            while (i < max + 1) {
                const flag = reader.read(1)[0];

                flags.push(flag) catch |e| {
                    logger.log(.Error, "Array list refuses to receive one more item", .{});

                    return e;
                };
                points.push(.{
                    .on_curve = (flag & on_curve) > 0
                }) catch |e| {
                    logger.log(.Error, "Array list refuses to receive one more item", .{});

                    return e;
                };

                if ((flag & repeat) != 0) {
                    var repeat_count = reader.read(1)[0];
                    i += repeat_count;

                    while (repeat_count > 0) {
                        flags.push(flag) catch |e| {
                            logger.log(.Error, "Array list refuses to receive one more item", .{});

                            return e;
                        };
                        points.push(.{
                            .on_curve = (flag & on_curve) > 0
                        }) catch |e| {
                            logger.log(.Error, "Array list refuses to receive one more item", .{});

                            return e;
                        };

                        repeat_count -= 1;
                    }
                }

                i += 1;
            }

            for (0..max + 1) |k| {
                points.items[k].x = coords(reader, x_is_byte, x_delta, flags.items[k]);
                points.items[k].y = coords(reader, y_is_byte, y_delta, flags.items[k]);
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

        fn new(tables: []const Table, reader: *Reader, header: Header, allocator: std.mem.Allocator, index: usize) !Glyph {
            const off = offset(tables, reader, header, index);
            reader.seek(off);

            const number_of_contours = convert(&reader.read(2));
            const x_min              = convert(&reader.read(2));
            const y_min              = convert(&reader.read(2));
            const x_max              = convert(&reader.read(2));
            const y_max              = convert(&reader.read(2));

            const points: [5]i16 = .{
                @bitCast(@as(u16, @intCast(number_of_contours))),
                @bitCast(@as(u16, @intCast(x_min))),
                @bitCast(@as(u16, @intCast(y_min))),
                @bitCast(@as(u16, @intCast(x_max))),
                @bitCast(@as(u16, @intCast(y_max))),
            };

            if (points[0] == -1) {
                return error.CouldNotInitializeGlyph;
                // return try read_compound_glyph(glyph);
            } else {

                return try simple(points, reader, allocator);
            }
        }

        fn deinit(self: *Glyph) void {
            self.points.deinit();
            self.contour_ends.deinit();
        }
    };

    const Header = struct {
        xMin:                 i16,
        yMin:                 i16,
        xMax:                 i16,
        yMax:                 i16,
        flags:                u32,
        version:              i32,
        created:              u64,
        modified:             u64,
        mac_style:            u32,
        units_pem:            u32,
        magic_number:         u32,
        font_revision:        i32,
        lowest_rec_ppem:      u32,
        glyph_data_format:    i16,
        font_direction_hint:  i16,
        index_to_loc_format:  i16,
        checksum_adjustment:  u32,

        fn new(reader: *Reader) !Header {
            const version             = convert(&reader.read(4));
            const font_revision       = convert(&reader.read(4));
            const checksum_adjustment = convert(&reader.read(4));
            const magic_number        = convert(&reader.read(4));
            const flags               = convert(&reader.read(2));
            const units_pem           = convert(&reader.read(2));
            const created             = convert(&reader.read(8));
            const modified            = convert(&reader.read(8));
            const xMin                = convert(&reader.read(2));
            const xMax                = convert(&reader.read(2));
            const yMin                = convert(&reader.read(2));
            const yMax                = convert(&reader.read(2));
            const mac_style           = convert(&reader.read(2));
            const lowest_rec_ppem     = convert(&reader.read(2));
            const font_direction_hint = convert(&reader.read(2));
            const index_to_loc_format = convert(&reader.read(2));
            const glyph_data_format   = convert(&reader.read(2));

            if (magic_number != 0x5f0f3cf5) return error.WrongMagicNumber;

            return .{
                .version              = @bitCast(version / (@as(u32, @intCast(1)) << 16)),
                .font_revision        = @bitCast(font_revision / (@as(u32, @intCast(1)) << 16)),
                .checksum_adjustment  = checksum_adjustment,
                .magic_number         = magic_number,
                .flags                = flags,
                .units_pem            = units_pem,
                .created              = created,
                .modified             = modified,
                .xMin                 = @bitCast(@as(u16, @intCast(xMin))),
                .yMin                 = @bitCast(@as(u16, @intCast(yMin))),
                .xMax                 = @bitCast(@as(u16, @intCast(xMax))),
                .yMax                 = @bitCast(@as(u16, @intCast(yMax))),
                .mac_style            = mac_style,
                .lowest_rec_ppem      = lowest_rec_ppem,
                .font_direction_hint  = @bitCast(@as(u16, @intCast(font_direction_hint))),
                .index_to_loc_format  = @bitCast(@as(u16, @intCast(index_to_loc_format))),
                .glyph_data_format    = @bitCast(@as(u16, @intCast(glyph_data_format))),
            };
        }
    };

    const Table = struct {
        checksum: u32,
        offset: u32,
        length: u32,

        const Type = enum {
            Location,
            Header,
            Glyph,
            Max,

            None,

            fn from_name(name: []const u8) Type {
                if (std.mem.eql(u8, name[0..], "loca")) {
                    return Type.Location;
                } else if (std.mem.eql(u8, name[0..], "head")) {
                    return Type.Header;
                } else if (std.mem.eql(u8, name[0..], "glyf")) {
                    return Type.Glyph;
                } else if (std.mem.eql(u8, name[0..], "maxp")) {
                    return Type.Max;
                } else {
                    return Type.None;
                }
            }
        };

        fn new(reader: *Reader) !Table {
            return .{
                .checksum = convert(&reader.read(4)),
                .offset   = convert(&reader.read(4)),
                .length   = convert(&reader.read(4)),
            };
        }
    };

    pub fn new(file_path: []const u8, allocator: std.mem.Allocator) !TrueTypeFont {
        var reader = Reader.new(file_path) catch |e| {
            logger.log(.Error, "Failed to get the reader of file: {s}", .{file_path});

            return e;
        };

        const scalar_type     = convert(&reader.read(4));
        const num_tables      = convert(&reader.read(2));
        const search_range    = convert(&reader.read(2));
        const entry_selector  = convert(&reader.read(2));
        const range_shift     = convert(&reader.read(2));
        var header: Header    = undefined;
        var glyphs_count: u32 = undefined;

        var tables = allocator.alloc(Table, @intFromEnum(Table.Type.None)) catch |e| {
            logger.log(.Error, "Out of memory", .{});

            return e;
        };

        const pos = reader.pos();

        for (0..num_tables) |k| {
            reader.seek(pos + k * 16);

            const name = reader.read(4);

            const typ = Table.Type.from_name(&name);
            const index = @intFromEnum(typ);

            if (typ != Table.Type.None) tables[index] = Table.new(&reader) catch |e| {
                logger.log(.Error, "Failed to instanciate the table: {}", .{index});

                return e;
            };

            switch (typ) {
                .Header => {
                    reader.seek(tables[index].offset);
                    header = try Header.new(&reader);
                },
                .Max => {
                    reader.seek(tables[index].offset + 4);

                    glyphs_count = convert(&reader.read(2));
                },
                else => {},
            }
        }

        var glyphs = ArrayList(Glyph).init(allocator, @intCast(glyphs_count)) catch |e| {
            logger.log(.Error, "Too much glyphs to allocate: {}", .{glyphs_count});

            return e;
        };

        const count = 128 - 32;
        for (0..count) |k| {
            if (reader.failed) return error.ReaderFailed;

            glyphs.push(Glyph.new(tables, &reader, header, allocator, 32 + k) catch {continue;}) catch |e| {
                logger.log(.Error, "Failed to add glyph: {}", .{k});

                return e;
            };
        }

        return .{
            .header         = header,
            .tables         = tables,
            .glyphs         = glyphs,
            .num_tables     = num_tables,
            .scalar_type    = scalar_type,
            .range_shift    = range_shift,
            .search_range   = search_range,
            .entry_selector = entry_selector,
            .allocator = allocator,
        };
    }
    // fn get_date(slice: [8]u8) u64 {
    //     var array1: [4]u8 = undefined;
    //     var array2: [4]u8 = undefined;

    //     @memcpy(&array1, slice[0..4]);
    //     @memcpy(&array2, slice[4..8]);

    //     return @as(u64, @intCast(to_u32(array1))) * 0x100000000 + to_u32(array2);
    // }

    fn convert(slice: []const u8) u32 {
        return switch (slice.len) {
            4 => @as(u32, @intCast(slice[0])) << 24 | @as(u32, @intCast(slice[1])) << 16 | @as(u32, @intCast(slice[2])) << 8 | @as(u32, @intCast(slice[3])),
            2 => @as(u32, @intCast(slice[0])) << 8 | @as(u32, @intCast(slice[1])),
            else => undefined,
        };
    }

    pub fn deinit(self: *TrueTypeFont) void {
        for (0..self.glyphs.items.len) |i| {
            self.glyphs.items[i].deinit();
        }

        self.glyphs.deinit();
        self.allocator.free(self.tables);
    }
};
