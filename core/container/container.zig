const std = @import("std");

const _math = @import("../math/math.zig");
const _mesh = @import("../assets/mesh.zig");
const _event = @import("../event/event.zig");
const _platform = @import("../platform/platform.zig");
const _collections = @import("../collections/collections.zig");
const _configuration = @import("../util/configuration.zig");
const _camera = @import("camera.zig");
const _font = @import("../assets/font.zig");

const Vec = _math.Vec;
const Matrix = _math.Matrix;

const ArrayList = _collections.ArrayList;
const Allocator = std.mem.Allocator;
const Camera = _camera.Camera;

const ObjectType = _mesh.Mesh.Type;
const TrueTypeFont = _font.TrueTypeFont;
const FontManager = _font.FontManager;
const FontType = _font.Type;

const EventSystem = _event.EventSystem;
const Listener = EventSystem.Event.Listener;
const Argument = EventSystem.Argument;

const Platform = _platform.Platform;
const KeyMap = _platform.KeyMap;

const configuration = _configuration.Configuration;

pub const Container = struct {
    objects: ArrayList(Object),
    glyphs: ArrayList(Object),
    updates: ArrayList(Update),
    camera: Camera,
    font_manager: FontManager,

    const Update = struct {
        change: Change,
        @"type": Type,
        id: u16,

        const Type = union(enum) {
            font: FontType,
            mesh: ObjectType,
        };

        const Change = enum(u8) {
            color,
            model,
            new
        };

        const Data = struct {
            value: [4][4]f32,
            change: Change,
            operation: Operation,

            const Operation = enum {
                replace,
                add,
            };
        };
    };

    const Object = struct {
        model: [4][4]f32,
        color: [4][4]f32,
        id: u16,
    };

    fn add_object(self: *Container, typ: ObjectType, object: Object) !void {
        try self.updates.push(.{
            .change = .new,
            .id = @intCast(self.objects.items.len),
            .type = .{ .mesh = typ }
        });

        try self.objects.push(object);
    }

    fn add_glyph(self: *Container, typ: FontType, glyph: Object) !void {
        try self.updates.push(.{
            .change = .new,
            .id = @intCast(self.glyphs.items.len),
            .type = .{ .font = typ },
        });

        try self.glyphs.push(glyph);
    }

    fn update_data(self: *Container, data: Update.Data, typ: Update.Type, id: u16) !void {
        const item = switch (typ) {
            .font => &self.font_glyphs.items[id],
            .object => &self.objects.items[id],
        };

        const to_change: *[4][4]f32 = switch (data.change) {
                .model => &item.model,
                .color => &item.color,
                .new => unreachable
        };

        const new_matrix = switch (data.operation) {
            .add => Matrix.mult(data.value, to_change.*),
            .replace => data.value,
        };

        to_change.* = new_matrix;

        try self.updates.push(.{
            .id = id,
            .change = data.change
        });
    }

    pub fn update(self: *Container) !void {
        if (self.objects.items.len == 0) {
            try self.add_object(.plane, .{
                .model = Matrix.scale(1.0, 1.0, 1.0),
                .color = Matrix.scale(1.0, 1.0, 1.0),
                .id = undefined,
            });

            try self.add_glyph(.a, .{
                .model = Matrix.translate(2.0, 0.0, 0.0),
                .color = Matrix.scale(1.0, 1.0, 1.0),
                .id = undefined,
            });
        }
    }

    pub fn keyboard_listener(self: *Container) Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_keyboard,
        };
    }

    pub fn mouse_listener(self: *Container) Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_mouse,
        };
    }

    pub fn resize_listener(self: *Container) Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_resize,
        };
    }

    pub fn click_listener(self: *Container) Listener {
        return .{
            .ptr = self,
            .listen_fn = listen_click,
        };
    }

    pub fn listen_keyboard(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_keyboard(argument);
    }

    pub fn listen_mouse(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_mouse(argument);
    }

    pub fn listen_resize(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_resize(argument);
    }

    pub fn listen_click(ptr: *anyopaque, argument: Argument) bool {
        const self: *Container = @ptrCast(@alignCast(ptr));
        return self.camera.listen_click(argument);
    }

    pub fn new(allocator: Allocator) !Container {
        var font = try TrueTypeFont.new("assets/font/font.ttf", allocator);
        try font.add_glyph(.a);
        const font_manager = try font.font_manager();

        return .{
            .objects = try ArrayList(Object).init(allocator, 1),
            .glyphs = try ArrayList(Object).init(allocator, 1),
            .updates = try ArrayList(Update).init(allocator, 1),
            .font_manager = font_manager,
            .camera = Camera.init(.{
                .x = 0.0,
                .y = 0.0,
                .z = - 1.0,
            }),
        };
    }

    pub fn shutdown(self: *Container) void {
        self.objects.deinit();
        self.glyphs.deinit();
        self.font_manager.deinit();
        self.updates.deinit();
    }
};
