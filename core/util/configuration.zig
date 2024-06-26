const std = @import("std");
const _log = @import("log.zig");

const Logger = _log.Logger;

pub const Configuration = struct {
    pub const application_name: []const u8 = "Engine";
    pub const default_width: u32 = 1920;
    pub const default_height: u32 = 1080;
    pub const version: u8 = 1;

    pub const logger = Logger {
        .level = .Debug,
    };
};

pub const State = enum {
    Running,
    Closing,
    Suspended,
};
