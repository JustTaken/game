const std = @import("std");

const _io = @import("../io/io.zig");
const _collections = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _math = @import("../math/math.zig");
const _object = @import("object.zig");

const Vec = _math.Vec;

const ArrayList = _collections.ArrayList;
const Allocator = std.mem.Allocator;
const Reader = _io.Io.Reader;
const Object = _object.ObjectHandler.Object;

pub const FontManager = struct {
    texture: []const u8,
    glyphs: [@typeInfo(Type).Enum.fields.len]Glyph,

    width: u32,
    height: u32,

    allocator: Allocator,

    const Glyph = struct {
        texture_coords: [4][2]f32,
        vertex: [4][3]f32,
        index: [6]u16,
    };

    pub fn new(glyphs: ArrayList(TrueTypeFont.Glyph), allocator: Allocator) !FontManager {
        var objects: [@typeInfo(Type).Enum.fields.len]Glyph = undefined;

        for (glyphs.items) |glyph| {
            objects[@intFromEnum(glyph.code_point)] = .{
                .texture_coords = glyph.texture_coords,
                .vertex = glyph.vertex,
                .index = glyph.index,
            };
        }

        return .{
            .texture = glyphs.items[0].texture,
            .width = glyphs.items[0].width,
            .height = glyphs.items[0].height,
            .glyphs = objects,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FontManager) void {
        self.allocator.free(self.texture);
    }
};

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

pub const TrueTypeFont = struct {
    glyphs: ArrayList(Glyph),
    tables: []Table,
    map_table: Cmap,
    header: Header,
    allocator: Allocator,
    path: []const u8,

    num_tables: u32,
    scalar_type: u32,
    range_shift: u32,
    search_range: u32,
    entry_selector: u32,

    const Glyph = struct {
        texture: []const u8,
        texture_coords: [4][2]f32,
        vertex: [4][3]f32,
        index: [6]u16,
        allocator: Allocator,
        width: u32,
        height: u32,
        code_point: Type,

        const Point = struct {
            x: i16 = 0,
            y: i16 = 0,
            on_curve: bool,
        };

        fn simple(glyph_points: [5]i16, reader: Reader, allocator: Allocator, code_point: Type) !Glyph {
            const number_of_contours: u32 = @intCast(glyph_points[0]);
            if (number_of_contours == 0) return error.NoCountour;

            const on_curve: u8 = 0x01;
            const x_is_byte: u8 = 0x02;
            const y_is_byte: u8 = 0x04;
            const repeat: u8 = 0x08;
            const x_delta: u8 = 0x10;
            const y_delta: u8 = 0x20;

            var contour_ends = try ArrayList(u16).init(allocator, number_of_contours);
            defer contour_ends.deinit();

            var max: u32 = 0;
            for (0..number_of_contours) |_| {
                const contour_end = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

                if (contour_end > max) {
                    max = contour_end;
                }

                try contour_ends.push(@intCast(contour_end));
            }

            var flags = try ArrayList(u8).init(allocator, max + 1);
            defer flags.deinit();

            var points = try ArrayList(Point).init(allocator, max + 1);
            defer points.deinit();

            const off = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
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

            const index: [6]u16 = .{0, 1, 2, 2, 1, 3};
            const texture_coords: [4][2]f32 = .{
                .{0, 0},
                .{1, 0},
                .{0, 1},
                .{1, 1},
            };
            const vertex: [4][3]f32 = .{
                .{-1, 1, 0},
                .{1, 1, 0},
                .{-1, -1, 0},
                .{1, -1, 0},
            };

            var values: [2]i16 = .{ 0, 0 };
            for (0..max + 1) |k| {
                points.items[k].x = blk: {
                    if (flags.items[k] & x_is_byte != 0) {
                        const v = (try reader.read(1))[0];

                        if (flags.items[k] & x_delta != 0) values[0] += v
                        else values[0] -= v;
                    } else if (~flags.items[k] & x_delta != 0) {
                        values[0] += @bitCast(@as(u16, @intCast(@byteSwap(@as(u16, @bitCast(try reader.read(2)))))));
                    }

                    break :blk values[0];
                };
            }

            for (0..max + 1) |k| {
                points.items[k].y = blk: {
                    if (flags.items[k] & y_is_byte != 0) {
                        const v = (try reader.read(1))[0];

                        if (flags.items[k] & y_delta != 0) values[1] += v
                        else values[1] -= v;
                    } else if (~flags.items[k] & y_delta != 0) {
                        values[1] += @bitCast(@as(u16, @intCast(@byteSwap(@as(u16, @bitCast(try reader.read(2)))))));
                    }

                    break :blk values[1];
                };

            }

            const width: u32 = @intCast(glyph_points[3] - glyph_points[1]);
            const height: u32 = @intCast(glyph_points[4] - glyph_points[2]);

            const texture = try allocator.alloc(u8, (width + 1) * (height + 1));
            @memset(texture, 0);

            for (0..points.items.len - 1) |p| {
                if (!points.items[p].on_curve) continue;
                const xp: u32 = @intCast(points.items[p].x - glyph_points[1]);
                const yp: u32 = @intCast(points.items[p].y - glyph_points[2]);
                @memset(texture[(xp + yp * width)..(xp + yp * width + 1)], 255);

                // const x0 = points.items[p].x - glyph_points[1];
                // const x1 = points.items[p + 1].x - glyph_points[1];
                // const y0 = points.items[p].y - glyph_points[2];
                // const y1 = points.items[p + 1].y - glyph_points[2];

                // const dx = x1 - x0;
                // const m = @as(f32, @floatFromInt(y1 - y0)) / @as(f32, @floatFromInt(dx));
                // const negative = dx < 0;

                // for (0..@intCast(if (negative) - dx else dx)) |k| {
                // const x: u32 = @intCast(x0 + if (negative) - @as(i16, @intCast(k)) else @as(i16, @intCast(k)));
                // const y: u32 = @intCast(y0 + @as(i16, @intFromFloat(@floor(m * @as(f32, @floatFromInt(if (negative) - @as(i16, @intCast(k)) else @as(i16, @intCast(k))))))));

                // @memset(texture[x + y * width..x + (y * width + 1)], 255);
                // }
            }

            // const line_size = width * 4;

            // for (0..height + 1) |ii| {
            // var filling = false;
            // const line_pos = ii * line_size;

            // for (0..width + 1) |jj| {
            // const coloumn_pos = jj + line_pos;

            // if (texture[coloumn_pos] == 255) {
            // filling = !filling;
            // continue;
            // }

            // if (filling) texture[coloumn_pos] = 255;
            // }
            // }

            return .{
                .width = width,
                .height = height,
                .vertex = vertex,
                .index = index,
                .texture = texture,
                .texture_coords = texture_coords,
                .allocator = allocator,
                .code_point = code_point,
            };
        }

        fn new(tables: []const Table, reader: Reader, header: Header, allocator: Allocator, index: usize, code_point: Type) !Glyph {
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

            const number_of_contours = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const x_min = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const y_min = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const x_max = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const y_max = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

            const points: [5]i16 = .{
                @bitCast(@as(u16, @intCast(number_of_contours))),
                @bitCast(@as(u16, @intCast(x_min))),
                @bitCast(@as(u16, @intCast(y_min))),
                @bitCast(@as(u16, @intCast(x_max))),
                @bitCast(@as(u16, @intCast(y_max))),
            };

            if (points[0] < 0) {
                return error.CouldNotInitializeGlyph;
            } else {
                return try simple(points, reader, allocator, code_point);
            }
        }
    };

    const Header = struct {
        xMin: i16,
        yMin: i16,
        xMax: i16,
        yMax: i16,
        flags: u32,
        version: i32,
        created: u64,
        modified: u64,
        mac_style: u32,
        units_pem: u32,
        magic_number: u32,
        font_revision: i32,
        lowest_rec_ppem: u32,
        glyph_data_format: i16,
        font_direction_hint: i16,
        index_to_loc_format: i16,
        checksum_adjustment: u32,

        fn new(reader: Reader) !Header {
            const version = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const font_revision = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const checksum_adjustment = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const magic_number = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
            const flags = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const units_pem = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
            const created = get_date(try reader.read(8));
            const modified = get_date(try reader.read(8));
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

        fn format4(reader: Reader, allocator: Allocator) !Cmap {
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

        fn format12(reader: Reader, allocator: Allocator) !Cmap {
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

        fn new(reader: Reader, allocator: Allocator) !Cmap {
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

    pub fn new(file_path: []const u8, allocator: Allocator) !TrueTypeFont {
        const reader = try Reader.new(file_path);
        defer reader.shutdown();

        var header: Header = undefined;
        var glyphs_count: u32 = undefined;
        var map_table: Cmap = undefined;

        const scalar_type = @byteSwap(@as(u32, @bitCast(try reader.read(4))));
        const num_tables = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
        const search_range = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
        const entry_selector = @byteSwap(@as(u16, @bitCast(try reader.read(2))));
        const range_shift = @byteSwap(@as(u16, @bitCast(try reader.read(2))));

        var tables = try allocator.alloc(Table, @typeInfo(Table.Type).Enum.fields.len);
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
                        map_table = Cmap.new(reader, allocator) catch |e| {
                            std.debug.print("No good: {}\n", .{e});
                            continue;
                        };

                        break;
                    }
                },
                else => {}
            }
        }

        const glyphs = try ArrayList(Glyph).init(allocator, 1);

        return .{
            .header = header,
            .tables = tables,
            .map_table = map_table,
            .glyphs = glyphs,
            .num_tables = num_tables,
            .scalar_type = scalar_type,
            .range_shift = range_shift,
            .search_range = search_range,
            .entry_selector = entry_selector,
            .allocator = allocator,
            .path = file_path,
        };
    }

    // pub fn glyph_object(self: *TrueTypeFont, typ: Type) !Object {
    // const c = typ.code();
    // const reader = try Reader.new(self.path);

    // defer reader.shutdown();

    // const index = try self.map_table.get_index(reader, c);
    // const glyph = try Glyph.new(self.tables, reader, self.header, self.allocator, index);

    // try self.glyphs.push(glyph);

    // var texture = try ArrayList([2]f32).init(self.allocator, 6);
    // texture.items.len = 6;

    // @memset(texture.items, .{0, 0});

    // return .{
    // .vertex = try ArrayList([3]f32).init(self.allocator, 0),
    // .index = try ArrayList(u16).init(self.allocator, 0),
    // .texture = texture
    // };
    // }

    pub fn add_glyph(self: *TrueTypeFont, typ: Type) !void {
        const reader = try Reader.new(self.path);
        defer reader.shutdown();

        const index = try self.map_table.get_index(reader, typ.code());
        const glyph = try Glyph.new(self.tables, reader, self.header, self.allocator, index, typ);

        try self.glyphs.push(glyph);
    }

    pub fn font_manager(self: *TrueTypeFont) !FontManager {
        const manager = FontManager.new(self.glyphs, self.allocator);

        self.glyphs.deinit();
        self.map_table.deinit();
        self.allocator.free(self.tables);

        return manager;
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
            2 => @as(u32, @intCast(slice[0])) << 8 | @as(u32, @intCast(slice[1])),
            else => undefined
        };
    }
};
