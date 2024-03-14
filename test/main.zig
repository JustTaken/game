const std = @import("std");
const core = @import("core");
const generator = @import("generator");

const TrueTypeFont = core.TrueTypeFont;
const Application = core.Application;

test "Parse : TrueTypeFont" {
    var font = try TrueTypeFont.new("assets/font.ttf", std.testing.allocator);

    font.deinit();
}

test "Parse : Xml" {
    _ = try generator.Xml.parse("assets/shader.vert");
}
const rating: u32 = rate: {
    const extensions_properties = instance.enumerate_device_extension_properties(physical_device, allocator) catch {
        logger.log(.Warn, "Could not get properties of one physical device, skipping", .{});

        break :rate 0;
    };

    defer allocator.free(extensions_properties);

    ext: for (REQUIRED_DEVICE_EXTENSIONS) |extension| {
        for (extensions_properties) |propertie| {
            if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&propertie.extensionName, 0))) break :ext;
        }
    } else {
        break :rate 0;
    }

    if (!(instance.get_physical_device_surface_formats(physical_device, surface, allocator) catch break :rate 0).len > 0) break :rate 0;
    if (!(instance.get_physical_device_surface_present_modes(physical_device, surface, allocator) catch break :rate 0).len > 0) break :rate 0;

    const families_properties = instance.get_physical_device_queue_family_properties(physical_device, allocator) catch |e| {
        logger.log(.Error, "Failed to get queue family properties", .{});
        return e;
    };

    defer allocator.free(families_properties);
    for (families_properties, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (families[0] == null and bit(properties.queueFlags, c.VK_QUEUE_GRAPHICS_BIT)) {
            families[0] = family;
        }
        if (families[1] == null and try instance.get_physical_device_surface_support(physical_device, family, surface)) {
            families[1] = family;
        }
        if (families[2] == null and bit(properties.queueFlags, c.VK_QUEUE_COMPUTE_BIT)) {
            families[2] = family;
        }
        if (families[3] == null and bit(properties.queueFlags, c.VK_QUEUE_TRANSFER_BIT)) {
            families[3] = family;
        }
    }
                  for (families) |i| {
                     if (i) |_| {
                     } else {
                                break :rate 0;
                            }
                        }

                        var sum: u8 = 1;

                        const physical_device_feats = instance.get_physical_device_features(physical_device);
                        const physical_device_props = instance.get_physical_device_properties(physical_device);

                        if (!Vulkan.boolean(physical_device_feats.geometryShader)) break :rate 0;
                        if (!Vulkan.boolean(physical_device_feats.samplerAnisotropy)) break :rate 0;

                        sum += switch (physical_device_props.deviceType) {
                            @intFromEnum(Type.DiscreteGpu) => 4,
                            @intFromEnum(Type.IntegratedGpu) => 3,
                            @intFromEnum(Type.VirtualGpu) => 2,
                            @intFromEnum(Type.Other) => 1,
                            else => 0,
                        };

                        break :rate sum;
};
