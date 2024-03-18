const std = @import("std");
const core = @import("core");

const Application = core.Application;
const Platform = core.Platform;

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = Application(.Wayland, .Vulkan).new(allocator) catch {
        return;
    };
    app.run();
}
