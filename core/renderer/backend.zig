const std = @import("std");

const _vulkan = @import("vulkan/vulkan.zig");
const _container = @import("../container/container.zig");
const _event = @import("../event/event.zig");
const _platform = @import("../platform/platform.zig");
const _configuration = @import("../util/configuration.zig");

const Vulkan = _vulkan.Vulkan;
const Container = _container.Container;
const Emiter = _event.EventSystem.Event.Emiter;

const Compositor = _platform.Compositor;
const Platform = _platform.Platform;

const Allocator = std.mem.Allocator;

pub fn Backend(comptime compositor: Compositor, comptime renderer: Renderer) type {
    return struct {
        renderer: R,
        platform: P,

        const Self = @This();

        pub const R = Renderer.get(renderer);
        pub const P = Platform(compositor);

        pub fn new(allocator: Allocator) !Self {
            const platform = try P.init();
            const backend_renderer = try R.new(P, platform, allocator);

            return .{
                .renderer = backend_renderer,
                .platform = platform,
            };
        }

        pub fn draw(self: *Self, container: *Container) !void {
            if (try self.renderer.draw(container)) {
                self.platform.commit();
            }

            try self.platform.update_events();
        }

        pub fn sync(self: *Self) void {
            self.renderer.clock();
        }

        pub fn register_window_emiter(self: *Self, emiter: *Emiter) void {
            self.renderer.window.register_emiter(emiter);
        }

        pub fn shutdown(self: *Self) void {
            self.renderer.shutdown();
            self.platform.deinit();
        }
    };
}

pub const Renderer = enum {
    vulkan,

    fn get(self: Renderer) type {
        return switch (self) {
            .vulkan => Vulkan,
        };
    }
};
