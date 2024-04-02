const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;
const Application = core.Application;

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("test/stocky.ttf", std.testing.allocator);
    var obj = try font.glyph_object(.a);
    defer {
        obj.deinit();
        font.deinit();
    }
}

// test "Application" {
//     var application = try Application(.wayland, .vulkan).new(std.testing.allocator);
//     application.run();
// }

// test "Compositor : Platform" {
//     const platform = try Platform(.Wayland).init();
//     platform.deinit();
// }
