const std = @import("std");

pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: u32,
        allocator: std.mem.Allocator,

        const Self = @This();
        const grow_factor = 10;

        pub fn init(allocator: std.mem.Allocator, capacity: ?u32) !Self {
            const memory = try allocator.alloc(T, capacity orelse 0);
            var items: []T = &[_]T {};
            items.ptr = memory.ptr;
            items.len = 0;

            return Self {
                .items = items,
                .capacity = capacity orelse 0,
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

// pub fn HashSet(comptime T: type) type {
//     return struct {
//         items: []T,
//         array: ArrayList(T),
//         metadata: []Metadata,
//         allocator: std.mem.Allocator,

//         const Self = @This();
//         const grow_factor = 10;

//         const Metadata = struct {
//             ocupied: bool = false,
//             hash: u32,
//             array_index: u32,
//         };

//         pub fn init(allocator: std.mem.Allocator, capacity: u32) !Self {
//             if (!@hasDecl(T, "hash") or !@hasDecl(T, "equal")) return error.DoNotHaveNeededFunctions;

//             return Self {
//                 .items = try allocator.alloc(T, capacity),
//                 .metadata = try allocator.alloc(Metadata, capacity),
//                 .allocator = allocator,
//                 .array = ArrayList(T).init(allocator),
//             };
//         }

//         pub fn push(self: *Self, item: T) !bool {

//             return try self.push_item(item, null);
//         }

//         fn push_item(self: *Self, item: T, index: ?usize) !bool {
//             if (self.array.items.len >= self.items.len) return error.FullSet;

//             const len = self.items.len - 1;
//             const hash = item.hash();

//             var flag = false;
//             var i = blk: {
//                 if (index) |in| {
//                     break :blk in;
//                 } else {
//                     break :blk hash % len;
//                 }
//             };

//             while (true) {
//                 if (!self.metadata[i].ocupied) {
//                     self.items[i] = item;
//                     self.metadata[i].hash = hash;
//                     self.metadata[i].ocupied = true;
//                     self.metadata[i].array_index = @intCast(self.array.items.len);
//                     flag = true;
//                     break;
//                 } else if (hash < self.metadata[i].hash) {
//                     const old_item = self.items[i];
//                     self.items[i] = item;
//                     self.metadata[i].hash = hash;
//                     self.metadata[i].array_index = @intCast(self.array.items.len);
//                     _ = try self.push_item(old_item, i + 1);
//                     flag = true;
//                     break;
//                 } else if (self.items[i].equal(item)) {
//                     std.debug.print("repeating yourselve\n", .{});
//                     break;
//                 }

//                 i += 1;
//             }

//             if (index) |_| {} else {
//                 if (flag) try self.array.push(item);
//             }

//             return flag;
//         }

//         pub fn get_index(self: Self, item: T) !u32 {
//             const len = self.items.len - 1;
//             const hash = item.hash();
//             var index = hash % len;

//             while (true) {
//                 if (self.metadata[index].ocupied) {
//                     if (self.metadata[index].hash == hash) {
//                         if (self.items[index].equal(item)) {
//                             return self.metadata[index].array_index;
//                         }
//                     } else if (self.metadata[index].hash > hash) {
//                         break;
//                     } else {
//                         index += 1;
//                     }
//                 } else {
//                     break;
//                 }
//             }

//             return error.NotFound;
//         }

//         pub fn get_items(self: Self) !ArrayList(T) {
//             return self.array;
//         }
//     };
// }
