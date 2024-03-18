const std = @import("std");

const _config = @import("../../util/configuration.zig");
const _collections = @import("../../util/collections.zig");
const _platform = @import("../../platform/platform.zig");

const _result = @import("error.zig");
const _instance = @import("instance.zig");
const _device = @import("device.zig");
const _graphics_pipeline = @import("graphics_pipeline.zig");
const _window = @import("window.zig");
const _data = @import("data.zig");
const _command_pool = @import("command_pool.zig");
const _sync = @import("sync.zig");

const Instance = _instance.Instance;
const GraphicsPipeline = _graphics_pipeline.GraphicsPipeline;
const Device = _device.Device;
const Data = _data.Data;
const Window = _window.Window;
const CommandPool = _command_pool.CommandPool;
const Sync = _sync.Sync;
const Result = _result.Result;

const Platform = _platform.Platform;
const ArrayList = _collections.ArrayList;

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Swapchain = struct {
    handle: c.VkSwapchainKHR,
    extent: c.VkExtent2D,
    image_views: ArrayList(c.VkImageView),
    framebuffers: ArrayList(c.VkFramebuffer),
    depth_image_view: c.VkImageView,
    depth_image_memory: c.VkDeviceMemory,
    arena: std.heap.ArenaAllocator,
    force_redraw: bool = false,

    pub fn new(device: Device, opt_swapchain: ?Swapchain, instance: Instance, window: Window, graphics_pipeline: GraphicsPipeline) !Swapchain {
        var swapchain = blk: {
            if (opt_swapchain) |swapchain| {
                break :blk swapchain;
            } else {
                break :blk Swapchain {
                    .handle = null,
                    .extent = .{
                        .width = window.width,
                        .height = window.height,
                    },
                    .image_views = undefined,
                    .framebuffers = undefined,
                    .depth_image_view = undefined,
                    .depth_image_memory = undefined,
                    .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                };
            }
        };

        const allocator = swapchain.arena.allocator();
        const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;
        const capabilities = instance.get_physical_device_surface_capabilities(device.physical_device, window.surface) catch |e| {
            logger.log(.Error, "Could not access physical device capabilities", .{});

            return e;
        };

        swapchain.extent = blk: {
            if (capabilities.currentExtent.width != 0xFFFFFFFF) {
                break :blk capabilities.currentExtent;
            } else {
                break :blk .{
                    .width = std.math.clamp(window.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
                    .height = std.math.clamp(window.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
                };
            }
        };

        const image_count = blk: {
            if (capabilities.maxImageCount > 0 and capabilities.minImageCount + 1 > capabilities.maxImageCount) {
                break :blk capabilities.maxImageCount;
            } else {
                break :blk capabilities.minImageCount + 1;
            }
        };

        const uniques_queue_family_index = Device.Queue.uniques(&.{ device.queues[0].family, device.queues[1].family }, allocator) catch |e| {
            logger.log(.Error, "Failed to get uniques queue family index list", .{});

            return e;
        };

        const old_handle = swapchain.handle;
        swapchain.handle = device.create_swapchain(.{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = window.surface,
            .minImageCount = image_count,
            .imageFormat = graphics_pipeline.format.format,
            .imageColorSpace = graphics_pipeline.format.colorSpace,
            .imageExtent = swapchain.extent,
            .imageSharingMode = if (uniques_queue_family_index.items.len == 1) c.VK_SHARING_MODE_EXCLUSIVE else c.VK_SHARING_MODE_CONCURRENT,
            .presentMode = present_mode,
            .preTransform = capabilities.currentTransform,
            .clipped = c.VK_TRUE,
            .imageArrayLayers = 1,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .queueFamilyIndexCount = @as(u32, @intCast(uniques_queue_family_index.items.len)),
            .pQueueFamilyIndices = uniques_queue_family_index.items.ptr,
            .oldSwapchain = old_handle,
        }) catch |e| {
            logger.log(.Error, "Failed to create sawpchain", .{});

            return e;
        };

        device.destroy_swapchain(old_handle);

        const images = device.get_swapchain_images(swapchain.handle, allocator) catch |e| {
            logger.log(.Error, "Failed to get swapchain images", .{});

            return e;
        };

        swapchain.image_views = ArrayList(c.VkImageView).init(allocator, @intCast(images.len)) catch |e| {
            logger.log(.Error, "Could not allocate image views array", .{});

            return e;
        };

        for (0..images.len) |i| {
            swapchain.image_views.push(device.create_image_view(.{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = images[i],
                .format = graphics_pipeline.format.format,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
            }) catch |e| {
                logger.log(.Error, "Failed to get image view from image", .{});

                return e;
            }) catch |e| {
                logger.log(.Error, "Failed to insert element in image views", .{});

                return e;
            };
        }

        const depth_image = device.create_image(.{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .extent = .{
                .width = swapchain.extent.width,
                .height = swapchain.extent.height,
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = graphics_pipeline.depth_format,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        }) catch |e| {
            logger.log(.Error, "Failed to create image depth", .{});

            return e;
        };

        const memory_properties = instance.get_physical_device_memory_properties(device.physical_device);
        const image_memory_requirements = device.get_image_memory_requirements(depth_image);
        const memory_index = blk: for (0..memory_properties.memoryTypeCount) |i| {
            if ((image_memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (memory_properties.memoryTypes[i].propertyFlags & c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) == c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
                break :blk i;
            }
        } else {
            logger.log(.Error, "Could not find memory type that suit the need of buffer allocation", .{});

            return error.NoMemoryRequirementsPassed;
        };

        swapchain.depth_image_memory = device.allocate_memory(.{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = image_memory_requirements.size,
            .memoryTypeIndex = @intCast(memory_index),
        }) catch |e| {
            logger.log(.Error, "Failed to allocate depth image memory", .{});

            return e;
        };

        device.bind_image_memory(depth_image, swapchain.depth_image_memory) catch |e| {
            logger.log(.Error, "Failed to bind depth image memory", .{});

            return e;
        };

        swapchain.depth_image_view = device.create_image_view(.{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = depth_image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = graphics_pipeline.depth_format,
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        }) catch |e| {
            logger.log(.Error, "Failed to create depth image view", .{});

            return e;
        };

        swapchain.framebuffers = ArrayList(c.VkFramebuffer).init(allocator, @intCast(images.len)) catch {
            logger.log(.Error, "Failed to create framebuffers array",  .{});

            return error.OutOfMemory;
        };

        for (0..swapchain.image_views.items.len) |i| {
            try swapchain.framebuffers.push(device.create_framebuffer(.{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = graphics_pipeline.render_pass,
                .attachmentCount = 2,
                .pAttachments = &[_]c.VkImageView {swapchain.image_views.items[i], swapchain.depth_image_view},
                .width = swapchain.extent.width,
                .height = swapchain.extent.height,
                .layers = 1,
            }) catch |e| {
                logger.log(.Error, "Failed to crate frambuffer", .{});

                return e;
            });

        }


        return swapchain;
    }

    pub fn recreate(
        self: *Swapchain,
        device: Device,
        instance: Instance,
        pipeline: GraphicsPipeline,
        window: Window,
        command_pool: *CommandPool,
    ) !void {
        while (true) {
            if (window.width == 0 or window.height == 0) {
            } else {
                break;
            }

            std.time.sleep(60 * Sync.default);
        }

        self.* = try Swapchain.new(device, self.*, instance, window, pipeline);
        command_pool.invalidate_all();
    }

    fn acquire_next_image(self: Swapchain, device: Device, sync: Sync) !u32 {
        return try device.acquire_next_image(self.handle, sync.image_available);
    }

    pub fn draw_next_frame(
        self: *Swapchain,
        device: Device,
        instance: Instance,
        pipeline: GraphicsPipeline,
        window: *Window,
        command_pool: *CommandPool,
        data: Data,
        sync: *Sync,
    ) !bool {
        _ = window;
        _ = instance;

        self.draw_frame(device, pipeline, command_pool, data, sync.*) catch |e| {
            if(e == Result.SuboptimalKhr or e == Result.OutOfDateKhr) {

                return true;
            } else {
                return e;
            }
        };

        return false;
    }

    fn draw_frame(
        self: Swapchain,
        device: Device,
        pipeline: GraphicsPipeline,
        command_pool: *CommandPool,
        data: Data,
        sync: Sync,
    ) !void {
        const image_index = try self.acquire_next_image(device, sync);

        if (!(command_pool.buffers.items[image_index].is_valid)) {
            command_pool.buffers.items[image_index].record(device, pipeline, self, data) catch {
                return error.Else;
            };
        }

        try device.queue_submit(.{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &sync.image_available,
            .pWaitDstStageMask = &@as(u32, @intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)),
            .commandBufferCount = 1,
            .pCommandBuffers = &command_pool.buffers.items[image_index].handle,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &sync.render_finished,
        }, sync.in_flight_fence);

        try device.queue_present(.{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &sync.render_finished,
            .swapchainCount = 1,
            .pSwapchains = &self.handle,
            .pImageIndices = &image_index,
            .pResults = null,
        });
    }

    pub fn destroy(self: *Swapchain, device: Device, destroy_handle: bool) void {
        device.free_memory(self.depth_image_memory);
        device.destroy_image_view(self.depth_image_view);

        if (destroy_handle) {
            device.destroy_swapchain(self.handle);
        }

        _ = self.arena.reset(.free_all);
    }
};
