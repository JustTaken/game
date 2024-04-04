const std           = @import("std");

const _config       = @import("../../util/configuration.zig");
const _platform     = @import("../../platform/platform.zig");
const _device       = @import("device.zig");
const _window       = @import("window.zig");

const Window        = _window.Window;

const Device        = _device.Device;

const Platform      = _platform.Platform;
const Timer         = std.time.Timer;

const c             = _platform.c;
const configuration = _config.Configuration;
const logger        = configuration.logger;

pub const Sync = struct {
    image_available: c.VkSemaphore,
    render_finished: c.VkSemaphore,
    in_flight_fence: c.VkFence,
    timer:           Timer,
    nanos_per_frame: u32,
    changed:         bool = true,

    pub const default: u32 = @intCast(1000000000 / 60);

    pub fn new(device: Device) !Sync {
        const nanos_per_frame = default;
        const timer = try Timer.start();

        const image = try device.create_semaphore(.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        });

        const render = try device.create_semaphore(.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        });

        const fence = try device.create_fence(.{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        });

        return .{
            .image_available = image,
            .render_finished = render,
            .in_flight_fence = fence,
            .timer           = timer,
            .nanos_per_frame = nanos_per_frame,
        };
    }

    pub fn update(self: *Sync, device: Device) void {
        if (self.changed) {
            device.wait_for_fences(&self.in_flight_fence) catch {};
            device.reset_fences(&self.in_flight_fence) catch {};
            self.changed = false;
        }

        const delta = self.timer.lap();
        if (delta < self.nanos_per_frame) {
            std.time.sleep(self.nanos_per_frame - delta);
            self.timer.reset();
        }
    }

    pub fn destroy(self: Sync, device: Device) void {
        device.destroy_semaphore(self.image_available);
        device.destroy_semaphore(self.render_finished);
        device.destroy_fence(self.in_flight_fence);
    }
};
