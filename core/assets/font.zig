const std            = @import("std");

const _io            = @import("../io/io.zig");
const _collections   = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _math          = @import("../math/math.zig");
const _object      = @import("object.zig");

const Vec            = _math.Vec;

const ArrayList      = _collections.ArrayList;
const Allocator      = std.mem.Allocator;
const Reader         = _io.Io.Reader;
const Object         = _object.ObjectHandler.Object;
const logger         = _configuration.Configuration.logger;

pub const TrueTypeFont = struct {
    glyphs:    ArrayList(Glyph),
    tables:    []Table,
    header:    Header,
    allocator: Allocator,
    path:      []const u8,

    num_tables:     u32,
    scalar_type:    u32,
    range_shift:    u32,
    search_range:   u32,
    entry_selector: u32,

    pub const Type = enum(u8) {
        a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z,
        space, comma, coulon, semi_coulon,

        pub fn indice(self: Type) u8 {
            return switch (self) {
                .space => ' ',
                .comma => ',',
                .coulon => '.',
                .semi_coulon => ';',
                else => @intFromEnum(self) + 97,
            };
        }
    };

    const Glyph = struct {
        vertex:       ArrayList(Vec),
        index:        ArrayList(u16),
        // contour_ends: ArrayList(u16),
        // points:       ArrayList(Point),
        x_min:        i16,
        y_min:        i16,
        x_max:        i16,
        y_max:        i16,

        const Point = struct {
            x:        f32 = 0,
            y:        f32 = 0,
            on_curve: bool,
        };

        fn simple(glyph_points: [5]i16, reader: Reader, factor: f32, allocator: Allocator) !Glyph {
            const number_of_contours: u32 = @intCast(glyph_points[0]);
            if (number_of_contours == 0) return error.NoCountour;

            const on_curve:  u8 = 0x01;
            const x_is_byte: u8 = 0x02;
            const y_is_byte: u8 = 0x04;
            const repeat:    u8 = 0x08;
            const x_delta:   u8 = 0x10;
            const y_delta:   u8 = 0x20;

            var contour_ends = ArrayList(u16).init(allocator, number_of_contours) catch |e| {
                logger.log(.Error, "Failed to initlize array list of countours", .{});

                return e;
            };

            defer contour_ends.deinit();

            var max: u32 = 0;
            for (0..number_of_contours) |_| {
                const contour_end = convert(&try reader.read(2));

                if (contour_end > max) {
                    max = contour_end;
                }

                contour_ends.push(@intCast(contour_end)) catch |e| {
                    logger.log(.Error, "Array list refuses to receive one more item", .{});
                    return e;
                };
            }

            var flags = ArrayList(u8).init(allocator, max + 1) catch |e| {
                logger.log(.Error, "Failed to initlize array list of flags", .{});
                return e;
            };

            defer flags.deinit();

            var points = ArrayList(Point).init(allocator, max + 1) catch |e| {
                logger.log(.Error, "Failed to initlize array list of points", .{});
                return e;
            };

            defer points.deinit();

            const off = convert(&try reader.read(2));
            const pos = reader.pos();

            reader.seek(off + pos);

            var i: u32 = 0;
            while (i < max + 1) {
                const flag = (try reader.read(1))[0];

                try flags.push(flag);
                try points.push(.{ .on_curve = flag & on_curve > 0 });

                if ((flag & repeat) != 0) {
                    var repeat_count = (try reader.read(1))[0];
                    i += repeat_count;

                    while (repeat_count > 0) {
                        try flags.push(flag);
                        try points.push(.{ .on_curve = flag & on_curve > 0 });

                        repeat_count -= 1;
                    }
                }

                i += 1;
            }

            var vertex = try ArrayList(Vec).init(allocator, max + 1);
            var index = try ArrayList(u16).init(allocator, max + 1);

            var values: [2]i16 = .{ 0, 0 };
            for (0..max + 1) |k| {
                points.items[k].x = blk: {
                    if (flags.items[k] & x_is_byte != 0) {
                        const v = (try reader.read(1))[0];

                        if (flags.items[k] & x_delta != 0) values[0] += v
                        else values[0] -= v;
                    } else if (~flags.items[k] & x_delta != 0) {
                        values[0] += @bitCast(@as(u16, @intCast(convert(&try reader.read(2)))));
                    }

                    break :blk @as(f32, @floatFromInt(values[0])) * factor;
                };
            }

            for (0..max + 1) |k| {
                points.items[k].y = blk: {
                    if (flags.items[k] & y_is_byte != 0) {
                        const v = (try reader.read(1))[0];

                        if (flags.items[k] & y_delta != 0) values[1] += v
                        else values[1] -= v;
                    } else if (~flags.items[k] & y_delta != 0) {
                        values[1] += @bitCast(@as(u16, @intCast(convert(&try reader.read(2)))));
                    }

                    break :blk @as(f32, @floatFromInt(values[1])) * factor;
                };

                try index.push(@intCast(vertex.items.len));
                try vertex.push(.{
                    .x = points.items[k].x,
                    .y = points.items[k].y,
                    .z = 0.0,
                });
            }

            return .{
                .x_min        = glyph_points[1],
                .y_min        = glyph_points[2],
                .x_max        = glyph_points[3],
                .y_max        = glyph_points[4],
                // .contour_ends = contour_ends,
                // .points       = points,
                .vertex       = vertex,
                .index        = index,
            };
        }

        fn new(tables: []const Table, reader: Reader, header: Header, allocator: Allocator, index: usize) !Glyph {
            const offset: u32 = blk: {
                var off: u32 = 0;

                if (header.index_to_loc_format == 1 ) {
                    reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 4);
                    off = convert(&try reader.read(4));
                } else {
                    reader.seek(tables[@intFromEnum(Table.Type.Location)].offset + index * 2);
                    off = convert(&try reader.read(2)) * 2;
                }

                break :blk tables[@intFromEnum(Table.Type.Glyph)].offset + off;
            };

            reader.seek(offset);

            const number_of_contours = convert(&try reader.read(2));
            const x_min              = convert(&try reader.read(2));
            const y_min              = convert(&try reader.read(2));
            const x_max              = convert(&try reader.read(2));
            const y_max              = convert(&try reader.read(2));

            const points: [5]i16 = .{
                @bitCast(@as(u16, @intCast(number_of_contours))),
                @bitCast(@as(u16, @intCast(x_min))),
                @bitCast(@as(u16, @intCast(y_min))),
                @bitCast(@as(u16, @intCast(x_max))),
                @bitCast(@as(u16, @intCast(y_max))),
            };

            const factor: f32 = 1 / @as(f32, @floatFromInt(header.units_pem));

            if (points[0] < 0) {
                return error.CouldNotInitializeGlyph;
            } else {
                return try simple(points, reader, factor, allocator);
            }
        }

        // fn deinit(self: *Glyph) void {
        //     // self.points.deinit();
        //     // self.contour_ends.deinit();
        //     self.vertex.deinit();
        //     self.index.deinit();

        // }
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

        fn new(reader: Reader) !Header {
            const version             = convert(&try reader.read(4));
            const font_revision       = convert(&try reader.read(4));
            const checksum_adjustment = convert(&try reader.read(4));
            const magic_number        = convert(&try reader.read(4));
            const flags               = convert(&try reader.read(2));
            const units_pem           = convert(&try reader.read(2));
            const created             = get_date(try reader.read(8));
            const modified            = get_date(try reader.read(8));
            const xMin                = convert(&try reader.read(2));
            const xMax                = convert(&try reader.read(2));
            const yMin                = convert(&try reader.read(2));
            const yMax                = convert(&try reader.read(2));
            const mac_style           = convert(&try reader.read(2));
            const lowest_rec_ppem     = convert(&try reader.read(2));
            const font_direction_hint = convert(&try reader.read(2));
            const index_to_loc_format = convert(&try reader.read(2));
            const glyph_data_format   = convert(&try reader.read(2));

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
    const Cmap4 = struct {
        fn get_indices(reader: Reader, char: u8, allocator: Allocator) !u32 {
            const length = convert(&try reader.read(2));
            _ = length;
            const language = convert(&try reader.read(2));
            _ = language;
            const segment_count = convert(&try reader.read(2)) / 2;

            _ = convert(&try reader.read(2));
            _ = convert(&try reader.read(2));
            _ = convert(&try reader.read(2));

            const end_code = try allocator.alloc(u32, segment_count);
            defer allocator.free(end_code);

            const start_code = try allocator.alloc(u32, segment_count);
            defer allocator.free(start_code);

            const id_delta = try allocator.alloc(i16, segment_count);
            defer allocator.free(id_delta);

            const id_range_offset = try allocator.alloc(u32, segment_count);
            defer allocator.free(id_range_offset);

            for (0..segment_count) |j| { end_code[j] = convert(&try reader.read(2)); }
            if (convert(&try reader.read(2)) != 0) return error.ReservedPadNotZero;
            for (0..segment_count) |j| { start_code[j] = convert(&try reader.read(2)); }
            for (0..segment_count) |j| { id_delta[j] = @bitCast(@as(u16, @intCast(convert(&try reader.read(2))))); }
            for (0..segment_count) |j| {
                const range_offset = convert(&try reader.read(2));
                if (range_offset != 0) {
                    id_range_offset[j] = @as(u32, @intCast(reader.pos())) - 2 + range_offset;
                } else {
                    id_range_offset[j] = 0;
                }
            }

            for (0..segment_count) |j| {
                if (start_code[j] <= char and end_code[j] >= char) {
                    const index = blk: {
                        if (id_range_offset[j] != 0) {
                            const index_offset = id_range_offset[j] + 2 * (char - start_code[j]);
                            reader.seek(index_offset);
                            break :blk convert(&try reader.read(2));

                        } else {
                            break :blk @as(u32, @intCast(id_delta[j] + char));
                        }
                    };

                    return index;
                }
            }

            return error.GlyphNotFound;
        }
    };

    const Cmap12 = struct {
        fn get_indices(reader: Reader, char: u8, allocator: Allocator) !u32 {
            if (convert(&try reader.read(2)) != 0) return error.ReservedPadNotZero;

            const length = convert(&try reader.read(4));
            _ = length;
            const language = convert(&try reader.read(4));
            _ = language;

            const group_count = convert(&try reader.read(4));

            var start_char_code_array = try ArrayList(u32).init(allocator, group_count);
            defer start_char_code_array.deinit();

            var end_char_code_array = try ArrayList(u32).init(allocator, group_count);
            defer end_char_code_array.deinit();

            var start_glyph_code_array = try ArrayList(u32).init(allocator, group_count);
            defer start_glyph_code_array.deinit();

            for (0..group_count) |k| {
                try start_char_code_array.push(convert(&try reader.read(4)));
                try end_char_code_array.push(convert(&try reader.read(4)));
                try start_glyph_code_array.push(convert(&try reader.read(4)));

                if (start_char_code_array.items[k] <= char and end_char_code_array.items[k] >= char) {
                    const index_offset = char - start_char_code_array.items[k];
                    return start_glyph_code_array.items[k] + index_offset;
                }
            }

            // for (0..group_count) |k| {
            //     if (start_char_code_array.items[k] <= chars[i] and end_char_code_array.items[k] >= chars[i]) {
            //         const index_offset = chars[i] - start_char_code_array.items[k];
            //         indices[i] = start_glyph_code_array.items[k] + index_offset;
            //     }
            // }


            // return indices;
            return error.GlyphNotFound;
        }
    };

    const Table = struct {
        name:     [4]u8,
        checksum: u32,
        offset:   u32,
        length:   u32,

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
                if      (std.mem.eql(u8, name[0..], "cmap")) return Table.Type.Map
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
                .name     = try reader.read(4),
                .checksum = convert(&try reader.read(4)),
                .offset   = convert(&try reader.read(4)),
                .length   = convert(&try reader.read(4)),
            };
        }
    };

    pub fn new(file_path: []const u8, allocator: Allocator) !TrueTypeFont {
        const reader = Reader.new(file_path) catch |e| {
            logger.log(.Error, "Failed to get the reader of file: {s}", .{file_path});

            return e;
        };

        var header: Header    = undefined;
        var glyphs_count: u32 = undefined;

        // const count: u32      = @intCast(chars.len);
        // _ = count;
        const scalar_type     = convert(&try reader.read(4));
        const num_tables      = convert(&try reader.read(2));
        const search_range    = convert(&try reader.read(2));
        const entry_selector  = convert(&try reader.read(2));
        const range_shift     = convert(&try reader.read(2));

        // var indices: [chars.len]u32 = undefined;
        var tables = allocator.alloc(Table, @typeInfo(Table.Type).Enum.fields.len) catch |e| {
            logger.log(.Error, "Out of memory", .{});

            return e;
        };

        const pos = reader.pos();

        for (0..num_tables) |k| {
            reader.seek(pos + k * @sizeOf(Table));

            const table = try Table.new(reader);
            const typ   = Table.Type.from_name(&table.name) catch continue;

            tables[@intFromEnum(typ)] = table;

            switch (typ) {
                .Header => {
                    reader.seek(table.offset);
                    header = try Header.new(reader);
                },
                .Max => {
                    reader.seek(table.offset + 4);
                    glyphs_count = convert(&try reader.read(2));
                },
                // .Map => {
                //     reader.seek(table.offset);
                //     const version = convert(&try reader.read(2));
                //     _ = version;
                //     const number_subtables = convert(&try reader.read(2));

                //     const table_pos = reader.pos();
                //     for (0..number_subtables) |i| {
                //         reader.seek(table_pos + 8 * i);

                //         const id = convert(&try reader.read(2));
                //         const specific_id = convert(&try reader.read(2));
                //         const offset = convert(&try reader.read(4));

                //        if (specific_id != 0 and specific_id != 4 and specific_id != 3) continue;
                //         if (id != 0) continue;

                //         reader.seek(table.offset + offset);
                //         const format = convert(&try reader.read(2));

                //         indices = switch (format) {
                //             4    => try Cmap4.get_indices(reader, chars, allocator),
                //             12   => try Cmap12.get_indices(reader, chars, allocator),
                //             else => continue,
                //         };

                //         break;
                //     }
                // },
                else => {}
            }
        }

        // var objects = try allocator.allo(Object, chars.len);
        const glyphs = try ArrayList(Glyph).init(allocator, 1);


        // for (indices, 0..) |k, i| {
        //     const glyph = try Glyph.new(tables, reader, header, size, allocator, k);

        //     objects[i] = .{
        //         .vertex = glyph.vertex,
        //         .index = glyph.index,
        //     };
        //     try glyphs.push(Glyph.new(tables, reader, header, size, allocator, k) catch {
        //         logger.log(.Error, "Wrong glyph bytes content", .{});
        //         continue;
        //     });
        // }

        return .{
            .header         = header,
            .tables         = tables,
            .glyphs         = glyphs,
            .num_tables     = num_tables,
            .scalar_type    = scalar_type,
            .range_shift    = range_shift,
            .search_range   = search_range,
            .entry_selector = entry_selector,
            .allocator      = allocator,
            .path           = file_path,
        };
    }

    pub fn glyph_object(self: *TrueTypeFont, typ: Type) !Object {
        const c = typ.indice();
        const reader = Reader.new(self.path) catch |e| {
            logger.log(.Error, "Failed to get the reader of file: {s}", .{self.path});

            return e;
        };

        const map_table = self.tables[@intFromEnum(Table.Type.Map)];
        reader.seek(map_table.offset);
        const version = convert(&try reader.read(2));
        _ = version;
        const number_subtables = convert(&try reader.read(2));

        const table_pos = reader.pos();
        for (0..number_subtables) |i| {
            reader.seek(table_pos + 8 * i);

            const id = convert(&try reader.read(2));
            const specific_id = convert(&try reader.read(2));
            const offset = convert(&try reader.read(4));

           if (specific_id != 0 and specific_id != 4 and specific_id != 3) continue;
            if (id != 0) continue;

            reader.seek(map_table.offset + offset);
            const format = convert(&try reader.read(2));

            const index = switch (format) {
                4    => try Cmap4.get_indices(reader, c, self.allocator),
                12   => try Cmap12.get_indices(reader, c, self.allocator),
                else => continue,
            };

            const glyph = try Glyph.new(self.tables, reader, self.header, self.allocator, index);
            try self.glyphs.push(glyph);

            return .{
                .vertex = glyph.vertex,
                .index = glyph.index,
            };
        }

        return error.GlyphNotFound;
    }


    fn get_date(slice: [8]u8) u64 {
        var array1: [4]u8 = undefined;
        var array2: [4]u8 = undefined;

        @memcpy(&array1, slice[0..4]);
        @memcpy(&array2, slice[4..8]);

        return @as(u64, @intCast(convert(&array1))) * 0x100000000 + convert(&array2);
    }

    fn convert(slice: []const u8) u32 {
        return switch (slice.len) {
            4 => @as(u32, @intCast(slice[0])) << 24 | @as(u32, @intCast(slice[1])) << 16 | @as(u32, @intCast(slice[2])) << 8 | @as(u32, @intCast(slice[3])),
            2 => @as(u32, @intCast(slice[0])) << 8  | @as(u32, @intCast(slice[1])),
            else => undefined
        };
    }

    pub fn deinit(self: *TrueTypeFont) void {
        // for (0..self.glyphs.items.len) |i| {
        //     self.glyphs.items[i].deinit();
        // }

        self.glyphs.deinit();
        self.allocator.free(self.tables);
    }
};

