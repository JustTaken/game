// const std = @import("std");
const core = @import("core");

// const TrueTypeFont = core.TrueTypeFont;
const Platform = core.Platform;
pub const c = @cImport({
    // @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", "");
    // @cDefine("VK_NO_PROTOTYPES", "");
    // @cInclude("vulkan/vulkan.h");
    // @cInclude("GLFW/glfw3.h");
    // @cInclude("wayland-client.h");
    // @cInclude("xdg-shell/xdg-shell.h");
    // @cInclude("xdg-shell.c");
    @cInclude("dlfcn.h");
});

// test "Parse : TrueTypeFont" {
//     var font = try TrueTypeFont.new("assets/font.ttf", std.testing.allocator);

//     font.deinit();
// }

test "Compositor : PLatform" {
    const platform = try Platform(.Wayland).init();
    platform.deinit();
}

// test "Compositor : Wayland" {
    // _ = c.dlopen("libwayland-client.so", c.RTLD_LAZY) orelse return error.LibWaylandNotFound;
// }

// test "Compositor : xdg-shell" {
    // _ = c.dlopen("xdg-shell.so", c.RTLD_LAZY) orelse return error.LibXdgShellNotFound;
// }

// test "Compositor : Vulkan" {
//     _ = c.dlopen("libvulkan.so.1", c.RTLD_LAZY) orelse return error.LibVulkanNotFound;
// }
