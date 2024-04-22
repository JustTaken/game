const std = @import("std");

pub const Allocator = struct {
    handle: std.mem.Allocator,
    memory_used: u32,

    pub fn new(allocator: std.mem.Allocator) Allocator {
        return .{
            .handle = allocator,
            .memory_used = 0,
        };
    }

    pub fn alloc(self: *Allocator, T: type, size: usize) ![]T {
        const len =  @sizeOf(T) * size;

        self.memory_used += @intCast(len);

        return try self.handle.alloc(T, size);
    }

    pub fn free(self: *Allocator, memory: anytype) void {
        const T = std.meta.Elem(@TypeOf(memory));
        const len = @sizeOf(T) * memory.len;

        self.memory_used -= @intCast(len);

        self.handle.free(memory);
    }

    pub fn realloc(self: *Allocator, memory: anytype, size: usize) !@TypeOf(memory) {
        const T = std.meta.Elem(@TypeOf(memory));
        const len = @sizeOf(T) * memory.len;

        self.memory_used += @intCast(@sizeOf(T) * size);
        self.memory_used -= @intCast(len);

        return try self.handle.realloc(memory, size);
    }
};
