const std = @import("std");
const _utility = @import("../utility.zig");
const _wrapper = @import("wrapper.zig");

const Glfw = _wrapper.Glfw;
const Vulkan = _wrapper.Vulkan;
const configuration = _utility.Configuration;

pub const Backend = struct {
    // vulkan: Vulkan,
    ptr: *anyopaque,
    draw: *const fn (*anyopaque) anyerror!void,
    shutdown: *const fn (*anyopaque) void,

    pub const Platform = enum {
        Linux,
        Windows,
        MacOs,
    };

    // pub fn new() !Backend {
    //     return .{
    //         .vulkan = try Vulkan.new(),
    //     };
    // }

    // pub fn draw(self: *Backend) !void {
    //     try self.vulkan.draw();
    // }

    // pub fn shutdown(self: *Backend) void {
    //     self.vulkan.shutdown();
    // }

    // pub fn window(self: Backend) *Glfw.Window {
    //     return self.vulkan.window.handle;
    // }
};
