const std           = @import("std");

const _config       = @import("../../util/configuration.zig");
const _collections  = @import("../../collections/collections.zig");
const _platform     = @import("../../platform/platform.zig");

const _error        = @import("error.zig");
const _instance     = @import("instance.zig");

const Instance      = _instance.Instance;
const check         = _error.check;
const ArrayList     = _collections.ArrayList;
const Allocator     = std.mem.Allocator;

const c             = _platform.c;
const configuration = _config.Configuration;

const REQUIRED_DEVICE_EXTENSIONS = [_][*:0]const u8{ c.VK_KHR_SWAPCHAIN_EXTENSION_NAME };

pub const Device = struct {
    handle:            c.VkDevice,
    physical_device:   c.VkPhysicalDevice,
    memory_properties: c.VkPhysicalDeviceMemoryProperties,
    queues:            [4]Queue,

    pub const Queue = struct {
        handle: c.VkQueue,
        family: u32,

        pub fn uniques(queues: []const u32, allocator: Allocator) !ArrayList(u32) {
            var uniques_array = try ArrayList(u32).init(allocator, 1);

            try uniques_array.push(queues[0]);

            var size: u32 = 1;

            for (queues) |family| {
                for (0..size) |i| {
                    if (family == uniques_array.items[i]) break;
                } else {
                    try uniques_array.push(family);
                    size += 1;
                }
            }

            return uniques_array;
        }
    };

    const Type = enum {
        Other,
        IntegratedGpu,
        DiscreteGpu,
        VirtualGpu,
        Cpu,
    };

    pub fn new(instance: Instance, surface: c.VkSurfaceKHR, allocator: Allocator) !Device {
        var queue_families: [4]u32 = undefined;
        const physical_device = blk: {
            const physical_devices = try instance.enumerate_physical_devices(allocator);

            defer allocator.free(physical_devices);

            var points: u32 = 1;
            var p_device: ?c.VkPhysicalDevice = null;

            for (physical_devices) |physical_device| {
                var families: [4]?u32 = .{ null, null, null, null };
                const rating: u32 = rate: {
                    const extensions_properties = try instance.enumerate_device_extension_properties(physical_device, allocator);

                    defer allocator.free(extensions_properties);

                    ext: for (REQUIRED_DEVICE_EXTENSIONS) |extension| {
                        for (extensions_properties) |propertie| {
                            if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&propertie.extensionName, 0))) break :ext;
                        }
                    } else break :rate 0;

                    const surface_formats = instance.get_physical_device_surface_formats(physical_device, surface, allocator) catch break :rate 0;
                    defer allocator.free(surface_formats);

                    const present_formats = instance.get_physical_device_surface_present_modes(physical_device, surface, allocator) catch break :rate 0;
                    defer allocator.free(present_formats);

                    if (!(surface_formats.len > 0)) break :rate 0;
                    if (!(present_formats.len > 0)) break :rate 0;

                    const families_properties = try instance.get_physical_device_queue_family_properties(physical_device, allocator);

                    defer allocator.free(families_properties);

                    for (families_properties, 0..) |properties, i| {
                        const family: u32 = @intCast(i);

                        if (families[0] == null and (properties.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)) families[0] = family;
                        if (families[1] == null and try instance.get_physical_device_surface_support(physical_device, family, surface)) families[1] = family;
                        if (families[2] == null and (properties.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)) families[2] = family;
                        if (families[3] == null and (properties.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0)) families[3] = family;
                    }

                    for (families) |i| {
                        if (i) |_| {} else break :rate 0;
                    }

                    var sum: u8 = 1;

                    const physical_device_feats = instance.get_physical_device_features(physical_device);
                    const physical_device_props = instance.get_physical_device_properties(physical_device);

                    if (physical_device_feats.geometryShader    != 1) break :rate 0;
                    if (physical_device_feats.samplerAnisotropy != 1) break :rate 0;

                    sum += switch (physical_device_props.deviceType) {
                        @intFromEnum(Type.DiscreteGpu)   => 4,
                        @intFromEnum(Type.IntegratedGpu) => 3,
                        @intFromEnum(Type.VirtualGpu)    => 2,
                        @intFromEnum(Type.Other)         => 1,
                        else                             => 0,
                    };

                    break :rate sum;
                };

                if (rating >= points) {
                    points         = rating;
                    p_device       = physical_device;
                    queue_families = .{ families[0].?, families[1].?, families[2].?, families[3].? };
                }
            }

            if (p_device) |physical_device| {
                break :blk physical_device;
            } else return error.PhysicalDeviceNotFound;
        };

        var families = try Queue.uniques(&queue_families, allocator);
        defer families.deinit();

        var queue_create_infos: []c.VkDeviceQueueCreateInfo = try allocator.alloc(c.VkDeviceQueueCreateInfo, families.items.len);
        defer allocator.free(queue_create_infos);

        for (families.items, 0..) |family, i| {
            queue_create_infos[i] = .{
                .sType            = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = family,
                .queueCount       = 1,
                .pQueuePriorities = &[_]f32{1.0},
            };
        }

        const device = try instance.create_device(physical_device,
            .{
                .sType                   = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .queueCreateInfoCount    = @as(u32, @intCast(queue_create_infos.len)),
                .pQueueCreateInfos       = queue_create_infos.ptr,
                .pEnabledFeatures        = &instance.get_physical_device_features(physical_device),
                .enabledExtensionCount   = @as(u32, @intCast(REQUIRED_DEVICE_EXTENSIONS.len)),
                .ppEnabledExtensionNames = &REQUIRED_DEVICE_EXTENSIONS[0],
            }
        );

        try populate_device_functions(device, instance.handle);

        var queues: [4]Queue = .{
            .{ .family = queue_families[0], .handle = undefined },
            .{ .family = queue_families[1], .handle = undefined },
            .{ .family = queue_families[2], .handle = undefined },
            .{ .family = queue_families[3], .handle = undefined },
        };

        for (0..queues.len) |i| vkGetDeviceQueue(device, queues[i].family, 0, &queues[i].handle);

        return .{
            .handle            = device,
            .queues            = queues,
            .physical_device   = physical_device,
            .memory_properties = instance.get_physical_device_memory_properties(physical_device),
        };
    }

    pub fn get_swapchain_images(self: Device, swapchain: c.VkSwapchainKHR, allocator: Allocator) !ArrayList(c.VkImage) {
        var count: u32 = undefined;

        try check(vkGetSwapchainImagesKHR(self.handle, swapchain, &count, null));

        var images       = try ArrayList(c.VkImage).init(allocator, count);
        images.items.len = count;

        try check(vkGetSwapchainImagesKHR(self.handle, swapchain, &count, images.items.ptr));

        return images;
    }

    pub fn get_image_memory_requirements(self: Device, image: c.VkImage) c.VkMemoryRequirements {
        var requirements: c.VkMemoryRequirements = undefined;
        vkGetImageMemoryRequirements(self.handle, image, &requirements);

        return requirements;
    }

    pub fn get_buffer_memory_requirements(self: Device, buffer: c.VkBuffer) c.VkMemoryRequirements {
        var requirements: c.VkMemoryRequirements = undefined;
        vkGetBufferMemoryRequirements(self.handle, buffer, &requirements);

        return requirements;
    }

    pub fn bind_buffer_memory(self: Device, buffer: c.VkBuffer, memory: c.VkDeviceMemory) !void {
        try check(vkBindBufferMemory(self.handle, buffer, memory, 0));
    }

    pub fn bind_image_memory(self: Device, image: c.VkImage, memory: c.VkDeviceMemory) !void {
        try check(vkBindImageMemory(self.handle, image, memory, 0));
    }

    pub fn create_image(self: Device, info: c.VkImageCreateInfo) !c.VkImage {
        var image: c.VkImage = undefined;
        try check(vkCreateImage(self.handle, &info, null, &image));

        return image;
    }

    pub fn create_image_view(self: Device, info: c.VkImageViewCreateInfo) !c.VkImageView {
        var view: c.VkImageView = undefined;
        try check(vkCreateImageView(self.handle, &info, null, &view));

        return view;
    }

    pub fn create_swapchain(self: Device, info: c.VkSwapchainCreateInfoKHR) !c.VkSwapchainKHR {
        var handle: c.VkSwapchainKHR = undefined;
        try check(vkCreateSwapchainKHR(self.handle, &info, null, &handle));

        return handle;
    }
    pub fn create_shader_module(self: Device, info: c.VkShaderModuleCreateInfo) !c.VkShaderModule {
        var shader_module: c.VkShaderModule = undefined;
        try check(vkCreateShaderModule(self.handle, &info, null, &shader_module));

        return shader_module;
    }

    pub fn create_pipeline_layout(self: Device, info: c.VkPipelineLayoutCreateInfo) !c.VkPipelineLayout {
        var layout: c.VkPipelineLayout = undefined;
        try check(vkCreatePipelineLayout(self.handle, &info, null, &layout));

        return layout;
    }

    pub fn create_descriptor_pool(self: Device, info: c.VkDescriptorPoolCreateInfo) !c.VkDescriptorPool {
        var pool: c.VkDescriptorPool = undefined;
        try check(vkCreateDescriptorPool(self.handle, &info, null, &pool));

        return pool;
    }

    pub fn create_graphics_pipeline(self: Device, info: c.VkGraphicsPipelineCreateInfo) !c.VkPipeline {
        var pipeline: c.VkPipeline = undefined;

        try check(vkCreateGraphicsPipelines(self.handle, null, 1, &info, null, &pipeline));

        return pipeline;
    }

    pub fn create_render_pass(self: Device, info: c.VkRenderPassCreateInfo) !c.VkRenderPass {
        var render_pass: c.VkRenderPass = undefined;
        try check(vkCreateRenderPass(self.handle, &info, null, &render_pass));

        return render_pass;
    }

    pub fn create_framebuffer(self: Device, info: c.VkFramebufferCreateInfo) !c.VkFramebuffer {
        var framebuffer: c.VkFramebuffer = undefined;
        try check(vkCreateFramebuffer(self.handle, &info, null, &framebuffer));

        return framebuffer;
    }

    pub fn create_command_pool(self: Device, info: c.VkCommandPoolCreateInfo) !c.VkCommandPool {
        var command_pool: c.VkCommandPool = undefined;
        try check(vkCreateCommandPool(self.handle, &info, null, &command_pool));

        return command_pool;
    }

    pub fn create_semaphore(self: Device, info: c.VkSemaphoreCreateInfo) !c.VkSemaphore {
        var semaphore: c.VkSemaphore = undefined;
        try check(vkCreateSemaphore(self.handle, &info, null, &semaphore));

        return semaphore;
    }

    pub fn create_fence(self: Device, info: c.VkFenceCreateInfo) !c.VkFence {
        var fence: c.VkFence = undefined;
        try check(vkCreateFence(self.handle, &info, null, &fence));

        return fence;
    }

    pub fn create_buffer(self: Device, info: c.VkBufferCreateInfo) !c.VkBuffer {
        var buffer: c.VkBuffer = undefined;
        try check(vkCreateBuffer(self.handle, &info, null, &buffer));

        return buffer;
    }

    pub fn create_descriptor_set_layout(self: Device, info: c.VkDescriptorSetLayoutCreateInfo) !c.VkDescriptorSetLayout {
        var desc: c.VkDescriptorSetLayout = undefined;
        try check(vkCreateDescriptorSetLayout(self.handle, &info, null, &desc));

        return desc;
    }

    pub fn map_memory(self: Device, memory: c.VkDeviceMemory, comptime T: type, len: usize, dst: *?*anyopaque) !void {
        try check(vkMapMemory(self.handle, memory, 0, len * @sizeOf(T), 0, dst));
    }

    pub fn unmap_memory(self: Device, memory: c.VkDeviceMemory) void {
        vkUnmapMemory(self.handle, memory);
    }

    pub fn wait_for_fences(self: Device, fence: *c.VkFence) !void {
        const MAX: u64 = 0xFFFFFF;
        try check(vkWaitForFences(self.handle, 1, fence, c.VK_TRUE, MAX));
    }

    pub fn reset_fences(self: Device, fence: *c.VkFence) !void {
        try check(vkResetFences(self.handle, 1, fence));
    }

    pub fn allocate_command_buffers(self: Device, allocator: Allocator, info: c.VkCommandBufferAllocateInfo) ![]c.VkCommandBuffer {
        var command_buffers = try allocator.alloc(c.VkCommandBuffer, info.commandBufferCount);
        try check(vkAllocateCommandBuffers(self.handle, &info, &command_buffers[0]));

        return command_buffers;
    }

    pub fn allocate_descriptor_sets(self: Device, info: c.VkDescriptorSetAllocateInfo, allocator: Allocator) ![]c.VkDescriptorSet {
        var descriptor = try allocator.alloc(c.VkDescriptorSet, info.descriptorSetCount);
        try check(vkAllocateDescriptorSets(self.handle, &info, &descriptor[0]));

        return descriptor;
    }

    pub fn allocate_memory(self: Device, info: c.VkMemoryAllocateInfo) !c.VkDeviceMemory {
        var memory: c.VkDeviceMemory = undefined;
        try check(vkAllocateMemory(self.handle, &info, null, &memory));

        return memory;
    }

    pub fn acquire_next_image(self: Device, swapchain: c.VkSwapchainKHR, semaphore: c.VkSemaphore) !u32 {
        const MAX: u64 = 0xFFFFFFFFFFFFFFFF;
        var index: u32 = undefined;

        try check(vkAcquireNextImageKHR(self.handle, swapchain, MAX, semaphore, null, &index));

        return index;
    }

    pub fn queue_submit(self: Device, fence: c.VkFence, info: c.VkSubmitInfo) !void {
        try check(vkQueueSubmit(self.queues[0].handle, 1, &info, fence));
    }

    pub fn queue_present(self: Device, info: c.VkPresentInfoKHR) !void {
        try check(vkQueuePresentKHR(self.queues[1].handle, &info));
    }

    pub fn queue_wait_idle(_: Device, queue: c.VkQueue) !void {
        try check(vkQueueWaitIdle(queue));
    }

    pub fn begin_command_buffer(_: Device, command_buffer: c.VkCommandBuffer, info: c.VkCommandBufferBeginInfo) !void {
        try check(vkBeginCommandBuffer(command_buffer, &info));
    }

    pub fn cmd_begin_render_pass(_: Device, command_buffer: c.VkCommandBuffer, info: c.VkRenderPassBeginInfo) void {
        vkCmdBeginRenderPass(command_buffer, &info, c.VK_SUBPASS_CONTENTS_INLINE);
    }

    pub fn cmd_bind_pipeline(_: Device, command_buffer: c.VkCommandBuffer, pipeline: c.VkPipeline) void {
        vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    }

    pub fn cmd_bind_vertex_buffer(_: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
        vkCmdBindVertexBuffers(command_buffer, 0, 1, &buffer, &0);
    }

    pub fn cmd_bind_index_buffer(_: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
        vkCmdBindIndexBuffer(command_buffer, buffer, 0, c.VK_INDEX_TYPE_UINT16);
    }

    pub fn cmd_set_viewport(_: Device, command_buffer: c.VkCommandBuffer, viewport: c.VkViewport) void {
        vkCmdSetViewport(command_buffer, 0, 1, &viewport);
    }

    pub fn cmd_set_scissor(_: Device, command_buffer: c.VkCommandBuffer, scissor: c.VkRect2D) void {
        vkCmdSetScissor(command_buffer, 0, 1, &scissor);
    }

    pub fn cmd_copy_buffer(_: Device, command_buffer: c.VkCommandBuffer, src: c.VkBuffer, dst: c.VkBuffer, copy: c.VkBufferCopy) void {
        vkCmdCopyBuffer(command_buffer, src, dst, 1, &copy);
    }

    pub fn cmd_draw(_: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
        vkCmdDraw(command_buffer, size, 1, 0, 0);
    }

    pub fn cmd_draw_indexed(_: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
        vkCmdDrawIndexed(command_buffer, size, 1, 0, 0, 0);
    }

    pub fn cmd_bind_descriptor_sets(_: Device, command_buffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, first: u32, count: u32, descriptor_sets: []const c.VkDescriptorSet, offsets: ?[]const u32) void {
        const len: u32 = if (offsets) |o| @as(u32, @intCast(o.len)) else 0;
        vkCmdBindDescriptorSets(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, layout, first, count, descriptor_sets.ptr, len, @ptrCast(offsets));
    }

    pub fn cmd_push_constants(_: Device, command_buffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, offset: u32, size: u32, value: ?*const anyopaque) void {
        vkCmdPushConstants(command_buffer, layout, c.VK_SHADER_STAGE_VERTEX_BIT, offset, size, value);
    }

    pub fn update_descriptor_sets(self: Device, write: c.VkWriteDescriptorSet) void {
        vkUpdateDescriptorSets(self.handle, 1, &write, 0, null);
    }

    pub fn end_render_pass(_: Device, command_buffer: c.VkCommandBuffer) void {
        vkCmdEndRenderPass(command_buffer);
    }

    pub fn end_command_buffer(_: Device, command_buffer: c.VkCommandBuffer) !void {
        try check(vkEndCommandBuffer(command_buffer));
    }

    pub fn reset_command_buffer(_: Device, command_buffer: c.VkCommandBuffer) !void {
        try check(vkResetCommandBuffer(command_buffer, 0));
    }

    pub fn destroy_command_pool(self: Device, command_pool: c.VkCommandPool) void {
        vkDestroyCommandPool(self.handle, command_pool, null);
    }

    pub fn destroy_swapchain(self: Device, swapchain: c.VkSwapchainKHR) void {
        vkDestroySwapchainKHR(self.handle, swapchain, null);
    }

    pub fn destroy_shader_module(self: Device, shader_module: c.VkShaderModule) void {
        vkDestroyShaderModule(self.handle, shader_module, null);
    }

    pub fn destroy_pipeline(self: Device, pipeline: c.VkPipeline) void {
        vkDestroyPipeline(self.handle, pipeline, null);
    }

    pub fn destroy_pipeline_layout(self: Device, pipeline_layout: c.VkPipelineLayout) void {
        vkDestroyPipelineLayout(self.handle, pipeline_layout, null);
    }

    pub fn destroy_render_pass(self: Device, render_pass: c.VkRenderPass) void {
        vkDestroyRenderPass(self.handle, render_pass, null);
    }

    pub fn destroy_semaphore(self: Device, semaphore: c.VkSemaphore) void {
        vkDestroySemaphore(self.handle, semaphore, null);
    }

    pub fn destroy_fence(self: Device, fence: c.VkFence) void {
        vkDestroyFence(self.handle, fence, null);
    }

    pub fn destroy_image(self: Device, image: c.VkImage) void {
        vkDestroyImage(self.handle, image, null);
    }

    pub fn destroy_image_view(self: Device, image_view: c.VkImageView) void {
        vkDestroyImageView(self.handle, image_view, null);
    }

    pub fn destroy_framebuffer(self: Device, framebuffer: c.VkFramebuffer) void {
        vkDestroyFramebuffer(self.handle, framebuffer, null);
    }

    pub fn destroy_buffer(self: Device, buffer: c.VkBuffer) void {
        vkDestroyBuffer(self.handle, buffer, null);
    }

    pub fn destroy_descriptor_set_layout(self: Device, layout: c.VkDescriptorSetLayout) void {
        vkDestroyDescriptorSetLayout(self.handle, layout, null);
    }

    pub fn destroy_descriptor_pool(self: Device, pool: c.VkDescriptorPool) void {
        vkDestroyDescriptorPool(self.handle, pool, null);
    }

    pub fn free_memory(self: Device, memory: c.VkDeviceMemory) void {
        vkFreeMemory(self.handle, memory, null);
    }

    pub fn free_command_buffer(self: Device, command_pool: c.VkCommandPool, command_buffer: c.VkCommandBuffer) void {
        vkFreeCommandBuffers(self.handle, command_pool, 1, &command_buffer);
    }

    pub fn free_descriptor_sets(self: Device, descriptor_pool: c.VkDescriptorPool, n: usize, descriptor_sets: []const c.VkDescriptorSet) !void {
        try check(vkFreeDescriptorSets(self.handle, descriptor_pool, @intCast(n), &descriptor_sets[0]));
    }

    pub fn destroy(self: Device) void {
        vkDestroyDevice(self.handle, null);
    }
};

pub fn populate_device_functions(device: c.VkDevice, instance: c.VkInstance) !void {
    const vkGetDeviceProcAddr = try _platform.get_device_procaddr(instance);

    vkAllocateCommandBuffers       = @as(c.PFN_vkAllocateCommandBuffers, @ptrCast(vkGetDeviceProcAddr(device, "vkAllocateCommandBuffers"))) orelse return error.FunctionNotFound;
    vkAllocateMemory               = @as(c.PFN_vkAllocateMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkAllocateMemory"))) orelse return error.FunctionNotFound;
    vkAllocateDescriptorSets       = @as(c.PFN_vkAllocateDescriptorSets, @ptrCast(vkGetDeviceProcAddr(device, "vkAllocateDescriptorSets"))) orelse return error.FunctionNotFound;
    vkGetDeviceQueue               = @as(c.PFN_vkGetDeviceQueue, @ptrCast(vkGetDeviceProcAddr(device, "vkGetDeviceQueue"))) orelse return error.FunctionNotFound;
    vkQueueSubmit                  = @as(c.PFN_vkQueueSubmit, @ptrCast(vkGetDeviceProcAddr(device, "vkQueueSubmit"))) orelse return error.FunctionNotFound;
    vkQueuePresentKHR              = @as(c.PFN_vkQueuePresentKHR, @ptrCast(vkGetDeviceProcAddr(device, "vkQueuePresentKHR"))) orelse return error.FunctionNotFound;
    vkQueueWaitIdle                = @as(c.PFN_vkQueueWaitIdle, @ptrCast(vkGetDeviceProcAddr(device, "vkQueueWaitIdle"))) orelse return error.FunctionNotFound;
    vkGetSwapchainImagesKHR        = @as(c.PFN_vkGetSwapchainImagesKHR, @ptrCast(vkGetDeviceProcAddr(device, "vkGetSwapchainImagesKHR"))) orelse return error.FunctionNotFound;
    vkGetImageMemoryRequirements   = @as(c.PFN_vkGetImageMemoryRequirements, @ptrCast(vkGetDeviceProcAddr(device, "vkGetImageMemoryRequirements"))) orelse return error.FunctionNotFound;
    vkGetBufferMemoryRequirements  = @as(c.PFN_vkGetBufferMemoryRequirements, @ptrCast(vkGetDeviceProcAddr(device, "vkGetBufferMemoryRequirements"))) orelse return error.FunctionNotFound;
    vkBindBufferMemory             = @as(c.PFN_vkBindBufferMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkBindBufferMemory"))) orelse return error.FunctionNotFound;
    vkBindImageMemory              = @as(c.PFN_vkBindImageMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkBindImageMemory"))) orelse return error.FunctionNotFound;
    vkAcquireNextImageKHR          = @as(c.PFN_vkAcquireNextImageKHR, @ptrCast(vkGetDeviceProcAddr(device, "vkAcquireNextImageKHR"))) orelse return error.FunctionNotFound;
    vkWaitForFences                = @as(c.PFN_vkWaitForFences, @ptrCast(vkGetDeviceProcAddr(device, "vkWaitForFences"))) orelse return error.FunctionNotFound;
    vkResetFences                  = @as(c.PFN_vkResetFences, @ptrCast(vkGetDeviceProcAddr(device, "vkResetFences"))) orelse return error.FunctionNotFound;
    vkCreateSwapchainKHR           = @as(c.PFN_vkCreateSwapchainKHR, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateSwapchainKHR"))) orelse return error.FunctionNotFound;
    vkCreateImage                  = @as(c.PFN_vkCreateImage, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateImage"))) orelse return error.FunctionNotFound;
    vkCreateImageView              = @as(c.PFN_vkCreateImageView, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateImageView"))) orelse return error.FunctionNotFound;
    vkCreateShaderModule           = @as(c.PFN_vkCreateShaderModule, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateShaderModule"))) orelse return error.FunctionNotFound;
    vkCreatePipelineLayout         = @as(c.PFN_vkCreatePipelineLayout, @ptrCast(vkGetDeviceProcAddr(device, "vkCreatePipelineLayout"))) orelse return error.FunctionNotFound;
    vkCreateRenderPass             = @as(c.PFN_vkCreateRenderPass, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateRenderPass"))) orelse return error.FunctionNotFound;
    vkCreateGraphicsPipelines      = @as(c.PFN_vkCreateGraphicsPipelines, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateGraphicsPipelines"))) orelse return error.FunctionNotFound;
    vkCreateFramebuffer            = @as(c.PFN_vkCreateFramebuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateFramebuffer"))) orelse return error.FunctionNotFound;
    vkCreateCommandPool            = @as(c.PFN_vkCreateCommandPool, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateCommandPool"))) orelse return error.FunctionNotFound;
    vkCreateSemaphore              = @as(c.PFN_vkCreateSemaphore, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateSemaphore"))) orelse return error.FunctionNotFound;
    vkCreateFence                  = @as(c.PFN_vkCreateFence, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateFence"))) orelse return error.FunctionNotFound;
    vkCreateBuffer                 = @as(c.PFN_vkCreateBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateBuffer"))) orelse return error.FunctionNotFound;
    vkCreateDescriptorSetLayout    = @as(c.PFN_vkCreateDescriptorSetLayout, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateDescriptorSetLayout"))) orelse return error.FunctionNotFound;
    vkDestroyCommandPool           = @as(c.PFN_vkDestroyCommandPool, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyCommandPool"))) orelse return error.FunctionNotFound;
    vkCreateDescriptorPool         = @as(c.PFN_vkCreateDescriptorPool, @ptrCast(vkGetDeviceProcAddr(device, "vkCreateDescriptorPool"))) orelse return error.FunctionNotFound;
    vkDestroyPipeline              = @as(c.PFN_vkDestroyPipeline, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyPipeline"))) orelse return error.FunctionNotFound;
    vkDestroyPipelineLayout        = @as(c.PFN_vkDestroyPipelineLayout, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyPipelineLayout"))) orelse return error.FunctionNotFound;
    vkDestroyRenderPass            = @as(c.PFN_vkDestroyRenderPass, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyRenderPass"))) orelse return error.FunctionNotFound;
    vkDestroySwapchainKHR          = @as(c.PFN_vkDestroySwapchainKHR, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroySwapchainKHR"))) orelse return error.FunctionNotFound;
    vkDestroyImage                 = @as(c.PFN_vkDestroyImage, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyImage"))) orelse return error.FunctionNotFound;
    vkDestroyImageView             = @as(c.PFN_vkDestroyImageView, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyImageView"))) orelse return error.FunctionNotFound;
    vkDestroyShaderModule          = @as(c.PFN_vkDestroyShaderModule, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyShaderModule"))) orelse return error.FunctionNotFound;
    vkDestroySemaphore             = @as(c.PFN_vkDestroySemaphore, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroySemaphore"))) orelse return error.FunctionNotFound;
    vkDestroyFence                 = @as(c.PFN_vkDestroyFence, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyFence"))) orelse return error.FunctionNotFound;
    vkDestroyFramebuffer           = @as(c.PFN_vkDestroyFramebuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyFramebuffer"))) orelse return error.FunctionNotFound;
    vkDestroyBuffer                = @as(c.PFN_vkDestroyBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyBuffer"))) orelse return error.FunctionNotFound;
    vkDestroyDescriptorSetLayout   = @as(c.PFN_vkDestroyDescriptorSetLayout, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyDescriptorSetLayout"))) orelse return error.FunctionNotFound;
    vkDestroyDescriptorPool        = @as(c.PFN_vkDestroyDescriptorPool, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyDescriptorPool"))) orelse return error.FunctionNotFound;
    vkBeginCommandBuffer           = @as(c.PFN_vkBeginCommandBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkBeginCommandBuffer"))) orelse return error.FunctionNotFound;
    vkCmdBeginRenderPass           = @as(c.PFN_vkCmdBeginRenderPass, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdBeginRenderPass"))) orelse return error.FunctionNotFound;
    vkCmdBindPipeline              = @as(c.PFN_vkCmdBindPipeline, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdBindPipeline"))) orelse return error.FunctionNotFound;
    vkCmdBindVertexBuffers         = @as(c.PFN_vkCmdBindVertexBuffers, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdBindVertexBuffers"))) orelse return error.FunctionNotFound;
    vkCmdBindIndexBuffer           = @as(c.PFN_vkCmdBindIndexBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdBindIndexBuffer"))) orelse return error.FunctionNotFound;
    vkCmdSetViewport               = @as(c.PFN_vkCmdSetViewport, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdSetViewport"))) orelse return error.FunctionNotFound;
    vkCmdSetScissor                = @as(c.PFN_vkCmdSetScissor, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdSetScissor"))) orelse return error.FunctionNotFound;
    vkCmdDraw                      = @as(c.PFN_vkCmdDraw, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdDraw"))) orelse return error.FunctionNotFound;
    vkCmdDrawIndexed               = @as(c.PFN_vkCmdDrawIndexed, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdDrawIndexed"))) orelse return error.FunctionNotFound;
    vkCmdCopyBuffer                = @as(c.PFN_vkCmdCopyBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdCopyBuffer"))) orelse return error.FunctionNotFound;
    vkCmdPushConstants             = @as(c.PFN_vkCmdPushConstants, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdPushConstants"))) orelse return error.FunctionNotFound;
    vkUpdateDescriptorSets         = @as(c.PFN_vkUpdateDescriptorSets, @ptrCast(vkGetDeviceProcAddr(device, "vkUpdateDescriptorSets"))) orelse return error.FunctionNotFound;
    vkCmdBindDescriptorSets        = @as(c.PFN_vkCmdBindDescriptorSets, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdBindDescriptorSets"))) orelse return error.FunctionNotFound;
    vkCmdEndRenderPass             = @as(c.PFN_vkCmdEndRenderPass, @ptrCast(vkGetDeviceProcAddr(device, "vkCmdEndRenderPass"))) orelse return error.FunctionNotFound;
    vkEndCommandBuffer             = @as(c.PFN_vkEndCommandBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkEndCommandBuffer"))) orelse return error.FunctionNotFound;
    vkResetCommandBuffer           = @as(c.PFN_vkResetCommandBuffer, @ptrCast(vkGetDeviceProcAddr(device, "vkResetCommandBuffer"))) orelse return error.FunctionNotFound;
    vkFreeMemory                   = @as(c.PFN_vkFreeMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkFreeMemory"))) orelse return error.FunctionNotFound;
    vkFreeCommandBuffers           = @as(c.PFN_vkFreeCommandBuffers, @ptrCast(vkGetDeviceProcAddr(device, "vkFreeCommandBuffers"))) orelse return error.FunctionNotFound;
    vkFreeDescriptorSets           = @as(c.PFN_vkFreeDescriptorSets, @ptrCast(vkGetDeviceProcAddr(device, "vkFreeDescriptorSets"))) orelse return error.FunctionNotFound;
    vkMapMemory                    = @as(c.PFN_vkMapMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkMapMemory"))) orelse return error.FunctionNotFound;
    vkUnmapMemory                  = @as(c.PFN_vkUnmapMemory, @ptrCast(vkGetDeviceProcAddr(device, "vkUnmapMemory"))) orelse return error.FunctionNotFound;
    vkDestroyDevice                = @as(c.PFN_vkDestroyDevice, @ptrCast(vkGetDeviceProcAddr(device, "vkDestroyDevice"))) orelse return error.FunctionNotFound;
}

var vkGetDeviceQueue:              *const fn (c.VkDevice, u32, u32, *c.VkQueue) callconv(.C) void = undefined;
var vkAllocateCommandBuffers:      *const fn (c.VkDevice, *const c.VkCommandBufferAllocateInfo, *c.VkCommandBuffer) callconv(.C) i32 = undefined;
var vkAllocateMemory:              *const fn (c.VkDevice, *const c.VkMemoryAllocateInfo, ?*const c.VkAllocationCallbacks, *c.VkDeviceMemory) callconv(.C) i32 = undefined;
var vkAllocateDescriptorSets:      *const fn (c.VkDevice, *const c.VkDescriptorSetAllocateInfo, *c.VkDescriptorSet) callconv(.C) i32 = undefined;
var vkQueueSubmit:                 *const fn (c.VkQueue, u32, *const c.VkSubmitInfo, c.VkFence) callconv(.C) i32 = undefined;
var vkQueuePresentKHR:             *const fn (c.VkQueue, *const c.VkPresentInfoKHR) callconv(.C) i32 = undefined;
var vkQueueWaitIdle:               *const fn (c.VkQueue) callconv(.C) i32 = undefined;
var vkGetImageMemoryRequirements:  *const fn (c.VkDevice, c.VkImage, *c.VkMemoryRequirements) callconv(.C) void = undefined;
var vkGetSwapchainImagesKHR:       *const fn (c.VkDevice, c.VkSwapchainKHR, *u32, ?[*]c.VkImage) callconv(.C) i32 = undefined;
var vkGetBufferMemoryRequirements: *const fn (c.VkDevice, c.VkBuffer, *c.VkMemoryRequirements) callconv(.C) void = undefined;
var vkBindBufferMemory:            *const fn (c.VkDevice, c.VkBuffer, c.VkDeviceMemory, u64) callconv(.C) i32 = undefined;
var vkBindImageMemory:             *const fn (c.VkDevice, c.VkImage, c.VkDeviceMemory, u64) callconv(.C) i32 = undefined;
var vkAcquireNextImageKHR:         *const fn (c.VkDevice, c.VkSwapchainKHR, u64, c.VkSemaphore, c.VkFence, *u32) callconv(.C) i32 = undefined;
var vkWaitForFences:               *const fn (c.VkDevice, u32, *const c.VkFence, u32, u64) callconv(.C) i32 = undefined;
var vkResetFences:                 *const fn (c.VkDevice, u32, *const c.VkFence) callconv(.C) i32 = undefined;
var vkCreateSwapchainKHR:          *const fn (c.VkDevice, *const c.VkSwapchainCreateInfoKHR, ?*const c.VkAllocationCallbacks, *c.VkSwapchainKHR) callconv(.C) i32 = undefined;
var vkCreateImage:                 *const fn (c.VkDevice, *const c.VkImageCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkImage) callconv(.C) i32 = undefined;
var vkCreateShaderModule:          *const fn (c.VkDevice, *const c.VkShaderModuleCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkShaderModule) callconv(.C) i32 = undefined;
var vkCreatePipelineLayout:        *const fn (c.VkDevice, *const c.VkPipelineLayoutCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkPipelineLayout) callconv(.C) i32 = undefined;
var vkCreateImageView:             *const fn (c.VkDevice, *const c.VkImageViewCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkImageView) callconv(.C) i32 = undefined;
var vkCreateRenderPass:            *const fn (c.VkDevice, *const c.VkRenderPassCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkRenderPass) callconv(.C) i32 = undefined;
var vkCreateGraphicsPipelines:     *const fn (c.VkDevice, c.VkPipelineCache, u32, *const c.VkGraphicsPipelineCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkPipeline) callconv(.C) i32 = undefined;
var vkCreateFramebuffer:           *const fn (c.VkDevice, *const c.VkFramebufferCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkFramebuffer) callconv(.C) i32 = undefined;
var vkCreateCommandPool:           *const fn (c.VkDevice, *const c.VkCommandPoolCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkCommandPool) callconv(.C) i32 = undefined;
var vkCreateSemaphore:             *const fn (c.VkDevice, *const c.VkSemaphoreCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkSemaphore) callconv(.C) i32 = undefined;
var vkCreateFence:                 *const fn (c.VkDevice, *const c.VkFenceCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkFence) callconv(.C) i32 = undefined;
var vkCreateBuffer:                *const fn (c.VkDevice, *const c.VkBufferCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkBuffer) callconv(.C) i32 = undefined;
var vkCreateDescriptorSetLayout:   *const fn (c.VkDevice, *const c.VkDescriptorSetLayoutCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkDescriptorSetLayout) callconv(.C) i32 = undefined;
var vkCreateDescriptorPool:        *const fn (c.VkDevice, *const c.VkDescriptorPoolCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkDescriptorPool) callconv(.C) i32 = undefined;
var vkDestroyCommandPool:          *const fn (c.VkDevice, c.VkCommandPool, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyPipeline:             *const fn (c.VkDevice, c.VkPipeline, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyPipelineLayout:       *const fn (c.VkDevice, c.VkPipelineLayout, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyRenderPass:           *const fn (c.VkDevice, c.VkRenderPass, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyImage:                *const fn (c.VkDevice, c.VkImage, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyImageView:            *const fn (c.VkDevice, c.VkImageView, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroySwapchainKHR:         *const fn (c.VkDevice, c.VkSwapchainKHR, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyShaderModule:         *const fn (c.VkDevice, c.VkShaderModule, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroySemaphore:            *const fn (c.VkDevice, c.VkSemaphore, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyFence:                *const fn (c.VkDevice, c.VkFence, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyFramebuffer:          *const fn (c.VkDevice, c.VkFramebuffer, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyBuffer:               *const fn (c.VkDevice, c.VkBuffer, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyDescriptorSetLayout:  *const fn (c.VkDevice, c.VkDescriptorSetLayout, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyDescriptorPool:       *const fn (c.VkDevice, c.VkDescriptorPool, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkBeginCommandBuffer:          *const fn (c.VkCommandBuffer, *const c.VkCommandBufferBeginInfo) callconv(.C) i32 = undefined;
var vkCmdBeginRenderPass:          *const fn (c.VkCommandBuffer, *const c.VkRenderPassBeginInfo, c.VkSubpassContents) callconv(.C) void = undefined;
var vkCmdBindPipeline:             *const fn (c.VkCommandBuffer, c.VkPipelineBindPoint, c.VkPipeline) callconv(.C) void = undefined;
var vkCmdBindVertexBuffers:        *const fn (c.VkCommandBuffer, u32, u32, *const c.VkBuffer, *const u64) callconv(.C) void = undefined;
var vkCmdBindIndexBuffer:          *const fn (c.VkCommandBuffer, c.VkBuffer, u64, c.VkIndexType) callconv(.C) void = undefined;
var vkCmdSetViewport:              *const fn (c.VkCommandBuffer, u32, u32, *const c.VkViewport) callconv(.C) void = undefined;
var vkCmdSetScissor:               *const fn (c.VkCommandBuffer, u32, u32, *const c.VkRect2D) callconv(.C) void = undefined;
var vkCmdCopyBuffer:               *const fn (c.VkCommandBuffer, c.VkBuffer, c.VkBuffer, u32, *const c.VkBufferCopy) callconv(.C) void = undefined;
var vkCmdDraw:                     *const fn (c.VkCommandBuffer, u32, u32, u32, u32) callconv(.C) void = undefined;
var vkCmdDrawIndexed:              *const fn (c.VkCommandBuffer, u32, u32, u32, i32, u32) callconv(.C) void = undefined;
var vkCmdPushConstants:            *const fn (c.VkCommandBuffer, c.VkPipelineLayout, c.VkShaderStageFlags, u32, u32, ?*const anyopaque) callconv(.C) void = undefined;
var vkUpdateDescriptorSets:        *const fn (c.VkDevice, u32, *const c.VkWriteDescriptorSet, u32, ?*const c.VkCopyDescriptorSet) callconv(.C) void = undefined;
var vkCmdBindDescriptorSets:       *const fn (c.VkCommandBuffer, c.VkPipelineBindPoint, c.VkPipelineLayout, u32, u32, [*]const c.VkDescriptorSet, u32, ?*const u32) callconv(.C) void = undefined;
var vkCmdEndRenderPass:            *const fn (c.VkCommandBuffer) callconv(.C) void = undefined;
var vkEndCommandBuffer:            *const fn (c.VkCommandBuffer) callconv(.C) i32 = undefined;
var vkResetCommandBuffer:          *const fn (c.VkCommandBuffer, c.VkCommandBufferResetFlags) callconv(.C) i32 = undefined;
var vkFreeMemory:                  *const fn (c.VkDevice, c.VkDeviceMemory, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkFreeCommandBuffers:          *const fn (c.VkDevice, c.VkCommandPool, u32, *const c.VkCommandBuffer) callconv(.C) void = undefined;
var vkFreeDescriptorSets:          *const fn (c.VkDevice, c.VkDescriptorPool, u32, *const c.VkDescriptorSet) callconv(.C) i32 = undefined;
var vkMapMemory:                   *const fn (c.VkDevice, c.VkDeviceMemory, u64, u64, u32, *?*anyopaque) callconv(.C) i32 = undefined;
var vkUnmapMemory:                 *const fn (c.VkDevice, c.VkDeviceMemory) callconv(.C) void = undefined;
var vkDestroyDevice:               *const fn (c.VkDevice, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
