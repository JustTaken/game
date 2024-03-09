const std = @import("std");
const core = @import("core");
const TrueTypeFont = core.TrueTypeFont;
const Application = core.Application;
test "TrueType parsing" {
    const font = try TrueTypeFont.new("assets/font.ttf", std.testing.allocator);
    try std.testing.expect(font.glyphs.items.len >= 80);
    font.deinit();
}

test "Application" {
    var app = Application(.Vulkan).new(std.testing.allocator);
    app.run();
}
