const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;
const Application  = core.Application;
const PngImage        = core.PngImage;

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("assets/font/font.ttf", std.testing.allocator);
    var obj = try font.glyph_object(.a);

    obj.deinit();
    font.deinit();
}

test "Parse : Png" {
    var image = try PngImage.new("assets/image/image.png", std.testing.allocator);
    image.deinit();
}

