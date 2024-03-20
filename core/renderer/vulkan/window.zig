const std           = @import("std");

const _config       = @import("../../util/configuration.zig");
const _platform     = @import("../../platform/platform.zig");
const _event        = @import("../../event/event.zig");
const _instance     = @import("instance.zig");

const Instance      = _instance.Instance;

const Platform      = _platform.Platform;
const Emiter        = _event.EventSystem.Event.Emiter;
const Listener      = _event.EventSystem.Event.Listener;
const Argument      = _event.EventSystem.Argument;

const c             = _platform.c;
const configuration = _config.Configuration;
const logger        = configuration.logger;

pub const Window = struct {
    surface: c.VkSurfaceKHR,
    resized: bool = false,
    width:   u32,
    height:  u32,

    pub fn new(surface: c.VkSurfaceKHR) !Window {
        return .{
            .width   = configuration.default_width,
            .height  = configuration.default_height,
            .surface = surface,
        };
    }

    pub fn listener(self: *Window) Listener {
        return .{
            .ptr       = self,
            .listen_fn = listen,
        };
    }

    pub fn listen(ptr: *anyopaque, argument: Argument) bool {
        const self: *Window = @alignCast(@ptrCast(ptr));
        const new_width     = argument.u32[0];
        const new_height    = argument.u32[1];

        if (new_width != self.width or new_height != self.height) {
            self.width   = new_width;
            self.height  = new_height;
            self.resized = true;
        }

        return false;
    }


    pub fn destroy(self: Window, instance: Instance) void {
        instance.destroy_surface(self.surface);
    }
};
