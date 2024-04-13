const std = @import("std");
const core = @import("core");

const TrueTypeFont = core.TrueTypeFont;
const Application = core.Application;
const PngImage = core.PngImage;
const ArrayList = core.ArrayList;
const Allocator = core.Allocator;
const logger = core.Configuration.logger;

test "Allocator : Alloc" {
    var allocator = Allocator.new(std.testing.allocator, logger);
    const allocation_test = try allocator.alloc(u8, 10);

    allocator.free(allocation_test);
}

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("assets/font/font.ttf", 16, std.testing.allocator);
    font.deinit();
}

test "Parse : Png" {
    var image = try PngImage.new("assets/image/image2.png", std.testing.allocator);
    std.debug.print("{d}\n", .{image.pixels[100..1000]});
    image.deinit();
}

// test "Application" {
//     var allocator = Allocator.new(std.testing.allocator, logger);

//     var app = try Application(.wayland, .vulkan).new(&allocator);
//     try app.run();
// }

