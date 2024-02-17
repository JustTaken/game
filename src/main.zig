const std = @import("std");
const core = @import("core");

const Application = core.Application;
const logger = Application.logger;
const Obj = core.Obj;
const HashSet = core.HashSet;
const Vec = core.Vec;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub fn main() void {
    logger.log(.Info, "Initilizing application", .{});
    defer logger.log(.Info, "Shutting down application", .{});

    var app = Application.new();
    app.run();
}
