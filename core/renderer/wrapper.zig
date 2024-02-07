const _utility = @import("../utility.zig");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});

const configuration = _utility.Configuration;

pub const Glfw = struct {
    const Window = *c.GLFWwindow;

    pub fn init() !void {
        if (c.glfwInit() != c.GLFW_TRUE) {
            configuration.logger.log(.Error, "Glfw failed to initialize", .{});
            return error.GlfwInit;
        }

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            configuration.logger.log(.Error, "Vulkan lib not found", .{});
            return error.VulkanInit;
        }
    }

    pub fn create_window(width: u32, height: u32, name: [*c]const u8) !Window {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        return c.glfwCreateWindow(@intCast(width), @intCast(height), name, null, null) orelse error.WindowInit;
    }
};
