const std = @import("std");
const _config = @import("../util/configuration.zig");
const _wrapper = @import("wrapper.zig");

const Glfw = _wrapper.Glfw;
const Vulkan = _wrapper.Vulkan;
const configuration = _config.Configuration;

pub const Backend = struct {
    vulkan: Vulkan,

    pub fn new() !Backend {
        const vulkan = Vulkan.new() catch |e| {
            configuration.logger.log(.Error, "Failed to creat vulkan instance", .{});

            return e;
        };

        return .{
            .vulkan = vulkan,
        };
    }

    pub fn draw(self: *Backend) !void {
        try self.vulkan.draw();
    }

    pub fn shutdown(self: *Backend) void {
        self.vulkan.shutdown();
    }

    pub fn get_window(self: Backend) *Glfw.Window {
        return self.vulkan.window.handle;
    }
};
