const std = @import("std");

const _game = @import("game.zig");
const _event = @import("event.zig");
const _config = @import("util/configuration.zig");
const _backend = @import("renderer/backend.zig");
const _platform = @import("platform/platform.zig");

const Game = _game.Game;
const Backend = _backend.Backend;
const Renderer = _backend.Renderer;
const Compositor = _platform.Compositor;
const Platform = _platform.Platform;
const EventSystem = _event.EventSystem;
const Configuration = _config.Configuration;

pub const logger = Configuration.logger;

pub fn Application(comptime compositor: Compositor, comptime renderer: Renderer) type {
    return struct {
        game: Game,
        backend: Backend(compositor, renderer),
        event_system: EventSystem,

        const Self = @This();

        pub fn new(allocator: std.mem.Allocator) !Self {
            const game: Game = Game.new(allocator) catch |e| {
                logger.log(.Fatal, "Could not create game instance", .{});

                return e;
            };

            const event_system: EventSystem = EventSystem.new() catch |e| {
                logger.log(.Fatal, "Could not create event handle system", .{});

                return e;
            };

            const backend: Backend(compositor, renderer) = Backend(compositor, renderer).new() catch |e| {
                logger.log(.Fatal, "Failed to initialize backend, {}", .{e});

                return e;
            };

            logger.log(.Info, "Application successfully initialized", .{});

            return .{
                .game = game,
                .backend = backend,
                .event_system = event_system,
            };
        }

        pub fn run(self: *Self) void {
            self.event_system.add_listener(self.game.camera.listener_resize(), .WindowResize) catch {
                logger.log(.Fatal,"Could not register camera in resize window event system", .{});
                return;
            };

            self.event_system.add_listener(self.game.camera.listener_keyboard(), .KeyPress) catch {
                logger.log(.Fatal,"Could not register camera in keyboard event system", .{});
                return;
            };

            self.event_system.add_listener(self.game.camera.listener_mouse(), .MouseMove) catch {
                logger.log(.Fatal,"Could not register camera in mouse event system", .{});
                return;
            };

            self.event_system.add_listener(self.game.camera.listener_click(), .MouseClick) catch {
                logger.log(.Fatal, "Could not register camera in mouse click system", .{});
                return;
            };

            self.event_system.add_listener(self.game.object_handle.listener(), .KeyPress) catch {
                logger.log(.Fatal,"Could not register object handle in keyboard event system", .{});
                return;
            };

            self.event_system.add_listener(self.backend.renderer.window.listener(), .WindowResize) catch {
                logger.log(.Fatal, "Could not register window as window resize listener", .{});
                return;
            };

            self.backend.platform.register_keyboard_emiter(self.event_system.add_emiter(.KeyPress) catch {
                logger.log(.Fatal, "Failed to register keyboard emiter", .{});
                return;
            });

            self.backend.platform.register_mouse_emiter(self.event_system.add_emiter(.MouseMove) catch {
                logger.log(.Fatal, "Could not register mouse movement emiter", .{});
                return;
            });

            self.backend.platform.register_click_emiter(self.event_system.add_emiter(.MouseClick) catch {
                logger.log(.Fatal, "Cold not register mouse click emiter", .{});
                return;
            });

            self.backend.platform.register_window_resize_emiter(self.event_system.add_emiter(.WindowResize) catch {
                logger.log(.Fatal, "Failed to register window resize emiter", .{});
                return;
            });

            while (self.event_system.state != .Closing) {
                self.backend.sync();

                if (self.event_system.state != .Suspended) {
                    self.backend.draw(&self.game) catch |e| {
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

                    self.game.update() catch {
                        logger.log(.Fatal, "Unrecoverable problem on frame update", .{});
                        break;
                    };
                }
            }

            self.shutdown();
        }

        pub fn shutdown(self: *Self) void {
            self.game.shutdown();
            self.event_system.shutdown();
            self.backend.shutdown();
        }
    };
}
