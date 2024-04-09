const std = @import("std");

const _container = @import("container/container.zig");
const _event = @import("event/event.zig");
const _backend = @import("renderer/backend.zig");
const _platform = @import("platform/platform.zig");
const _configuration = @import("util/configuration.zig");

const EventSystem = _event.EventSystem;
const Backend = _backend.Backend;
const Renderer = _backend.Renderer;
const Platform = _platform.Platform;
const Compositor = _platform.Compositor;
const Container = _container.Container;

const Allocator = std.mem.Allocator;
const logger = _configuration.Configuration.logger;

pub fn Application(comptime compositor: Compositor, comptime renderer: Renderer) type {
    return struct {
        backend: Backend(compositor, renderer),
        container: Container,
        event_system: EventSystem,

        const Self = @This();

        pub fn new(allocator: Allocator) !Self {
            const container: Container = try Container.new(allocator);
            const backend: Backend(compositor, renderer) = try Backend(compositor, renderer).new(allocator);
            const event_system: EventSystem = try EventSystem.new(allocator);

            return .{
                .container = container,
                .backend = backend,
                .event_system = event_system,
            };
        }

        pub fn run(self: *Self) !void {
            defer self.shutdown();

            try self.event_system.add_listener(self.container.resize_listener(), .WindowResize);
            try self.event_system.add_listener(self.container.mouse_listener(), .MouseMove);
            try self.event_system.add_listener(self.container.click_listener(), .MouseClick);
            try self.event_system.add_listener(self.container.keyboard_listener(), .KeyPress);
            try self.event_system.add_listener(self.backend.renderer.window.listener(), .WindowResize);

            self.backend.platform.register_keyboard_emiter(try self.event_system.add_emiter(.KeyPress, false));
            self.backend.platform.register_mouse_emiter(try self.event_system.add_emiter(.MouseMove, true));
            self.backend.platform.register_click_emiter(try self.event_system.add_emiter(.MouseClick, true));
            self.backend.platform.register_window_resize_emiter(try self.event_system.add_emiter(.WindowResize, true));

            while (self.event_system.state != .Closing) {
                self.backend.sync();

                if (self.event_system.state != .Suspended) {
                    self.backend.draw(&self.container) catch |e| {
                        switch (e) {
                            error.CloseDisplay => self.event_system.state = .Closing,
                            else => return e,
                        }
                    };

                    self.event_system.input();
                    try self.container.update();
                }
            }
        }

        pub fn shutdown(self: *Self) void {
            self.backend.sync();
            self.event_system.shutdown();
            self.container.shutdown();
            self.backend.shutdown();
        }
    };
}
