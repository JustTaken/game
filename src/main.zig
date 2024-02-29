const std = @import("std");
const core = @import("core");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Application = core.Application;
const Renderer = core.Renderer;
const TrueTypeFont = core.TrueTypeFont;

pub fn main() void {
    var app = Application(Renderer.Vulkan).new();
    app.run();
}
