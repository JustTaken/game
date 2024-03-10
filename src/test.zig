const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;

test "TrueType parsing" {
    var font = try TrueTypeFont.new("assets/font.ttf", std.testing.allocator);

    font.deinit();
}

// const Application = core.Application;
// test "Application" {
//     var app = Application(.Vulkan).new(std.testing.allocator);
//     app.run();
// }
