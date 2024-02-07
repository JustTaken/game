const std = @import("std");
const core = @import("core");

const Application = core.Application;
const logger = Application.logger;

pub fn main() void {
    logger.log(.Info, "Initilizing application", .{});
    defer logger.log(.Info, "Shutting down application", .{});

    var app = Application.new();
    app.run();
}
