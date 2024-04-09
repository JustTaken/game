const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;
const Application  = core.Application;
const PngImage        = core.PngImage;

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("assets/font/font.ttf", std.testing.allocator);
    try font.add_glyph(.a);

    font.deinit();
}

// test "Parse : Png" {
//     var image = try PngImage.new("assets/image/image2.png", std.testing.allocator);
//     std.debug.print("{d}\n", .{image.pixels[100..1000]});
//     image.deinit();
// }

