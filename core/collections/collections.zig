const std = @import("std");
const _allocator = @import("../util/allocator.zig");

const Allocator = _allocator.Allocator;

pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: u32,
        allocator: *Allocator,

        const Self = @This();
        const grow_factor = 10;

        pub fn init(allocator: *Allocator, capacity: ?u32) !Self {
            const c = capacity orelse 0;
            const memory = try allocator.alloc(T, c);
            var items: []T = &[_]T {};
            items.ptr = memory.ptr;

            return Self {
                .items = items,
                .capacity = c,
                .allocator = allocator
            };
        }

        pub fn push(self: *Self, item: T) !void {
            if (self.items.len >= self.capacity) {
                try self.resize(self.capacity + grow_factor);
            }

            self.items.len += 1;
            self.items[self.items.len - 1] = item;
        }

        pub fn push_slice(self: *Self, items: []const T) !void {
            if (self.items.len + items.len >= self.capacity) {
                try self.resize(self.capacity + @as(u32, @intCast(items.len)) + grow_factor);
            }

            const len = self.items.len;
            self.items.len += items.len;

            @memcpy(self.items[len..self.items.len], items.ptr[0..items.len]);
        }

        pub fn insert(self: *Self, item: T, i: u32) !void {
            if (self.items.len + 1 >= self.capacity) {
                try self.resize(self.capacity + 1 + grow_factor);
            }

            self.items.len += 1;
            std.mem.copyBackwards(T, self.items[i + 1..self.items.len], self.items[i..self.items.len - 1]);

            // @memcpy(self.items[i + 1..self.items.len], self.items[i..self.items.len - 1]);
            self.items[i] = item;

            // if (!(self.items.len + 1 >= self.capacity)) {
            //     try self.resize(self.capacity + 1 + grow_factor);
            // }


            // if (self.capacity <= i) return error.IndexNotAvailable;

            // self.items.len = std.math.max(i, self.items.len);
            // self.items[i] = item;
        }

        pub fn get(self: Self, i: u32) !T {
            if (self.items.len <= i) return error.NoItemAtIndex;

            return self.items[i];
        }

        pub fn get_last_mut(self: *Self) !*T {
            return &self.items[self.items.len - 1];
        }

        pub fn clear(self: *Self) !void {
            self.items.len = 0;
            try self.resize(1);
        }

        fn resize(self: *Self, capacity: u32) !void {
            const len = self.items.len;

            self.items = try self.allocator.realloc(self.items.ptr[0..self.capacity], capacity);
            self.capacity = capacity;
            self.items.len = len;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items.ptr[0..self.capacity]);
            self.capacity = 0;
        }
    };
}
