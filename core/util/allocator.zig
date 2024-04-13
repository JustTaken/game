const std = @import("std");

const Logger = @import("log.zig").Logger;

pub const Allocator = struct {
    handle: std.mem.Allocator,
    logger: Logger,
    memory_used: u32,

    pub fn new(allocator: std.mem.Allocator, logger: Logger) Allocator {
        return .{
            .handle = allocator,
            .logger = logger,
            .memory_used = 0,
        };
    }

    pub fn alloc(self: *Allocator, T: type, size: usize) ![]T {
        const len =  @sizeOf(T) * size;

        self.logger.log(.Debug, "{} bytes allocated for {} members of type {s}", .{len, size, @typeName(T)});

        self.memory_used += @intCast(len);

        return try self.handle.alloc(T, size);
    }

    pub fn free(self: *Allocator, memory: anytype) void {
        const T = std.meta.Elem(@TypeOf(memory));
        const len = @sizeOf(T) * memory.len;

        self.logger.log(.Debug, "{} bytes freed of {} members of type {s}", .{len, memory.len, @typeName(T)});

        self.memory_used -= @intCast(len);

        self.handle.free(memory);
    }

    pub fn usage(self: *Allocator) void {
        self.logger.log(.Debug, "memory usage: {}", .{self.memory_used});
    }

    pub fn realloc(self: *Allocator, memory: anytype, size: usize) !@TypeOf(memory) {
        const T = std.meta.Elem(@TypeOf(memory));
        const len = @sizeOf(T) * memory.len;

        self.logger.log(.Debug, "{} bytes freed of {} members of type {s}", .{len, memory.len, @typeName(T)});
        self.logger.log(.Debug, "{} bytes allocated of {} members of type {s}", .{len, size, @typeName(T)});

        self.memory_used += @intCast(@sizeOf(T) * size);
        self.memory_used -= @intCast(len);

        return try self.handle.realloc(memory, size);

    }
};
