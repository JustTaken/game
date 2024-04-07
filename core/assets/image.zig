const std = @import("std");
const _io = @import("../io/io.zig");

const c   = @cImport({
    @cInclude("zlib.h");
});

// extern fn stbi_load([*c]const u8, *i32, *i32, *i32, i32) callconv(.C) [*]u8;
// extern fn stbi_image_free(*anyopaque) callconv(.C) void;

const Allocator = std.mem.Allocator;
const Reader = _io.Io.Reader;

const Chunk = struct {
    length: u32,
    @"type": [4]u8,
    data: []const u8,
    crc: [4]u8,
};

fn abs(int: i16) u16 {
    if (int < 0) return @intCast(-int);
    return @intCast(int);
}

pub const PngImage = struct {
    width: u32,
    height: u32,
    // bit_depth: u8,
    // colour_type: u8,
    // compression_method: u8,
    // filter_method: u8,
    // interlace_method: u8,
    // allocator: Allocator,
    pixels: []const u8,
    allocator: Allocator,

    // pub fn old(path: []const u8, allocator: Allocator) !PngImage {
    //     var x: i32 = undefined;
    //     var y: i32 = undefined;
    //     var n: i32 = undefined;

    //     const stbi_pixels = stbi_load(@ptrCast(path), &x, &y, &n, 4);
    //     const pixels = try allocator.alloc(u8, @intCast(x * y * 4));
    //     var image = try old(path, allocator);
    //     defer image.deinit();

    //     @memcpy(pixels, stbi_pixels);

    //     defer stbi_image_free(stbi_pixels);


    //     return .{
    //         .pixels = pixels,
    //         .allocator = allocator,
    //         .width = @intCast(x),
    //         .height = @intCast(y),
    //     };
    // }

    pub fn deinit(self: *PngImage) void {
        self.allocator.free(self.pixels);
    }

    pub fn new(path: []const u8, allocator: Allocator) !PngImage {
        // const stdout = std.io.getStdOut().writer();
        const reader = try Reader.new(path);
        const magic_number = try reader.read(8);
        var bit_depth: u8 = undefined;
        var colour_type: u8 = undefined;
        var compression_method: u8 = undefined;
        var filter_method: u8 = undefined;
        var interlace_method: u8 = undefined;

        if (!std.mem.eql(u8, &magic_number, &.{ 0x89, 0x50, 0x4e, 0x47, 0xd, 0xa, 0x1a, 0xa })) return error.NotPngFile;

        var image: PngImage = undefined;
        var idat: []u8 = try allocator.alloc(u8, 0);
        defer allocator.free(idat);

        var idat_len: u32 = 0;
        var length: [4]u8 = undefined;

        while (try reader.file.read(&length) == 4) {
            const len: u32 = @byteSwap(@as(u32, @bitCast(length)));

            const chunk = Chunk {
                .length = len,
                .type = try reader.read(4),
                .data = try reader.read_alloc(len, allocator),
                .crc = try reader.read(4),
            };

            if (std.mem.eql(u8, &chunk.type, "IHDR")) {
                bit_depth = @bitCast(chunk.data[8..9].*);
                colour_type = @bitCast(chunk.data[9..10].*);
                compression_method = @bitCast(chunk.data[10..11].*);
                filter_method = @bitCast(chunk.data[11..12].*);
                interlace_method = @bitCast(chunk.data[12..13].*);

                image = .{
                    .width = @byteSwap(@as(u32, @bitCast(chunk.data[0..4].*))),
                    .height = @byteSwap(@as(u32, @bitCast(chunk.data[4..8].*))),
                    .allocator = allocator,
                    .pixels = undefined,
                };

                if (bit_depth != 8) return error.BitDepthNotSupported;
                if (colour_type != 6) return error.ColourTypeNotSupported;
                if (compression_method != 0) return error.CompressionMethodNotSupported;
                if (filter_method != 0) return error.FilterMethodNotSupported;
                if (interlace_method != 0) return error.InterlaceMethodNotSupported;

            } else if (std.mem.eql(u8, &chunk.type, "IDAT")) {
                idat = try allocator.realloc(idat, idat_len + len);
                @memcpy(idat[idat_len..len + idat_len], chunk.data);
                idat_len += len;
            }

            allocator.free(chunk.data);
        }

        var pixels = try allocator.alloc(u8, image.width * image.height * 4);
        var odat: []u8 = try allocator.alloc(u8, idat_len);
        defer allocator.free(odat);

        var stream = c.z_stream {
            .zalloc = null,
            .zfree = null,
            .next_in = idat.ptr,
            .avail_in = @intCast(idat.len),
            .next_out = odat.ptr,
            .avail_out = @intCast(odat.len),
        };

        if (c.inflateInit(&stream) != c.Z_OK) return error.NotOk;
        while (c.inflate(&stream, c.Z_SYNC_FLUSH) == c.Z_OK and stream.avail_in > 0) {
            const old_len = odat.len;
            odat = try allocator.realloc(odat, old_len + idat_len);
            stream.avail_out = @intCast(idat.len);
            stream.next_out = &odat[old_len..][0];
        }

        const scanline_len = image.width * 4 + 1;
        const content = try allocator.alloc(u8, image.width * 4);
        defer allocator.free(content);

        for (0..image.height) |i| {
            const line = odat[(scanline_len*i)..scanline_len*(i + 1)];

            const filter = line[0];
            switch (filter) {
                0 => {
                    @memcpy(content, line[1..]);
                },
                1 => {
                    var prev_rgba: [4]u8 = .{0, 0, 0, 0};

                    for (0..image.width) |k| {
                        const new_array = [4]u8 {
                            @intCast((@as(u16, @intCast(line[k*4 + 1])) + @as(u16, @intCast(prev_rgba[0]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 2])) + @as(u16, @intCast(prev_rgba[1]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 3])) + @as(u16, @intCast(prev_rgba[2]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 4])) + @as(u16, @intCast(prev_rgba[3]))) % 256),
                        };

                        prev_rgba = new_array;
                        @memcpy(content[k*4..(k+1)*4], &new_array);
                    }
                },
                2 => {
                    const prev_line: []const u8 = pixels[image.width*4*(i - 1)..image.width*i];

                    for (0..image.width) |k| {
                        const new_array = [4]u8 {
                            @intCast((@as(u16, @intCast(line[k*4 + 1])) + @as(u16, @intCast(prev_line[k*4 + 0]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 2])) + @as(u16, @intCast(prev_line[k*4 + 1]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 3])) + @as(u16, @intCast(prev_line[k*4 + 2]))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 4])) + @as(u16, @intCast(prev_line[k*4 + 3]))) % 256),
                        };

                        @memcpy(content[k*4..(k+1)*4], &new_array);
                    }

                },
                3 => {
                    const prev_line: []const u8 = pixels[image.width*4*(i - 1)..image.width*4*i];
                    var prev_rgba: [4]u8 = .{0, 0, 0, 0};

                    for (0..image.width) |k| {
                        const new_array = [4]u8 {
                            @intCast((@as(u16, @intCast(line[k*4 + 1])) + @as(u16, @intFromFloat(@floor((@as(f32, @floatFromInt(prev_rgba[0])) + @as(f32, @floatFromInt(prev_line[k*4 + 0]))) / 2)))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 2])) + @as(u16, @intFromFloat(@floor((@as(f32, @floatFromInt(prev_rgba[1])) + @as(f32, @floatFromInt(prev_line[k*4 + 1]))) / 2)))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 3])) + @as(u16, @intFromFloat(@floor((@as(f32, @floatFromInt(prev_rgba[2])) + @as(f32, @floatFromInt(prev_line[k*4 + 2]))) / 2)))) % 256),
                            @intCast((@as(u16, @intCast(line[k*4 + 4])) + @as(u16, @intFromFloat(@floor((@as(f32, @floatFromInt(prev_rgba[3])) + @as(f32, @floatFromInt(prev_line[k*4 + 3]))) / 2)))) % 256),
                        };

                        prev_rgba = new_array;
                        @memcpy(content[k*4..(k+1)*4], &new_array);
                    }
                },
                4 => {
                    const prev_line: []const u8 = pixels[image.width*4*(i - 1)..image.width*4*i];
                    var prev_rgba: [4]u8 = .{0, 0, 0, 0};

                    for (0..image.width) |k| {
                        var new_array: [4]u8 = undefined;
                        const upper_left_pixel: []const u8 = if (k == 0) &.{0, 0, 0, 0} else prev_line[(k - 1)*4..k*4];

                        for (0..4) |j| {
                            const p = @as(i16, @intCast(prev_rgba[j])) + @as(i16, @intCast(prev_line[k*4 + j])) - @as(i16, @intCast(upper_left_pixel[j]));
                            const pa = abs(p - prev_rgba[j]);
                            const pb = abs(p - prev_line[k*4 + j]);
                            const pc = abs(p - upper_left_pixel[j]);

                            if (pa <= pb and pa <= pc) new_array[j] = @intCast((@as(u16, @intCast(line[k*4 + 1 + j])) + @as(u16, @intCast(prev_rgba[j]))) % 256)
                            else if (pb <= pc) new_array[j] = @intCast((@as(u16, @intCast(line[k*4 + 1 + j])) + @as(u16, @intCast(prev_line[k*4 + j]))) % 256)
                            else new_array[j] = @intCast((@as(u16, @intCast(line[k*4 + 1 + j])) + @as(u16, @intCast(upper_left_pixel[j]))) % 256);
                        }

                        prev_rgba = new_array;
                        @memcpy(content[k*4..(k+1)*4], &new_array);
                    }
                    // std.debug.print("stb {d}\n", .{o_image.pixels[image.width*4*i..image.width*4*i + 1000]});
                    // std.debug.print("mine {d}\n", .{content[0..1000]});
                },
                else => {
                    @memset(content, 0);

                    for (0..image.width) |k| {
                        content[k + 3] = 255;
                    }

                }
            }

            // try stdout.print("{d} {d}\n", .{filter, content});
            @memcpy(pixels[image.width*4*i..image.width*4*(i + 1)], content);
        }

        image.pixels = pixels;
        return image;
    }
};

