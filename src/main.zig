const std = @import("std");
const core = @import("core");

const Application = core.Application;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try Application(.wayland, .vulkan).new(allocator);
    try app.run();
}
