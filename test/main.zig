const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;
const Platform = core.Platform;

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("assets/font/font.ttf", std.testing.allocator);
    font.deinit();
}

// test "Compositor : Platform" {
//     const platform = try Platform(.Wayland).init();
//     platform.deinit();
// }

