pub const Game = struct {
    window: Window,
    name: []const u8,

    const Window = struct {
        width: u32,
        height: u32,
    };

    pub fn update(_: *Game) void {}

    fn initialize() !void {}
    fn render(_: *Game) !void {}
    fn on_resize(_: *Game) !void {}
};
