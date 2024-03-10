const Log = @import("../log.zig");
const std = @import("std");

pub const Configuration = struct {
    pub const application_name: []const u8 = "Engine";
    pub const default_width: u32 = 1920;
    pub const default_height: u32 = 1080;
    pub const version: u32 = 1;
    pub const logger = Log.Log {
        .level = .Debug,
    };
};

pub const State = enum {
    Stoped,
    Running,
    Closing,
    Suspended,
};
