const std = @import("std");

const _config = @import("../util/configuration.zig");

pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("GLFW/glfw3.h");
});

const logger = _config.Configuration.logger;

pub const Platform = struct {
    pub const Window = c.GLFWwindow;

    pub const Press = c.GLFW_PRESS;
    pub const KeyF = c.GLFW_KEY_F;

    pub fn init() !void {
        if (c.glfwInit() != c.GLFW_TRUE) {
            logger.log(.Error, "Glfw failed to initialize", .{});

            return error.GlfwInit;
        }

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            logger.log(.Error, "Vulkan lib not found", .{});

            return error.VulkanInit;
        }
    }

    pub fn create_window(width: u32, height: u32, name: [*c]const u8) !*Window {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        return c.glfwCreateWindow(@intCast(width), @intCast(height), name, null, null) orelse error.WindowInit;
    }

    pub fn destroy_window(window: *Window) void {
        c.glfwDestroyWindow(window);
    }

    pub fn create_window_surface(instance: c.VkInstance, window: *Window, callback: ?*c.VkAllocationCallbacks) !c.VkSurfaceKHR {
        var surface: c.VkSurfaceKHR = undefined;
        if (c.glfwCreateWindowSurface(instance, window, callback, &surface) != c.VK_SUCCESS) return error.lksjdafklj;

        return surface;
    }

    pub fn window_should_close(window: *Window) bool {
        return c.glfwWindowShouldClose(window) != 0;
    }

    pub fn get_framebuffer_size(window: *Window) c.VkExtent2D {
        var width: i32 = undefined;
        var height: i32 = undefined;

        c.glfwGetFramebufferSize(window, &width, &height);

        return .{
            .width = @as(u32, @intCast(width)),
            .height = @as(u32, @intCast(height)),
        };
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

    pub fn get_key(window: *Window, key: i32) i32 {
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
