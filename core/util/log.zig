const std = @import("std");

pub const Log  = struct {
    level: Level = .Error,

    pub const Level = enum {
        Fatal,
        Error,
        Warn,
        Info,
        Debug,

        pub fn as_text(self: Level) []const u8 {
            return switch (self) {
                .Fatal => "\x1b[1;31mFatal\x1b[0m",
                .Error => "\x1b[0;31mError\x1b[0m",
                .Warn => "\x1b[0;33mWarn\x1b[0m",
                .Info => "\x1b[0;32mInfo\x1b[0m",
                .Debug => "\x1b[0;34mDebug\x1b[0m",
            };
        }
    };

    pub fn log(comptime self: Log, comptime level: Level, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(level) > @intFromEnum(self.level)) {
            return;
        }

        const prefix = "[" ++ comptime level.as_text() ++ "]: ";

        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();
        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
    }
};
