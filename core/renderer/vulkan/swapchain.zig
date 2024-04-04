const std                = @import("std");

const _config            = @import("../../util/configuration.zig");
const _collections       = @import("../../collections/collections.zig");
const _platform          = @import("../../platform/platform.zig");

const _result            = @import("error.zig");
const _instance          = @import("instance.zig");
const _device            = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");
const _window            = @import("window.zig");
const _data              = @import("data.zig");
const _command_pool      = @import("command_pool.zig");
const _sync              = @import("sync.zig");

const Instance           = _instance.Instance;
const GraphicsPipeline   = _graphics_pipeline.GraphicsPipeline;
const Device             = _device.Device;
const Data               = _data.Data;
const Window             = _window.Window;
const CommandPool        = _command_pool.CommandPool;
const Sync               = _sync.Sync;
const Result             = _result.Result;

const Platform           = _platform.Platform;
const ArrayList          = _collections.ArrayList;
const Allocator          = std.mem.Allocator;

const c                  = _platform.c;
const configuration      = _config.Configuration;
const logger             = configuration.logger;

pub const Swapchain = struct {
    handle:             c.VkSwapchainKHR,
    extent:             c.VkExtent2D,
    depth_image:        c.VkImage,
    depth_image_view:   c.VkImageView,
    depth_image_memory: c.VkDeviceMemory,

    image_views:        ArrayList(c.VkImageView),
    framebuffers:       ArrayList(c.VkFramebuffer),
    allocator:          Allocator,

    force_redraw:       bool,

    pub fn new(
        device:            Device,
        allocator:         Allocator,
        instance:          Instance,
        window:            Window,
        graphics_pipeline: GraphicsPipeline
    ) !Swapchain {
        const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;
        const capabilities = try instance.get_physical_device_surface_capabilities(device.physical_device, window.surface);

        const extent = if (capabilities.currentExtent.width != 0xFFFFFFFF) capabilities.currentExtent
        else c.VkExtent2D {
            .width  = std.math.clamp(window.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(window.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };

        const image_count =
            if (capabilities.maxImageCount > 0) @min(capabilities.minImageCount + 1, capabilities.maxImageCount)
            else capabilities.minImageCount + 1;

        var uniques_queue_family_index = try Device.Queue.uniques(&.{ device.queues[0].family, device.queues[1].family }, allocator);
        defer uniques_queue_family_index.deinit();

        const handle = try device.create_swapchain(.{
            .sType                 = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface               = window.surface,
            .minImageCount         = image_count,
            .imageFormat           = graphics_pipeline.format.format,
            .imageColorSpace       = graphics_pipeline.format.colorSpace,
            .imageExtent           = extent,
            .imageSharingMode      = if (uniques_queue_family_index.items.len == 1) c.VK_SHARING_MODE_EXCLUSIVE else c.VK_SHARING_MODE_CONCURRENT,
            .presentMode           = present_mode,
            .preTransform          = capabilities.currentTransform,
            .clipped               = c.VK_TRUE,
            .imageArrayLayers      = 1,
            .compositeAlpha        = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .imageUsage            = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .queueFamilyIndexCount = @as(u32, @intCast(uniques_queue_family_index.items.len)),
            .pQueueFamilyIndices   = uniques_queue_family_index.items.ptr,
            .oldSwapchain          = null,
        });

        var images = try device.get_swapchain_images(handle, allocator);
        defer images.deinit();

        var image_views = try ArrayList(c.VkImageView).init(allocator, @intCast(image_count));

        for (images.items) |image| {
            try image_views.push(try device.create_image_view(.{
                .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image            = image,
                .format           = graphics_pipeline.format.format,
                .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
                .subresourceRange = .{
                    .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel   = 0,
                    .levelCount     = 1,
                    .baseArrayLayer = 0,
                    .layerCount     = 1,
                },
                .components       = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
            }));
        }

        const depth_image = try device.create_image(.{
            .sType         = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType     = c.VK_IMAGE_TYPE_2D,
            .extent        = .{
                .width  = extent.width,
                .height = extent.height,
                .depth  = 1,
            },
            .mipLevels     = 1,
            .arrayLayers   = 1,
            .format        = graphics_pipeline.depth_format,
            .tiling        = c.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage         = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .samples       = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode   = c.VK_SHARING_MODE_EXCLUSIVE,
        });

        const image_memory_requirements = device.get_image_memory_requirements(depth_image);
        const memory_index = for (0..device.memory_properties.memoryTypeCount) |i| {
            if ((image_memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (device.memory_properties.memoryTypes[i].propertyFlags & c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) == c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
                break i;
            }
        } else return error.NoMemoryRequirementsPassed;

        const depth_image_memory = try device.allocate_memory(.{
            .sType           = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = image_memory_requirements.size,
            .memoryTypeIndex = @intCast(memory_index),
        });

        try device.bind_image_memory(depth_image, depth_image_memory);

        const depth_image_view = try device.create_image_view(.{
            .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = depth_image,
            .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
            .format           = graphics_pipeline.depth_format,
            .subresourceRange = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_DEPTH_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
        });

        var framebuffers = try ArrayList(c.VkFramebuffer).init(allocator, @intCast(image_count));

        for (0..image_count) |i| {
            try framebuffers.push(try device.create_framebuffer(.{
                .sType           = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = graphics_pipeline.render_pass,
                .attachmentCount = 2,
                .pAttachments    = &[_]c.VkImageView {image_views.items[i], depth_image_view},
                .width           = extent.width,
                .height          = extent.height,
                .layers          = 1,
            }));
        }

        return .{
            .handle             = handle,
            .extent             = extent,
            .image_views        = image_views,
            .framebuffers       = framebuffers,
            .depth_image        = depth_image,
            .depth_image_view   = depth_image_view,
            .depth_image_memory = depth_image_memory,
            .allocator          = allocator,
            .force_redraw       = false,
        };
    }

    pub fn recreate(
        self:         *Swapchain,
        device:       Device,
        instance:     Instance,
        pipeline:     GraphicsPipeline,
        window:       Window,
        command_pool: *CommandPool,
    ) !void {
        while (true) {
            if (window.width == 0 or window.height == 0) {
            } else {
                break;
            }

            std.time.sleep(60 * Sync.default);
        }

        const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;
        const capabilities = try instance.get_physical_device_surface_capabilities(device.physical_device, window.surface);

        self.extent = if (capabilities.currentExtent.width != 0xFFFFFFFF) capabilities.currentExtent
        else .{
            .width  = std.math.clamp(window.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(window.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };

        const image_count = if (capabilities.maxImageCount > 0 and capabilities.minImageCount + 1 > capabilities.maxImageCount) capabilities.maxImageCount
        else capabilities.minImageCount + 1;

        var uniques_queue_family_index = try Device.Queue.uniques(&.{ device.queues[0].family, device.queues[1].family }, self.allocator);
        defer uniques_queue_family_index.deinit();

        const old_swapchain = self.handle;
        self.handle = try device.create_swapchain(.{
            .sType                 = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface               = window.surface,
            .minImageCount         = image_count,
            .imageFormat           = pipeline.format.format,
            .imageColorSpace       = pipeline.format.colorSpace,
            .imageExtent           = self.extent,
            .imageSharingMode      = if (uniques_queue_family_index.items.len == 1) c.VK_SHARING_MODE_EXCLUSIVE else c.VK_SHARING_MODE_CONCURRENT,
            .presentMode           = present_mode,
            .preTransform          = capabilities.currentTransform,
            .clipped               = c.VK_TRUE,
            .imageArrayLayers      = 1,
            .compositeAlpha        = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .imageUsage            = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .queueFamilyIndexCount = @as(u32, @intCast(uniques_queue_family_index.items.len)),
            .pQueueFamilyIndices   = uniques_queue_family_index.items.ptr,
            .oldSwapchain          = old_swapchain,
        });

        device.destroy_swapchain(old_swapchain);

        var images = try device.get_swapchain_images(self.handle, self.allocator);
        defer images.deinit();

        for (images.items, 0..) |image, i| {
            device.destroy_image_view(self.image_views.items[i]);
            self.image_views.items[i] = try device.create_image_view(.{
                .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image            = image,
                .format           = pipeline.format.format,
                .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
                .subresourceRange = .{
                    .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel   = 0,
                    .levelCount     = 1,
                    .baseArrayLayer = 0,
                    .layerCount     = 1,
                },
                .components         = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
            });
        }


        device.destroy_image(self.depth_image);
        self.depth_image = try device.create_image(.{
            .sType     = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .extent    = .{
                .width  = self.extent.width,
                .height = self.extent.height,
                .depth  = 1,
            },
            .mipLevels     = 1,
            .arrayLayers   = 1,
            .format        = pipeline.depth_format,
            .tiling        = c.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage         = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .samples       = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode   = c.VK_SHARING_MODE_EXCLUSIVE,
        });

        const image_memory_requirements = device.get_image_memory_requirements(self.depth_image);
        const memory_index = for (0..device.memory_properties.memoryTypeCount) |i| {
            if ((image_memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (device.memory_properties.memoryTypes[i].propertyFlags & c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) == c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
                break i;
            }
        } else return error.NoMemoryRequirementsPassed;

        device.free_memory(self.depth_image_memory);
        self.depth_image_memory = try device.allocate_memory(.{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = image_memory_requirements.size,
            .memoryTypeIndex = @intCast(memory_index),
        });

        try device.bind_image_memory(self.depth_image, self.depth_image_memory);

        device.destroy_image_view(self.depth_image_view);
        self.depth_image_view = try device.create_image_view(.{
            .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = self.depth_image,
            .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
            .format           = pipeline.depth_format,
            .subresourceRange = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_DEPTH_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
        });

        for (0..image_count) |i| {
            device.destroy_framebuffer(self.framebuffers.items[i]);
            self.framebuffers.items[i] = try device.create_framebuffer(.{
                .sType           = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = pipeline.render_pass,
                .attachmentCount = 2,
                .pAttachments    = &[_]c.VkImageView {self.image_views.items[i], self.depth_image_view},
                .width           = self.extent.width,
                .height          = self.extent.height,
                .layers          = 1,
            });
        }

        self.force_redraw = true;
        command_pool.invalidate_all();

        logger.log(.Debug, "Swapchain recreated", .{});
    }

    fn acquire_next_image(self: Swapchain, device: Device, sync: Sync) !u32 {
        return try device.acquire_next_image(self.handle, sync.image_available);
    }

    pub fn draw_next_frame(
        self:         *Swapchain,
        device:       Device,
        pipeline:     GraphicsPipeline,
        command_pool: *CommandPool,
        data:         Data,
        sync:         *Sync,
    ) !bool {
        self.draw_frame(device, pipeline, command_pool, data, sync) catch |e| {
            if(e == Result.SuboptimalKhr or e == Result.OutOfDateKhr) return true
            else return e;
        };

        return false;
    }

    fn draw_frame(
        self:         Swapchain,
        device:       Device,
        pipeline:     GraphicsPipeline,
        command_pool: *CommandPool,
        data:         Data,
        sync:         *Sync,
    ) !void {
        const image_index = try self.acquire_next_image(device, sync.*);

        if (!(command_pool.buffers.items[image_index].is_valid)) try command_pool.buffers.items[image_index].record(device, pipeline, self, data);

        sync.changed = true;
        try device.queue_submit(sync.in_flight_fence, .{
            .sType                = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount   = 1,
            .pWaitSemaphores      = &sync.image_available,
            .pWaitDstStageMask    = &@as(u32, @intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)),
            .commandBufferCount   = 1,
            .pCommandBuffers      = &command_pool.buffers.items[image_index].handle,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &sync.render_finished,
        });

        try device.queue_present(.{
            .sType                = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount   = 1,
            .pWaitSemaphores      = &sync.render_finished,
            .swapchainCount       = 1,
            .pSwapchains          = &self.handle,
            .pImageIndices        = &image_index,
            .pResults             = null,
        });
    }

    pub fn destroy(self: *Swapchain, device: Device) void {
        device.free_memory(self.depth_image_memory);

        for (self.image_views.items) |view| {
            device.destroy_image_view(view);
        }

        device.destroy_image_view(self.depth_image_view);
        device.destroy_image(self.depth_image);

        self.image_views.deinit();

        for (self.framebuffers.items) |framebuffer| {
            device.destroy_framebuffer(framebuffer);
        }

        self.framebuffers.deinit();
        device.destroy_swapchain(self.handle);
    }
};
