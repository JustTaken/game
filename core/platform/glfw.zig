const std = @import("std");

const _config = @import("../util/configuration.zig");
const _wayland = @import("wayland.zig");

const _platform = @import("platform.zig");

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Glfw = struct {
    window: c.GLFWwindow,

    // pub const Press = c.GLFW_PRESS;

    // pub const Right = c.GLFW_KEY_RIGHT;
    // pub const Left = c.GLFW_KEY_LEFT;
    // pub const Down = c.GLFW_KEY_DOWN;
    // pub const Up = c.GLFW_KEY_UP;
    // pub const W = c.GLFW_KEY_W;
    // pub const A = c.GLFW_KEY_A;
    // pub const S = c.GLFW_KEY_S;
    // pub const D = c.GLFW_KEY_D;
    // pub const C = c.GLFW_KEY_C;
    // pub const Control = c.GLFW_KEY_LEFT_CONTROL;
    // pub const Space = c.GLFW_KEY_SPACE;

    pub fn init() !Glfw {
        if (c.glfwInit() != c.GLFW_TRUE) {
            logger.log(.Error, "Glfw failed to initialize", .{});

            return error.GlfwInit;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        const window = c.glfwCreateWindow(@intCast(configuration.default_width), @intCast(configuration.default_height), configuration.application_name, c.glfwGetPrimaryMonitor(), null) orelse return error.WindowInit;

        return .{
            .window = window,
        };
    }

    pub fn set_cursor_position(window: ?*c.GLFWwindow, x: f64, y: f64) void {
        c.glfwSetCursorPos(window, x, y);
    }

    pub fn cursor_position_callback(window: *c.GLFWwindow, func: ?*const fn (?*c.GLFWwindow, f64, f64) callconv (.C) void) void {
        c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
        _ = c.glfwSetCursorPosCallback(window, func);
    }

    pub fn destroy_window(window: *c.GLFWwindow) void {
        c.glfwDestroyWindow(window);
    }

    pub fn create_window_surface(instance: c.VkInstance, window: *c.GLFWwindow, callback: ?*c.VkAllocationCallbacks) !c.VkSurfaceKHR {
        var surface: c.VkSurfaceKHR = undefined;
        if (c.glfwCreateWindowSurface(instance, window, callback, &surface) != c.VK_SUCCESS) return error.SurfaceEerror;

        return surface;
    }

    pub fn window_should_close(window: *c.GLFWwindow) bool {
        return c.glfwWindowShouldClose(window) != 0;
    }

    pub fn get_framebuffer_size(window: *c.GLFWwindow) c.VkExtent2D {
        var width: i32 = undefined;
        var height: i32 = undefined;

        c.glfwGetFramebufferSize(window, &width, &height);

        return .{
            .width = @as(u32, @intCast(width)),
            .height = @as(u32, @intCast(height)),
        };
    }

    pub fn get_nanos_per_frame(window: *c.GLFWwindow) !u32 {
        if (c.glfwGetWindowMonitor(window)) |monitor| {
            const video_mode = c.glfwGetVideoMode(monitor);
            const rate: u32 = @intCast(video_mode.*.refreshRate);

            return 1000000000 / rate;
        }

        return error.NotFound;
    }

    pub fn get_required_instance_extensions(allocator: std.mem.Allocator) ![][*:0]const u8 {
        var count: u32 = undefined;
        const extensions_c = c.glfwGetRequiredInstanceExtensions(&count);
        const extensions = try allocator.alloc([*:0]const u8, count);

        for (0..count) |i| {
            extensions[i] = extensions_c[i];
        }

        return extensions;
    }

    pub fn wait_events() void {
        c.glfwWaitEvents();
    }

    pub fn get_key(window: *c.GLFWwindow, key: i32) i32 {
        return c.glfwGetKey(window, key);
    }

    pub fn get_time() f64 {
        return c.glfwGetTime();
    }

    pub fn poll_events() void {
        c.glfwPollEvents();
    }

    pub fn shutdown() void {
        c.glfwTerminate();
    }
};
