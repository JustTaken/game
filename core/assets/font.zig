const std            = @import("std");

const _io            = @import("../io/io.zig");
const _collections   = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _math          = @import("../math/math.zig");
const _object        = @import("object.zig");

const Vec            = _math.Vec;

const ArrayList      = _collections.ArrayList;
const Allocator      = std.mem.Allocator;
const Reader         = _io.Io.Reader;
const Object         = _object.ObjectHandler.Object;

pub const TrueTypeFont = struct {
    glyphs:    ArrayList(Glyph),
    tables:    []Table,
    map_table: Cmap,
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

        pub fn code(self: Type) u8 {
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
        vertex: ArrayList(Vec),
        index:  ArrayList(u16),
        x_min:  i16,
        y_min:  i16,
        x_max:  i16,
        y_max:  i16,

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

            var contour_ends = try ArrayList(u16).init(allocator, number_of_contours);
            defer contour_ends.deinit();

            var max: u32 = 0;
            for (0..number_of_contours) |_| {
                const contour_end = convert(&try reader.read(2));

                if (contour_end > max) {
                    max = contour_end;
                }

                try contour_ends.push(@intCast(contour_end));
            }

            var flags = try ArrayList(u8).init(allocator, max + 1);

            defer flags.deinit();

            var points = try ArrayList(Point).init(allocator, max + 1);

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

                if (points.items[k].on_curve) {
                    try vertex.push(.{
                        .x = points.items[k].x,
                        .y = points.items[k].y,
                        .z = 0.0,
                    });
                }
            }

            for (1..vertex.items.len - 1) |k| {
                const ii: u16 = @intCast(k);
                try index.push(ii);
                try index.push(0);
                try index.push(ii + 1);
            }

            return .{
                .x_min        = glyph_points[1],
                .y_min        = glyph_points[2],
                .x_max        = glyph_points[3],
                .y_max        = glyph_points[4],
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

    pub const Cmap = struct {
        end_code:        ArrayList(u32),
        start_code:      ArrayList(u32),
        id_delta:        ArrayList(i16),
        glyph_id:        ArrayList(u32),
        format:          u8,

        fn format4(reader: Reader, allocator: Allocator) !Cmap {
            const length        = convert(&try reader.read(2));
            const language      = convert(&try reader.read(2));
            const segment_count = convert(&try reader.read(2)) / 2;

            _ = length;
            _ = language;

            _ = convert(&try reader.read(2));
            _ = convert(&try reader.read(2));
            _ = convert(&try reader.read(2));

            var end_code        = try ArrayList(u32).init(allocator, segment_count);
            var start_code      = try ArrayList(u32).init(allocator, segment_count);
            var id_delta        = try ArrayList(i16).init(allocator, segment_count);
            var glyph_id        = try ArrayList(u32).init(allocator, segment_count);

            for (0..segment_count) |_| { try end_code.push(convert(&try reader.read(2))); }
            if (convert(&try reader.read(2)) != 0) return error.ReservedPadNotZero;
            for (0..segment_count) |_| { try start_code.push(convert(&try reader.read(2))); }
            for (0..segment_count) |_| { try id_delta.push(@bitCast(@as(u16, @intCast(convert(&try reader.read(2)))))); }
            for (0..segment_count) |_| {
                const range_offset = convert(&try reader.read(2));

                if (range_offset != 0) {
                    try glyph_id.push(@as(u32, @intCast(reader.pos())) - 2 + range_offset);
                } else {
                    try glyph_id.push(0);
                }
            }

            return .{
                .format          = 4,
                .start_code      = start_code,
                .end_code        = end_code,
                .id_delta        = id_delta,
                .glyph_id        = glyph_id,
            };
        }

        fn format12(reader: Reader, allocator: Allocator) !Cmap {
            if (convert(&try reader.read(2)) != 0) return error.ReservedPadNotZero;

            const length = convert(&try reader.read(4));
            const language = convert(&try reader.read(4));

            _ = length;
            _ = language;

            const group_count = convert(&try reader.read(4));

            var start_code = try ArrayList(u32).init(allocator, group_count);
            var end_code   = try ArrayList(u32).init(allocator, group_count);
            var glyph_code = try ArrayList(u32).init(allocator, group_count);

            for (0..group_count) |_| {
                try start_code.push(convert(&try reader.read(4)));
                try end_code.push(convert(&try reader.read(4)));
                try glyph_code.push(convert(&try reader.read(4)));
            }

            return .{
                .format     = 12,
                .start_code = start_code,
                .end_code   = end_code,
                .glyph_id   = glyph_code,
                .id_delta   = try ArrayList(i16).init(allocator, 0),
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
                                break :blk convert(&try reader.read(2));
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

        fn new(reader: Reader, allocator: Allocator) !Cmap {
            const format = convert(&try reader.read(2));

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
        const reader = try Reader.new(file_path);

        defer reader.shutdown();

        var header: Header    = undefined;
        var glyphs_count: u32 = undefined;
        var map_table: Cmap   = undefined;

        const scalar_type     = convert(&try reader.read(4));
        const num_tables      = convert(&try reader.read(2));
        const search_range    = convert(&try reader.read(2));
        const entry_selector  = convert(&try reader.read(2));
        const range_shift     = convert(&try reader.read(2));

        var tables = try allocator.alloc(Table, @typeInfo(Table.Type).Enum.fields.len);
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
                .Map => {
                    reader.seek(table.offset);

                    const version = convert(&try reader.read(2));
                    const number_subtables = convert(&try reader.read(2));
                    const table_pos = reader.pos();

                    _ = version;

                    for (0..number_subtables) |i| {
                        reader.seek(table_pos + 8 * i);

                        const id          = convert(&try reader.read(2));
                        const specific_id = convert(&try reader.read(2));
                        const offset      = convert(&try reader.read(4));

                       if (specific_id != 0 and specific_id != 4 and specific_id != 3) continue;
                        if (id != 0) continue;

                        reader.seek(table.offset + offset);
                        map_table = Cmap.new(reader, allocator) catch continue;
                        break;
                    }
                },
                else => {}
            }
        }

        const glyphs = try ArrayList(Glyph).init(allocator, 1);

        return .{
            .header         = header,
            .tables         = tables,
            .map_table      = map_table,
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
        const c = typ.code();
        const reader = try Reader.new(self.path);

        defer reader.shutdown();

        const index = try self.map_table.get_index(reader, c);
        const glyph = try Glyph.new(self.tables, reader, self.header, self.allocator, index);
        try self.glyphs.push(glyph);

        return .{
            .vertex = glyph.vertex,
            .index  = glyph.index,
        };
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
        self.map_table.deinit();
        self.glyphs.deinit();
        self.allocator.free(self.tables);
    }
};
