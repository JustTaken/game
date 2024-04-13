const std = @import("std");

pub const c = @cImport({
    @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", "");
    @cDefine("VK_NO_PROTOTYPES", "");
    @cInclude("vulkan/vulkan.h");
    @cInclude("xdg-shell.h");
});

const dlopen = std.c.dlopen;
const dlsym = std.c.dlsym;
const dlclose = std.c.dlclose;

const _config = @import("../util/configuration.zig");
const _event = @import("../event/event.zig");

const Emiter = _event.EventSystem.Event.Emiter;

pub fn Platform(comptime compositor: Compositor) type {
    return struct {
        compositor: T,

        const Self = @This();

        pub const Extensions = T.Extensions;
        pub const T = Compositor.get(compositor);

        pub fn init() !Self {
            return .{
                .compositor = try T.init(),
            };
        }

        pub fn commit(self: Self) void {
            self.compositor.commit();
        }

        pub fn update_events(self: Self) !void {
            try self.compositor.update_events();
        }

        pub fn register_click_emiter(self: Self, emiter: *Emiter) void {
            self.compositor.register_click_emiter(emiter);
        }

        pub fn register_mouse_emiter(self: Self, emiter: *Emiter) void {
            self.compositor.register_mouse_emiter(emiter);
        }

        pub fn register_window_resize_emiter(self: Self, emiter: *Emiter) void {
            self.compositor.register_window_resize_emiter(emiter);
        }

        pub fn register_keyboard_emiter(self: Self, emiter: *Emiter) void {
            self.compositor.register_keyboard_emiter(emiter);
        }


        pub fn create_surface(self: Self, instance: c.VkInstance) !c.VkSurfaceKHR {
            return try self.compositor.create_surface(instance);
        }

        pub fn deinit(self: Self) void {
            _ = dlclose(vulkan.?);
            self.compositor.deinit();
        }
    };
}

pub const KeyMap = enum(u8) {
    Esc = 1,
    One = 2,
    Two = 3,
    Three = 4,
    Four = 5,
    Five = 6,
    Xis = 7,
    Seven = 8,
    Eight = 9,
    Nine = 10,
    Zero = 11,
    Minus = 12,
    Equal = 13,
    Backspace = 14,
    Tab = 15,
    Q = 16,
    W = 17,
    E = 18,
    R = 19,
    T = 20,
    Y = 21,
    U = 22,
    I = 23,
    O = 24,
    P = 25,
    Agudo = 26,
    SquareBracketsOpen = 27,
    Enter = 28,
    Control = 29,
    A = 30,
    S = 31,
    D = 32,
    F = 33,
    G = 34,
    H = 35,
    J = 36,
    K = 37,
    L = 38,
    Cecedilha = 39,
    Negation = 40,
    Quote = 41,
    Shift = 42,
    SquareBracketsClose = 43,
    Z = 44,
    X = 45,
    C = 46,
    V = 47,
    B = 48,
    N = 49,
    M = 50,
    Coulum = 51,
    Dot = 52,
    SemiCoulum = 53,
    RShift = 54,
    DontKnow = 55,
    Alt = 56,
    Space = 57,
};

pub const Compositor = enum {
    wayland,

    fn get(comptime compositor: Compositor) type {
        return switch (compositor) {
            .wayland => @import("wayland.zig").Wayland,
        };
    }
};

var vulkan: ?*anyopaque = null;
var GetInstanceProcAddr: vkGetInstanceProcAddr = undefined;

pub fn get_instance_function() !vkCreateInstance {
    if (vulkan) |_| {
    } else {
        vulkan = dlopen("libvulkan.so.1", 1) orelse return error.LibVulkanNotFound;
    }

    return @as(c.PFN_vkCreateInstance, @ptrCast(dlsym(vulkan, "vkCreateInstance"))) orelse return error.vkCreateInstanceNotFound;
}

pub fn get_instance_procaddr() !vkGetInstanceProcAddr {
    GetInstanceProcAddr = @as(c.PFN_vkGetInstanceProcAddr, @ptrCast(dlsym(vulkan, "vkGetInstanceProcAddr"))) orelse return error.FunctionNotFound;
    return GetInstanceProcAddr;
}

pub fn get_device_procaddr(instance: c.VkInstance) !vkGetDeviceProcAddr {
    return @as(c.PFN_vkGetDeviceProcAddr, @ptrCast(GetInstanceProcAddr(instance, "vkGetDeviceProcAddr"))) orelse return error.FunctionNotFound;
}

const vkCreateInstance = *const fn (?*const c.VkInstanceCreateInfo, ?*const c.VkAllocationCallbacks, ?*c.VkInstance) callconv(.C) i32;
const vkGetInstanceProcAddr = *const fn (c.VkInstance, ?[*:0]const u8) callconv(.C) c.PFN_vkVoidFunction;
const vkGetDeviceProcAddr = *const fn (c.VkDevice, ?[*:0]const u8) callconv(.C) c.PFN_vkVoidFunction;
