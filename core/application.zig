const std            = @import("std");

const _container     = @import("container/container.zig");
const _event         = @import("event/event.zig");
const _backend       = @import("renderer/backend.zig");
const _platform      = @import("platform/platform.zig");
const _configuration = @import("util/configuration.zig");

const EventSystem    = _event.EventSystem;
const Backend        = _backend.Backend;
const Renderer       = _backend.Renderer;
const Platform       = _platform.Platform;
const Compositor     = _platform.Compositor;
const Container      = _container.Container;

const logger         = _configuration.Configuration.logger;

pub fn Application(comptime compositor: Compositor, comptime renderer: Renderer) type {
    return struct {
        backend:      Backend(compositor, renderer),
        container:    Container,
        event_system: EventSystem,

        const Self = @This();

        pub fn new(allocator: std.mem.Allocator) !Self {
            const container: Container = Container.new(allocator) catch |e| {
                logger.log(.Fatal, "Could not create container instance", .{});

                return e;
            };

            const event_system: EventSystem = EventSystem.new(allocator) catch |e| {
                logger.log(.Fatal, "Could not create event handle system", .{});

                return e;
            };

            const backend: Backend(compositor, renderer) = Backend(compositor, renderer).new(allocator) catch |e| {
                logger.log(.Fatal, "Failed to initialize backend", .{});

                return e;
            };

            return .{
                .container    = container,
                .backend      = backend,
                .event_system = event_system,
            };
        }

        pub fn run(self: *Self) void {
            self.event_system.add_listener(self.container.resize_listener(), .WindowResize) catch {
                logger.log(.Fatal,"Failed to register camera in resize window event system", .{});
                return;
            };

            self.event_system.add_listener(self.container.mouse_listener(), .MouseMove) catch {
                logger.log(.Fatal,"Failed to register camera in mouse event system", .{});
                return;
            };

            self.event_system.add_listener(self.container.click_listener(), .MouseClick) catch {
                logger.log(.Fatal, "Failed to register camera in mouse click system", .{});
                return;
            };

            self.event_system.add_listener(self.container.keyboard_listener(), .KeyPress) catch {
                logger.log(.Fatal,"Failed to register object handle in keyboard event system", .{});
                return;
            };

            self.event_system.add_listener(self.backend.renderer.window.listener(), .WindowResize) catch {
                logger.log(.Fatal, "Failed to register window as window resize listener", .{});
                return;
            };

            self.backend.platform.register_keyboard_emiter(self.event_system.add_emiter(.KeyPress, false) catch {
                logger.log(.Fatal, "Failed to register keyboard emiter", .{});
                return;
            });

            self.backend.platform.register_mouse_emiter(self.event_system.add_emiter(.MouseMove, true) catch {
                logger.log(.Fatal, "Failed to register mouse movement emiter", .{});
                return;
            });

            self.backend.platform.register_click_emiter(self.event_system.add_emiter(.MouseClick, true) catch {
                logger.log(.Fatal, "Failed to register mouse click emiter", .{});
                return;
            });

            self.backend.platform.register_window_resize_emiter(self.event_system.add_emiter(.WindowResize, true) catch {
                logger.log(.Fatal, "Failed to register window resize emiter", .{});
                return;
            });

            while (self.event_system.state != .Closing) {
                self.backend.sync();

                if (self.event_system.state != .Suspended) {
                    self.backend.draw(&self.container) catch |e| {
                        switch (e) {
                            error.CloseDisplay => {
                                self.event_system.state = .Closing;
                                logger.log(.Info, "Closing Application", .{});
                            },
                            else => {
                                logger.log(.Fatal, "Unrecoverable problem occoured on frame draw", .{});
                                break;
                            }
                        }

                        break;
                    };

                    self.event_system.input();

                    self.container.update() catch {
                        logger.log(.Fatal, "Unrecoverable problem on frame update", .{});
                        break;
                    };
                }
            }

            self.shutdown();
        }

        pub fn shutdown(self: *Self) void {
            self.backend.sync();
            self.event_system.shutdown();
            self.container.shutdown();
            self.backend.shutdown();
        }
    };
}
