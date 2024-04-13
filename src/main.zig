const std = @import("std");
const core = @import("core");

const Application = core.Application;
const Allocator = core.Allocator;
const logger = core.Configuration.logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var allocator = Allocator.new(alloc, logger);

    var app = try Application(.wayland, .vulkan).new(&allocator);
    try app.run();

    allocator.usage();
}
