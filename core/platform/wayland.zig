const std                         = @import("std");
const _platform                   = @import("platform.zig");
const _event                      = @import("../event/event.zig");
const _configuration              = @import("../util/configuration.zig");

const configuration               = _configuration.Configuration;

const c                           = _platform.c;
const Platform                    = _platform.Platform;
const Emiter                      = _event.EventSystem.Event.Emiter;

const WlDisplay                   = c.wl_display;
const WlSurface                   = c.wl_surface;
const WlRegistry                  = c.wl_registry;
const WlCompositor                = c.wl_compositor;
const WlKeyboard                  = c.wl_keyboard;
const WlPointer                   = c.wl_pointer;
const WlArray                     = c.wl_array;
const WlSeat                      = c.wl_seat;

const XdgSurface                  = c.xdg_surface;
const XdgWmBase                   = c.xdg_wm_base;
const XdgTopLevel                 = c.xdg_toplevel;

var compositor: *WlCompositor     = undefined;
var shell: *XdgWmBase             = undefined;
var seat: *WlSeat                 = undefined;
var keyboard: *WlKeyboard         = undefined;
var pointer: *WlPointer           = undefined;

var resize: bool                  = false;
var running: bool                 = false;

var keyboard_emiter_len: u32      = 0;
var keyboard_emiter: *Emiter      = undefined;
var click_emiter: *Emiter         = undefined;
var mouse_emiter: *Emiter         = undefined;
var mouse_position: [2]i32        = .{ 0, 0 };
var window_resize_emiter: *Emiter = undefined;

pub const Wayland = struct {
    xdg:        Xdg,
    display:    Display,
    registry:   Registry,
    surface:    Surface,
    compositor: Compositor,

    pub const Extensions = &[_] [*:0]const u8 {
        "VK_KHR_surface",
        "VK_KHR_wayland_surface"
    };

    pub const Seat = struct {
        keyboard: *WlKeyboard,
        pointer:  *WlPointer,

        const listener: c.wl_seat_listener = .{
            .capabilities = capabilities,
            .name = name,
        };

        pub const Pointer = struct {
            const listener = c.wl_pointer_listener {
                .enter  = enter,
                .leave  = leave,
                .motion = motion,
                .button = button,
                .axis   = axis,
            };

            fn enter(data: ?*anyopaque, pt: ?*WlPointer,  serial: u32, surf: ?*WlSurface, x: i32, y: i32) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = serial;
                _ = surf;
                _ = x;
                _ = y;
            }

            fn leave(data: ?*anyopaque, pt: ?*WlPointer, serial: u32, surf: ?*WlSurface) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = serial;
                _ = surf;
            }

            fn motion(data: ?*anyopaque, pt: ?*WlPointer, time: u32, x: i32, y: i32) callconv(.C) void {
                mouse_emiter.value.i32 = .{ x - mouse_position[0], y - mouse_position[1] };
                mouse_emiter.changed = true;
                mouse_position = .{ x, y };

                _ = data;
                _ = pt;
                _ = time;
            }

            fn button(data: ?*anyopaque, pt: ?*WlPointer, serial: u32, time: u32, bt: u32, state: u32) callconv(.C) void {
                if (bt == 272) {
                    if (state == 1) click_emiter.value.u32[0] = 1
                    else click_emiter.value.u32[0] = 0;

                    click_emiter.changed = true;
                } else if (bt == 273) {
                    if (state == 1) click_emiter.value.u32[1] = 1
                    else click_emiter.value.u32[1] = 0;

                    click_emiter.changed = true;
                }

                _ = data;
                _ = pt;
                _ = serial;
                _ = time;

            }

            fn axis(data: ?*anyopaque, pt: ?*WlPointer, time: u32, ax: u32, value: i32) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = time;
                _ = ax;
                _ = value;
            }

            fn frame(data: ?*anyopaque, pt: ?*WlPointer) callconv(.C) void {
                _ = data;
                _ = pt;
            }

            fn axis_source(data: ?*anyopaque, pt: ?*WlPointer, ax_src: u32) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = ax_src;
            }

            fn axis_stop(data: ?*anyopaque, pt: ?*WlPointer, time: u32, ax: u32) callconv(.C) void {
                _ = ax;
                _ = data;
                _ = pt;
                _ = time;
            }

            fn axis_discrete(data: ?*anyopaque, pt: ?*WlPointer, ax: u32, discrete: i32 ) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = ax;
                _ = discrete;
            }

            fn axis_value120(data: ?*anyopaque, pt: ?*WlPointer, ax: u32, value120: i32 ) callconv(.C) void {
                _ = data;
                _ = pt;
                _ = ax;
                _ = value120;
            }

            fn axis_relative_direction(data: ?*anyopaque, pt: ?*WlPointer, ax: u32, direction: u32) callconv(.C) void {
                _ = direction;
                _ = data;
                _ = pt;
                _ = ax;
            }
        };

        pub const Keyboard = struct {
            const listener = c.wl_keyboard_listener {
                .keymap      = map,
                .enter       = enter,
                .leave       = leave,
                .key         = key,
                .modifiers   = modifiers,
                .repeat_info = repeat_info,
            };

            fn map(data: ?*anyopaque, kb: ?*WlKeyboard, format: u32, fd: i32, size: u32) callconv(.C) void {
                _ = data;
                _ = kb;
                _ = fd;
                _ = size;
                _ = format;
            }

            fn enter(data: ?*anyopaque, kb: ?*WlKeyboard, serial: u32, s: ?*WlSurface, ks: ?*WlArray) callconv(.C) void {
                _ = data;
                _ = kb;
                _ = serial;
                _ = s;
                _ = ks;
            }

            fn leave(data: ?*anyopaque, kb: ?*WlKeyboard, serial: u32, s: ?*WlSurface) callconv(.C) void {
                _ = data;
                _ = kb;
                _ = serial;
                _ = s;
            }

            fn key(data: ?*anyopaque, kb: ?*WlKeyboard, serial: u32, time: u32, k: u32, state: u32) callconv(.C) void {
                _ = data;
                _ = kb;
                _ = serial;
                _ = time;

                if (state == 1) {
                    if (k < 58 and keyboard_emiter_len < 4) {
                        for (0..4) |i| {
                            if (keyboard_emiter.value.u16[i] == 0) {
                                keyboard_emiter.value.u16[i] = @intCast(k);
                                keyboard_emiter.changed = true;
                                keyboard_emiter_len += 1;

                                return;
                            }
                        }
                    }
                } else if (keyboard_emiter_len > 0) {
                    for (0..4) |i| {
                        if (keyboard_emiter.value.u16[i] == k) {
                            keyboard_emiter.value.u16[i] = 0;
                            keyboard_emiter_len -= 1;

                            return;
                        }

                        if (keyboard_emiter_len == 0) {
                            keyboard_emiter.changed = false;
                        }
                    }
                }
            }

            fn modifiers(data: ?*anyopaque, kb: ?*WlKeyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.C) void {
                _ = data;
                _ = kb;
                _ = serial;
                _ = mods_depressed;
                _ = mods_latched;
                _ = mods_locked;
                _ = group;
            }

            fn repeat_info(data: ?*anyopaque, kb: ?*WlKeyboard, rate: i32, delay: i32) callconv(.C) void {
                _ = rate;
                _ = delay;
                _ = data;
                _ = kb;
            }
        };

        fn setup() !void {
            if (c.wl_seat_add_listener(seat, &listener, null) != 0) return error.SeatListener;
        }

        fn capabilities(data: ?*anyopaque, s: ?*WlSeat, cap: u32) callconv(.C) void {
            _ = data;

            if (cap != 0 and c.WL_SEAT_CAPABILITY_KEYBOARD != 0 and c.WL_SEAT_CAPABILITY_POINTER != 0) {
                keyboard = c.wl_seat_get_keyboard(s) orelse return;
                pointer= c.wl_seat_get_pointer(s) orelse return;
                _ = c.wl_keyboard_add_listener(keyboard, &Keyboard.listener, null);
                _ = c.wl_pointer_add_listener(pointer, &Pointer.listener, null);
            }
        }

        fn name(data: ?*anyopaque, s: ?*WlSeat, n: [*c]const u8) callconv(.C) void {
            _ = data;
            _ = s;
            _ = n;
        }

        fn destroy() void {
            c.wl_keyboard_release(keyboard);
            c.wl_seat_release(seat);
        }
    };

    pub const Display = struct {
        handle: *WlDisplay,

        pub fn new() !Display {
            return .{
                .handle = c.wl_display_connect(null) orelse return error.WaylandInit,
            };
        }

        fn roundtrip(self: Display) void {
            _ = c.wl_display_roundtrip(self.handle);
        }

        fn destroy(self: Display) void {
            c.wl_display_disconnect(self.handle);
        }
    };

    pub const Registry = struct {
        handle: *WlRegistry,

        pub fn new(display: Display) !Registry {
            const handle = c.wl_display_get_registry(display.handle) orelse return error.RegistryGet;
            const listener: c.wl_registry_listener = .{
                .global = global_listener,
                .global_remove = global_remove_listener,
            };

            if (c.wl_registry_add_listener(handle, &listener, null) != 0) return error.ListenerAdd;

            display.roundtrip();

            return .{
                .handle = handle,
            };
        }

        fn global_listener(data: ?*anyopaque, registry: ?*WlRegistry, name: u32, interface: [*c]const u8, version: u32) callconv(.C) void {
            _ = version;
            _ = data;

            const interface_name = std.mem.span(interface);

            if (std.mem.eql(u8, interface_name, std.mem.span(c.wl_compositor_interface.name))) {
                const comp = c.wl_registry_bind(registry, name, &c.wl_compositor_interface, 4) orelse return;
                compositor = @ptrCast(@alignCast(comp));
            } else if (std.mem.eql(u8, interface_name, std.mem.span(c.xdg_wm_base_interface.name))) {
                const s = c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, 1) orelse return;
                shell = @ptrCast(@alignCast(s));
            } else if (std.mem.eql(u8, interface_name, std.mem.span(c.wl_seat_interface.name))) {
                const s = c.wl_registry_bind(registry, name, &c.wl_seat_interface, 1) orelse return;
                seat = @ptrCast(@alignCast(s));
            }
        }

        fn global_remove_listener(data: ?*anyopaque, registry: ?*WlRegistry, name: u32) callconv(.C) void {
            _ = data;
            _ = registry;
            _ = name;
        }

        fn destroy(self: Registry) void {
            c.wl_registry_destroy(self.handle);
        }
    };

    const Surface = struct {
        handle: *WlSurface,

        pub fn new() !Surface {
            return .{
                .handle = c.wl_compositor_create_surface(compositor) orelse return error.SurfaceCreate,
            };
        }

        fn commit(self: Surface) void {
            c.wl_surface_commit(self.handle);
        }

        fn destroy(self: Surface) void {
            c.wl_surface_destroy(self.handle);
        }
    };

    const Compositor = struct {
        handle: *WlCompositor,

        fn new() Compositor {
            return .{
                .handle = compositor,
            };
        }

        fn destroy(self: Compositor) void {
            c.wl_compositor_destroy(self.handle);
        }
    };

    const Xdg = struct {
        shell:    *XdgWmBase,
        surface:  *XdgSurface,
        toplevel: *XdgTopLevel,

        fn new(surface: *WlSurface) !Xdg {
            if (c.xdg_wm_base_add_listener(shell, &shell_listener, null) != 0) return error.XdgWmBaseAddListener;

            const shell_surface = c.xdg_wm_base_get_xdg_surface(shell, surface) orelse return error.ShellSurface;
            if (c.xdg_surface_add_listener(shell_surface, &shell_surface_listener, null) != 0) return error.ShellSurfaceListener;

            const toplevel = c.xdg_surface_get_toplevel(shell_surface) orelse return error.TopLevel;
            if (c.xdg_toplevel_add_listener(toplevel, &toplevel_listener, null) != 0) return error.ShellSurfaceListener;

            c.xdg_toplevel_set_title(toplevel, &configuration.application_name[0]);
            c.xdg_toplevel_set_app_id(toplevel, &configuration.application_name[0]);

            return .{
                .shell    = shell,
                .surface  = shell_surface,
                .toplevel = toplevel,
            };
        }

        const shell_listener: c.xdg_wm_base_listener = .{
            .ping = shell_ping,
        };

        const shell_surface_listener: c.xdg_surface_listener = .{
            .configure = shell_surface_configure,
        };

        const toplevel_listener: c.xdg_toplevel_listener = .{
            .configure = toplevel_configure,
            .close = toplevel_close,
        };

        fn shell_ping(data: ?*anyopaque, s: ?*XdgWmBase, serial: u32) callconv(.C) void {
            _ = data;
            c.xdg_wm_base_pong(s, serial);
        }

        fn shell_surface_configure(data: ?*anyopaque, shell_surf: ?*XdgSurface, serial: u32) callconv(.C) void {
            _ = data;
            c.xdg_surface_ack_configure(shell_surf, serial);

            if (resize) {
                window_resize_emiter.changed = true;
            }
        }

        fn toplevel_configure(data: ?*anyopaque, top: ?*XdgTopLevel, new_width: i32, new_height: i32, states: ?*WlArray) callconv(.C) void {
            _ = data;
            _ = states;
            _ = top;

            if (new_width != 0 and new_height != 0) {
                resize = true;
                window_resize_emiter.value = .{ .u32 = .{ @intCast(new_width), @intCast(new_height) } };
            }
        }

        fn toplevel_close(data: ?*anyopaque, top: ?*XdgTopLevel) callconv(.C) void {
            _ = data;
            _ = top;

            running = false;
        }

        fn destroy(self: Xdg) void {
            c.xdg_toplevel_destroy(self.toplevel);
            c.xdg_surface_destroy(self.surface);
            c.xdg_wm_base_destroy(self.shell);
        }
    };

    pub fn init() !Wayland {
        const display = try Display.new();
        const registry = try Registry.new(display);
        const surf = try Surface.new();
        const comp = Compositor.new();
        const xdg = try Xdg.new(surf.handle);

        try Seat.setup();

        surf.commit();
        display.roundtrip();

        running = true;

        return .{
            .display    = display,
            .registry   = registry,
            .surface    = surf,
            .compositor = comp,
            .xdg        = xdg,
        };
    }

    pub fn create_surface(self: Wayland, instance: c.VkInstance) !c.VkSurfaceKHR {
        var s: c.VkSurfaceKHR = undefined;
        const vkGetInstanceProcAddr = try _platform.get_instance_procaddr(instance);
        vkCreateWaylandSurfaceKHR = @as(c.PFN_vkCreateWaylandSurfaceKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkCreateWaylandSurfaceKHR"))) orelse return error.FunctionNotFound;

        if (vkCreateWaylandSurfaceKHR(
            instance,
            &.{
                .sType   = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                .display = self.display.handle,
                .surface = self.surface.handle,
            },
            null,
            &s
        ) != c.VK_SUCCESS) return error.VkSurfaceKHR;

        return s;
    }

    pub fn register_click_emiter(_: Wayland, e: *Emiter) void{
        e.value = .{ .u32 = .{ 0, 0 } };
        click_emiter = e;
    }

    pub fn register_mouse_emiter(_: Wayland, e: *Emiter) void {
        e.value = .{ .i32 = .{ 0, 0 } };
        mouse_emiter = e;
    }

    pub fn register_keyboard_emiter(_: Wayland, e: *Emiter) void {
        e.value = .{ .u16 = .{0, 0, 0, 0} };
        keyboard_emiter = e;
    }

    pub fn register_window_resize_emiter(_: Wayland, e: *Emiter) void {
        window_resize_emiter = e;
    }

    pub fn commit(self: Wayland) void {
        self.surface.commit();
    }

    pub fn update_events(self: Wayland) !void {
        if (running) {
            self.display.roundtrip();
        } else {
            return error.CloseDisplay;
        }
    }

    pub fn deinit(self: Wayland) void {
        Seat.destroy();
        self.xdg.destroy();
        self.surface.destroy();
        self.compositor.destroy();
        self.registry.destroy();
        self.display.destroy();
    }
};

var vkCreateWaylandSurfaceKHR: *const fn (c.VkInstance, *const c.VkWaylandSurfaceCreateInfoKHR, ?*const c.VkAllocationCallbacks, *c.VkSurfaceKHR) callconv(.C) i32 = undefined;
