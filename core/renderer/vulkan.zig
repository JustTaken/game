const std = @import("std");

const _config = @import("../util/configuration.zig");
const _collections = @import("../util/collections.zig");
const _io = @import("../util/io.zig");
const _math = @import("../util/math.zig");
const _platform = @import("platform.zig");
const _object = @import("../asset/object.zig");
const _game = @import("../game.zig");
const _event = @import("../event.zig");

const c = _platform.c;

const Platform = _platform.Platform;
const configuration = _config.Configuration;
const ArrayList = _collections.ArrayList;
const Io = _io.Io;
const Vec = _math.Vec;
const Matrix = _math.Matrix;
const Object = _object.Object;
const Game = _game.Game;
const ObjectHandle = _game.ObjectHandle;
const Emiter = _event.EventSystem.Event.Emiter;

const logger = configuration.logger;

const REQUIRED_DEVICE_EXTENSIONS = [_][*:0]const u8 { c.VK_KHR_SWAPCHAIN_EXTENSION_NAME };

pub const Vulkan = struct {
    instance: Instance,
    window: Window,
    device: Device,
    swapchain: Swapchain,
    graphics_pipeline: GraphicsPipeline,
    command_pool: CommandPool,
    sync: Sync,
    data: Data,

    const Instance = struct {
        handle: c.VkInstance,
        dispatch: Dispatch,

        const Dispatch = struct {
            create_device: *const fn (c.VkPhysicalDevice, *const c.VkDeviceCreateInfo, ?*const c.VkAllocationCallbacks, ?*c.VkDevice) callconv(.C) i32,
            enumerate_physical_devices: *const fn (c.VkInstance, *u32, ?[*]c.VkPhysicalDevice) callconv(.C) i32,
            enumerate_device_extension_properties: *const fn (c.VkPhysicalDevice, ?[*]const u8, *u32, ?[*]c.VkExtensionProperties) callconv(.C) i32,
            get_physical_device_properties: *const fn (c.VkPhysicalDevice, ?*c.VkPhysicalDeviceProperties) callconv(.C) void,
            get_physical_device_features: *const fn (c.VkPhysicalDevice, ?*c.VkPhysicalDeviceFeatures) callconv(.C) void,
            get_physical_device_surface_formats: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *u32, ?[*]c.VkSurfaceFormatKHR) callconv(.C) i32,
            get_physical_device_surface_present_modes: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *u32, ?[*]c.VkPresentModeKHR) callconv(.C) i32,
            get_physical_device_queue_family_properties: *const fn (c.VkPhysicalDevice, *u32, ?[*]c.VkQueueFamilyProperties) callconv(.C) void,
            get_physical_device_surface_capabilities: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *c.VkSurfaceCapabilitiesKHR) callconv(.C) i32,
            get_physical_device_surface_support: *const fn (c.VkPhysicalDevice, u32, c.VkSurfaceKHR, *u32) callconv(.C) i32,
            get_physical_device_memory_properties: *const fn (c.VkPhysicalDevice, *c.VkPhysicalDeviceMemoryProperties) callconv(.C) void,
            get_physical_device_format_properties: *const fn (c.VkPhysicalDevice, c.VkFormat, *c.VkFormatProperties) callconv(.C) void,
            destroy_surface: *const fn (c.VkInstance, c.VkSurfaceKHR, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy: *const fn (c.VkInstance, ?*const c.VkAllocationCallbacks) callconv(.C) void,
        };

        fn new(allocator: std.mem.Allocator) !Instance {
            var instance: c.VkInstance = undefined;
            const PFN_vkCreateInstance = @as(c.PFN_vkCreateInstance, @ptrCast(c.glfwGetInstanceProcAddress(null, "vkCreateInstance"))) orelse return error.FunctionNotFound;
            const extensions = Platform.get_required_instance_extensions(allocator) catch |e| {
                logger.log(.Error, "No window extension list was provided by the platform", .{});

                return e;
            };

            defer allocator.free(extensions);

            try check(PFN_vkCreateInstance(&.{
                .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                .pApplicationInfo = &.{
                    .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                    .pApplicationName = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                    .applicationVersion = configuration.version,
                    .pEngineName = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                    .engineVersion = configuration.version,
                    .apiVersion = c.VK_MAKE_API_VERSION(0, 1, 3, 0),
                },
                .enabledExtensionCount = @as(u32, @intCast(extensions.len)),
                .ppEnabledExtensionNames = extensions.ptr,
                },
                                           null,
                                           &instance));

            const PFN_vkGetInstanceProcAddr = @as(c.PFN_vkGetInstanceProcAddr, @ptrCast(c.glfwGetInstanceProcAddress(instance, "vkGetInstanceProcAddr"))) orelse return error.FunctionNotFound;

            return .{
                .handle = instance,
                .dispatch = .{
                    .destroy_surface = @as(c.PFN_vkDestroySurfaceKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkDestroySurfaceKHR"))) orelse return error.FunctionNotFound,
                    .enumerate_physical_devices = @as(c.PFN_vkEnumeratePhysicalDevices, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkEnumeratePhysicalDevices"))) orelse return error.FunctionNotFound,
                    .enumerate_device_extension_properties = @as(c.PFN_vkEnumerateDeviceExtensionProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkEnumerateDeviceExtensionProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_properties = @as(c.PFN_vkGetPhysicalDeviceProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_features = @as(c.PFN_vkGetPhysicalDeviceFeatures, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFeatures"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_formats = @as(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_present_modes = @as(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_queue_family_properties = @as(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceQueueFamilyProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_capabilities = @as(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_support = @as(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceSupportKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_memory_properties = @as(c.PFN_vkGetPhysicalDeviceMemoryProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceMemoryProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_format_properties = @as(c.PFN_vkGetPhysicalDeviceFormatProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFormatProperties"))) orelse return error.FunctionNotFound,
                    .create_device = @as(c.PFN_vkCreateDevice, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkCreateDevice"))) orelse return error.FunctionNotFound,
                    .destroy = @as(c.PFN_vkDestroyInstance, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkDestroyInstance"))) orelse return error.FunctionNotFound,
                },
            };
        }

        fn create_device(self: Instance, physical_device: c.VkPhysicalDevice, info: c.VkDeviceCreateInfo) !c.VkDevice {
            var device: c.VkDevice = undefined;
            try check(self.dispatch.create_device(physical_device, &info, null, &device));

            return device;
        }

        fn destroy_surface(self: Instance, surface: c.VkSurfaceKHR) void {
            self.dispatch.destroy_surface(self.handle, surface, null);
        }

        fn enumerate_physical_devices(self: Instance, allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_physical_devices(self.handle, &count, null));
            const physical_devices = try allocator.alloc(c.VkPhysicalDevice, count);

            try check(self.dispatch.enumerate_physical_devices(self.handle, &count, physical_devices.ptr));

            return physical_devices;
        }

        fn enumerate_device_extension_properties(self: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkExtensionProperties {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, null));
            const extension_properties = try allocator.alloc(c.VkExtensionProperties, count);

            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, extension_properties.ptr));

            return extension_properties;
        }

        fn get_physical_device_properties(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceProperties {
            var properties: c.VkPhysicalDeviceProperties = undefined;
            self.dispatch.get_physical_device_properties(physical_device, &properties);

            return properties;
        }

        fn get_physical_device_features(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceFeatures {
            var features: c.VkPhysicalDeviceFeatures = undefined;
            self.dispatch.get_physical_device_features(physical_device, &features);

            return features;
        }

        fn get_physical_device_format_properties(self: Instance, physical_device: c.VkPhysicalDevice, format: c.VkFormat) c.VkFormatProperties {
            var properties: c.VkFormatProperties = undefined;
            self.dispatch.get_physical_device_format_properties(physical_device, format, &properties);

            return properties;
        }

        fn get_physical_device_surface_formats(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkSurfaceFormatKHR {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, null));
            const formats = try allocator.alloc(c.VkSurfaceFormatKHR, count);

            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, formats.ptr));

            return formats;
        }

        fn get_physical_device_surface_present_modes(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkPresentModeKHR {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, null));
            const present_modes = try allocator.alloc(c.VkPresentModeKHR, count);
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, present_modes.ptr));

            return present_modes;
        }

        fn get_physical_device_queue_family_properties(self: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkQueueFamilyProperties {
            var count: u32 = undefined;
            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, null);
            const properties = try allocator.alloc(c.VkQueueFamilyProperties, count);

            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, properties.ptr);

            return properties;
        }

        fn get_physical_device_surface_capabilities(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceCapabilitiesKHR {
            var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
            try check(self.dispatch.get_physical_device_surface_capabilities(physical_device, surface, &capabilities));

            return capabilities;
        }

        fn get_physical_device_surface_support(self: Instance, physical_device: c.VkPhysicalDevice, family: u32, surface: c.VkSurfaceKHR) !bool {
            var flag: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_support(physical_device, family, surface, &flag));

            return flag == c.VK_TRUE;
        }

        fn get_physical_device_memory_properties(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceMemoryProperties {
            var properties: c.VkPhysicalDeviceMemoryProperties = undefined;
            self.dispatch.get_physical_device_memory_properties(physical_device, &properties);

            return properties;
        }

        fn destroy(self: Instance) void {
            self.dispatch.destroy(self.handle, null);
        }
    };

    const Device = struct {
        handle: c.VkDevice,
        physical_device: c.VkPhysicalDevice,
        queues: [4]Queue,

        dispatch: Dispatch,

        const Queue = struct {
            handle: c.VkQueue,
            family: u32,

            fn uniques(queues: []const u32, allocator: std.mem.Allocator) !ArrayList(u32) {
                var uniques_array = try ArrayList(u32).init(allocator, 1);

                try uniques_array.push(queues[0]);

                var size: u32 = 0;

                for (queues) |family| {
                    for (0..size + 1) |i| {
                        if (family == uniques_array.items[i]) break;
                    } else {
                        try uniques_array.push(family);

                        size += 1;
                    }
                }

                return uniques_array;
            }
        };

        const Dispatch = struct {
            allocate_command_buffers: *const fn (c.VkDevice, *const c.VkCommandBufferAllocateInfo, *c.VkCommandBuffer) callconv(.C) i32,
            allocate_memory: *const fn (c.VkDevice, *const c.VkMemoryAllocateInfo, ?*const c.VkAllocationCallbacks, *c.VkDeviceMemory) callconv(.C) i32,
            allocate_descriptor_sets: *const fn (c.VkDevice, *const c.VkDescriptorSetAllocateInfo, *c.VkDescriptorSet) callconv(.C) i32,
            queue_submit: *const fn (c.VkQueue, u32, *const c.VkSubmitInfo, c.VkFence) callconv(.C) i32,
            queue_present: *const fn (c.VkQueue, *const c.VkPresentInfoKHR) callconv(.C) i32,
            queue_wait_idle: *const fn (c.VkQueue) callconv(.C) i32,
            get_image_memory_requirements: *const fn (c.VkDevice, c.VkImage, *c.VkMemoryRequirements) callconv(.C) void,
            get_device_queue: *const fn (c.VkDevice, u32, u32, *c.VkQueue) callconv(.C) void,
            get_swapchain_images: *const fn (c.VkDevice, c.VkSwapchainKHR, *u32, ?[*]c.VkImage) callconv(.C) i32,
            get_buffer_memory_requirements: *const fn (c.VkDevice, c.VkBuffer, *c.VkMemoryRequirements) callconv(.C) void,
            bind_buffer_memory: *const fn (c.VkDevice, c.VkBuffer, c.VkDeviceMemory, u64) callconv(.C) i32,
            bind_image_memory: *const fn (c.VkDevice, c.VkImage, c.VkDeviceMemory, u64) callconv(.C) i32,
            acquire_next_image: *const fn (c.VkDevice, c.VkSwapchainKHR, u64, c.VkSemaphore, c.VkFence, *u32) callconv(.C) i32,
            wait_for_fences : *const fn (c.VkDevice, u32, *const c.VkFence, u32, u64) callconv(.C) i32,
            reset_fences: *const fn (c.VkDevice, u32, *const c.VkFence) callconv(.C) i32,
            create_swapchain: *const fn (c.VkDevice, *const c.VkSwapchainCreateInfoKHR, ?*const c.VkAllocationCallbacks, *c.VkSwapchainKHR) callconv(.C) i32,
            create_image: *const fn (c.VkDevice, *const c.VkImageCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkImage) callconv(.C) i32,
            create_shader_module: *const fn (c.VkDevice, *const c.VkShaderModuleCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkShaderModule) callconv(.C) i32,
            create_pipeline_layout: *const fn (c.VkDevice, *const c.VkPipelineLayoutCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkPipelineLayout) callconv(.C) i32,
            create_image_view: *const fn (c.VkDevice, *const c.VkImageViewCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkImageView) callconv(.C) i32,
            create_render_pass: *const fn (c.VkDevice, *const c.VkRenderPassCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkRenderPass) callconv(.C) i32,
            create_graphics_pipeline: *const fn (c.VkDevice, c.VkPipelineCache, u32, *const c.VkGraphicsPipelineCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkPipeline) callconv(.C) i32,
            create_framebuffer: *const fn (c.VkDevice, *const c.VkFramebufferCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkFramebuffer) callconv(.C) i32,
            create_command_pool: *const fn (c.VkDevice, *const c.VkCommandPoolCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkCommandPool) callconv(.C) i32,
            create_semaphore: *const fn (c.VkDevice, *const c.VkSemaphoreCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkSemaphore) callconv(.C) i32,
            create_fence: *const fn (c.VkDevice, *const c.VkFenceCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkFence) callconv(.C) i32,
            create_buffer: *const fn (c.VkDevice, *const c.VkBufferCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkBuffer) callconv(.C) i32,
            create_descriptor_set_layout: *const fn (c.VkDevice, *const c.VkDescriptorSetLayoutCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkDescriptorSetLayout) callconv(.C) i32,
            create_descriptor_pool: *const fn (c.VkDevice, *const c.VkDescriptorPoolCreateInfo, ?*const c.VkAllocationCallbacks, *c.VkDescriptorPool) callconv(.C) i32,
            destroy_command_pool: *const fn (c.VkDevice, c.VkCommandPool, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_pipeline: *const fn (c.VkDevice, c.VkPipeline, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_pipeline_layout: *const fn (c.VkDevice, c.VkPipelineLayout, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_render_pass: *const fn (c.VkDevice, c.VkRenderPass, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_image_view: *const fn (c.VkDevice, c.VkImageView, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_swapchain: *const fn (c.VkDevice, c.VkSwapchainKHR, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_shader_module: *const fn (c.VkDevice, c.VkShaderModule, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_semaphore: *const fn (c.VkDevice, c.VkSemaphore, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_fence: *const fn (c.VkDevice, c.VkFence, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_framebuffer: *const fn (c.VkDevice, c.VkFramebuffer, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_buffer: *const fn (c.VkDevice, c.VkBuffer, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_descriptor_set_layout: *const fn (c.VkDevice, c.VkDescriptorSetLayout, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            destroy_descriptor_pool: *const fn (c.VkDevice, c.VkDescriptorPool, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            begin_command_buffer: *const fn (c.VkCommandBuffer, *const c.VkCommandBufferBeginInfo) callconv(.C) i32,
            cmd_begin_render_pass: *const fn (c.VkCommandBuffer, *const c.VkRenderPassBeginInfo, c.VkSubpassContents) callconv(.C) void,
            cmd_bind_pipeline: *const fn (c.VkCommandBuffer, c.VkPipelineBindPoint, c.VkPipeline) callconv(.C) void,
            cmd_bind_vertex_buffer: *const fn (c.VkCommandBuffer, u32, u32, *const c.VkBuffer, *const u64) callconv(.C) void,
            cmd_bind_index_buffer: *const fn (c.VkCommandBuffer, c.VkBuffer, u64, c.VkIndexType) callconv(.C) void,
            cmd_set_viewport: *const fn (c.VkCommandBuffer, u32, u32, *const c.VkViewport) callconv(.C) void,
            cmd_set_scissor: *const fn (c.VkCommandBuffer, u32, u32, *const c.VkRect2D ) callconv(.C) void,
            cmd_copy_buffer: *const fn (c.VkCommandBuffer, c.VkBuffer, c.VkBuffer, u32, *const c.VkBufferCopy) callconv(.C) void,
            cmd_draw: *const fn (c.VkCommandBuffer, u32, u32, u32, u32) callconv(.C) void,
            cmd_draw_indexed: *const fn (c.VkCommandBuffer, u32, u32, u32, i32, u32) callconv(.C) void,
            cmd_push_constants: *const fn (c.VkCommandBuffer, c.VkPipelineLayout, c.VkShaderStageFlags, u32, u32, ?*const anyopaque) callconv(.C) void,
            update_descriptor_sets: *const fn (c.VkDevice, u32, *const c.VkWriteDescriptorSet, u32, ?*const c.VkCopyDescriptorSet) callconv(.C) void,
            cmd_bind_descriptor_sets: *const fn (c.VkCommandBuffer, c.VkPipelineBindPoint, c.VkPipelineLayout, u32, u32, [*]const c.VkDescriptorSet, u32, ?*const u32) callconv(.C) void,
            end_render_pass: *const fn (c.VkCommandBuffer) callconv(.C) void,
            end_command_buffer: *const fn (c.VkCommandBuffer) callconv(.C) i32,
            reset_command_buffer: *const fn (c.VkCommandBuffer, c.VkCommandBufferResetFlags) callconv(.C) i32,
            free_memory: *const fn (c.VkDevice, c.VkDeviceMemory, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            free_command_buffers: *const fn (c.VkDevice, c.VkCommandPool, u32, *const c.VkCommandBuffer) callconv (.C) void,
            free_descriptor_sets: *const fn (c.VkDevice, c.VkDescriptorPool, u32, *const c.VkDescriptorSet) callconv (.C) i32,
            map_memory: *const fn (c.VkDevice, c.VkDeviceMemory, u64, u64, u32, *?*anyopaque) callconv(.C) i32,
            unmap_memory: *const fn (c.VkDevice, c.VkDeviceMemory) callconv(.C) void,
            destroy: *const fn (c.VkDevice, ?*const c.VkAllocationCallbacks) callconv(.C) void,
        };

        const Type = enum {
            Other,
            IntegratedGpu,
            DiscreteGpu,
            VirtualGpu,
            Cpu,
        };

        fn new(instance: Instance, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) !Device {
            var queue_families: [4]u32 = undefined;
            const physical_device = blk: {
                const physical_devices = instance.enumerate_physical_devices(allocator) catch |e| {
                    logger.log(.Error, "Failed to list physical devices", .{});

                    return e;
                };

                defer allocator.free(physical_devices);

                var points: u32 = 1;
                var p_device: ?c.VkPhysicalDevice = null;

                for (physical_devices) |physical_device| {
                    var families: [4]?u32 = .{null, null, null, null};
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

                        if (!((instance.get_physical_device_surface_formats(physical_device, surface, allocator) catch break :rate 0).len > 0)) break :rate 0;
                        if (!((instance.get_physical_device_surface_present_modes(physical_device, surface, allocator) catch break :rate 0).len > 0)) break :rate 0;

                        const families_properties = instance.get_physical_device_queue_family_properties(physical_device, allocator) catch |e| {
                            logger.log(.Error, "Failed to get queue family properties", .{});
                            return e;
                        };

                        defer allocator.free(families_properties);

                        for (families_properties, 0..) |properties, i| {
                            const family: u32 = @intCast(i);

                            if (families[1] == null and try instance.get_physical_device_surface_support(physical_device, family, surface)) families[1] = family;
                            if (families[0] == null and bit(properties.queueFlags, c.VK_QUEUE_GRAPHICS_BIT)) families[0] = family;
                            if (families[2] == null and bit(properties.queueFlags, c.VK_QUEUE_COMPUTE_BIT)) families[2] = family;
                            if (families[3] == null and bit(properties.queueFlags, c.VK_QUEUE_TRANSFER_BIT)) families[3] = family;
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

                    if (rating >= points) {
                        points = rating;
                        p_device = physical_device;
                        queue_families = .{families[0].?, families[1].?, families[2].?, families[3].?};
                    }
                }

                if (p_device) |physical_device| {
                    break :blk physical_device;
                } else {
                    logger.log(.Error, "Failed to find suitable GPU", .{});

                    return error.PhysicalDeviceNotFount;
                }
            };

            var families = Queue.uniques(&queue_families, allocator) catch |e| {
                logger.log(.Error, "Could not get uniques queue family index for the selecter physical device", .{});

                return e;
            };

            defer families.deinit();

            var queue_create_infos: []c.VkDeviceQueueCreateInfo = allocator.alloc(c.VkDeviceQueueCreateInfo, families.items.len) catch |e| {
                logger.log(.Error, "Out of memory", .{});

                return e;
            };

            defer allocator.free(queue_create_infos);

            for (families.items, 0..) |family, i| {
                queue_create_infos[i] = .{
                    .queueFamilyIndex = family,
                    .queueCount = 1,
                    .pQueuePriorities = &[_]f32 {1.0},
                };
            }

            const device = instance.create_device( physical_device, .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .queueCreateInfoCount = @as(u32 , @intCast(queue_create_infos.len)),
                    .pQueueCreateInfos = queue_create_infos.ptr,
                    .pEnabledFeatures = &instance.get_physical_device_features(physical_device),
                    .enabledExtensionCount = @as(u32, @intCast(REQUIRED_DEVICE_EXTENSIONS.len)),
                    .ppEnabledExtensionNames = &REQUIRED_DEVICE_EXTENSIONS[0],
                },
            ) catch |e| {
                logger.log(.Error, "Failed to create logical device handle", .{});

                return e;
            };

            const PFN_vkGetDeviceProcAddr = @as(c.PFN_vkGetDeviceProcAddr, @ptrCast(c.glfwGetInstanceProcAddress(instance.handle, "vkGetDeviceProcAddr"))) orelse return error.FunctionNotFound;
            const PFN_vkGetDeviceQueue = @as(c.PFN_vkGetDeviceQueue, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetDeviceQueue"))) orelse return error.FunctionNotFound;

            var queues: [4]Queue = .{
                .{ .family = queue_families[0], .handle = undefined, },
                .{ .family = queue_families[1], .handle = undefined, },
                .{ .family = queue_families[2], .handle = undefined, },
                .{ .family = queue_families[3], .handle = undefined, },
            };

            for (0..queues.len) |i| {
                PFN_vkGetDeviceQueue(device, queues[i].family, 0, &queues[i].handle);
            }

            return .{
                .handle = device,
                .dispatch = .{
                    .get_device_queue = PFN_vkGetDeviceQueue,
                    .allocate_command_buffers = @as(c.PFN_vkAllocateCommandBuffers, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAllocateCommandBuffers"))) orelse return error.FunctionNotFound,
                    .allocate_memory = @as(c.PFN_vkAllocateMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAllocateMemory"))) orelse return error.FunctionNotFound,
                    .allocate_descriptor_sets = @as(c.PFN_vkAllocateDescriptorSets, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAllocateDescriptorSets"))) orelse return error.FunctionNotFound,
                    .queue_submit = @as(c.PFN_vkQueueSubmit, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueueSubmit"))) orelse return error.FunctionNotFound,
                    .queue_present = @as(c.PFN_vkQueuePresentKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueuePresentKHR"))) orelse return error.FunctionNotFound,
                    .queue_wait_idle = @as(c.PFN_vkQueueWaitIdle, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueueWaitIdle"))) orelse return error.FunctionNotFound,
                    .get_swapchain_images = @as(c.PFN_vkGetSwapchainImagesKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetSwapchainImagesKHR"))) orelse return error.FunctionNotFound,
                    .get_image_memory_requirements = @as(c.PFN_vkGetImageMemoryRequirements, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetImageMemoryRequirements"))) orelse return error.FunctionNotFound,
                    .get_buffer_memory_requirements = @as(c.PFN_vkGetBufferMemoryRequirements, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetBufferMemoryRequirements"))) orelse return error.FunctionNotFound,
                    .bind_buffer_memory = @as(c.PFN_vkBindBufferMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkBindBufferMemory"))) orelse return error.FunctionNotFound,
                    .bind_image_memory = @as(c.PFN_vkBindImageMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkBindImageMemory"))) orelse return error.FunctionNotFound,
                    .acquire_next_image = @as(c.PFN_vkAcquireNextImageKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAcquireNextImageKHR"))) orelse return error.FunctionNotFound,
                    .wait_for_fences = @as(c.PFN_vkWaitForFences, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkWaitForFences"))) orelse return error.FunctionNotFound,
                    .reset_fences= @as(c.PFN_vkResetFences, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkResetFences"))) orelse return error.FunctionNotFound,
                    .create_swapchain = @as(c.PFN_vkCreateSwapchainKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateSwapchainKHR"))) orelse return error.FunctionNotFound,
                    .create_image = @as(c.PFN_vkCreateImage, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateImage"))) orelse return error.FunctionNotFound,
                    .create_image_view = @as(c.PFN_vkCreateImageView, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateImageView"))) orelse return error.FunctionNotFound,
                    .create_shader_module = @as(c.PFN_vkCreateShaderModule, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateShaderModule"))) orelse return error.FunctionNotFound,
                    .create_pipeline_layout = @as(c.PFN_vkCreatePipelineLayout, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreatePipelineLayout"))) orelse return error.FunctionNotFound,
                    .create_render_pass = @as(c.PFN_vkCreateRenderPass, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateRenderPass"))) orelse return error.FunctionNotFound,
                    .create_graphics_pipeline = @as(c.PFN_vkCreateGraphicsPipelines, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateGraphicsPipelines"))) orelse return error.FunctionNotFound,
                    .create_framebuffer = @as(c.PFN_vkCreateFramebuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateFramebuffer"))) orelse return error.FunctionNotFound,
                    .create_command_pool = @as(c.PFN_vkCreateCommandPool, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateCommandPool"))) orelse return error.FunctionNotFound,
                    .create_semaphore = @as(c.PFN_vkCreateSemaphore, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateSemaphore"))) orelse return error.FunctionNotFound,
                    .create_fence = @as(c.PFN_vkCreateFence, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateFence"))) orelse return error.FunctionNotFound,
                    .create_buffer = @as(c.PFN_vkCreateBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateBuffer"))) orelse return error.FunctionNotFound,
                    .create_descriptor_set_layout = @as(c.PFN_vkCreateDescriptorSetLayout, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateDescriptorSetLayout"))) orelse return error.FunctionNotFound,
                    .destroy_command_pool = @as(c.PFN_vkDestroyCommandPool, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyCommandPool"))) orelse return error.FunctionNotFound,
                    .create_descriptor_pool = @as(c.PFN_vkCreateDescriptorPool, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateDescriptorPool"))) orelse return error.FunctionNotFound,
                    .destroy_pipeline = @as(c.PFN_vkDestroyPipeline, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyPipeline"))) orelse return error.FunctionNotFound,
                    .destroy_pipeline_layout = @as(c.PFN_vkDestroyPipelineLayout, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyPipelineLayout"))) orelse return error.FunctionNotFound,
                    .destroy_render_pass = @as(c.PFN_vkDestroyRenderPass, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyRenderPass"))) orelse return error.FunctionNotFound,
                    .destroy_swapchain = @as(c.PFN_vkDestroySwapchainKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroySwapchainKHR"))) orelse return error.FunctionNotFound,
                    .destroy_image_view = @as(c.PFN_vkDestroyImageView, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyImageView"))) orelse return error.FunctionNotFound,
                    .destroy_shader_module = @as(c.PFN_vkDestroyShaderModule, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyShaderModule"))) orelse return error.FunctionNotFound,
                    .destroy_semaphore = @as(c.PFN_vkDestroySemaphore, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroySemaphore"))) orelse return error.FunctionNotFound,
                    .destroy_fence = @as(c.PFN_vkDestroyFence, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyFence"))) orelse return error.FunctionNotFound,
                    .destroy_framebuffer = @as(c.PFN_vkDestroyFramebuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyFramebuffer"))) orelse return error.FunctionNotFound,
                    .destroy_buffer = @as(c.PFN_vkDestroyBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyBuffer"))) orelse return error.FunctionNotFound,
                    .destroy_descriptor_set_layout = @as(c.PFN_vkDestroyDescriptorSetLayout, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyDescriptorSetLayout"))) orelse return error.FunctionNotFound,
                    .destroy_descriptor_pool = @as(c.PFN_vkDestroyDescriptorPool, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyDescriptorPool"))) orelse return error.FunctionNotFound,
                    .begin_command_buffer = @as(c.PFN_vkBeginCommandBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkBeginCommandBuffer"))) orelse return error.FunctionNotFound,
                    .cmd_begin_render_pass = @as(c.PFN_vkCmdBeginRenderPass, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdBeginRenderPass"))) orelse return error.FunctionNotFound,
                    .cmd_bind_pipeline = @as(c.PFN_vkCmdBindPipeline, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdBindPipeline"))) orelse return error.FunctionNotFound,
                    .cmd_bind_vertex_buffer = @as(c.PFN_vkCmdBindVertexBuffers, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdBindVertexBuffers"))) orelse return error.FunctionNotFound,
                    .cmd_bind_index_buffer = @as(c.PFN_vkCmdBindIndexBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdBindIndexBuffer"))) orelse return error.FunctionNotFound,
                    .cmd_set_viewport = @as(c.PFN_vkCmdSetViewport, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdSetViewport"))) orelse return error.FunctionNotFound,
                    .cmd_set_scissor = @as(c.PFN_vkCmdSetScissor, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdSetScissor"))) orelse return error.FunctionNotFound,
                    .cmd_draw = @as(c.PFN_vkCmdDraw, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdDraw"))) orelse return error.FunctionNotFound,
                    .cmd_draw_indexed = @as(c.PFN_vkCmdDrawIndexed, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdDrawIndexed"))) orelse return error.FunctionNotFound,
                    .cmd_copy_buffer = @as(c.PFN_vkCmdCopyBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdCopyBuffer"))) orelse return error.FunctionNotFound,
                    .cmd_push_constants = @as(c.PFN_vkCmdPushConstants, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdPushConstants"))) orelse return error.FunctionNotFound,
                    .update_descriptor_sets = @as(c.PFN_vkUpdateDescriptorSets, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkUpdateDescriptorSets"))) orelse return error.FunctionNotFound,
                    .cmd_bind_descriptor_sets = @as(c.PFN_vkCmdBindDescriptorSets, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdBindDescriptorSets"))) orelse return error.FunctionNotFound,
                    .end_render_pass = @as(c.PFN_vkCmdEndRenderPass, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdEndRenderPass"))) orelse return error.FunctionNotFound,
                    .end_command_buffer = @as(c.PFN_vkEndCommandBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkEndCommandBuffer"))) orelse return error.FunctionNotFound,
                    .reset_command_buffer = @as(c.PFN_vkResetCommandBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkResetCommandBuffer"))) orelse return error.FunctionNotFound,
                    .free_memory = @as(c.PFN_vkFreeMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkFreeMemory"))) orelse return error.FunctionNotFound,
                    .free_command_buffers = @as(c.PFN_vkFreeCommandBuffers, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkFreeCommandBuffers"))) orelse return error.FunctionNotFound,
                    .free_descriptor_sets = @as(c.PFN_vkFreeDescriptorSets, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkFreeDescriptorSets"))) orelse return error.FunctionNotFound,
                    .map_memory = @as(c.PFN_vkMapMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkMapMemory"))) orelse return error.FunctionNotFound,
                    .unmap_memory = @as(c.PFN_vkUnmapMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkUnmapMemory"))) orelse return error.FunctionNotFound,
                    .destroy = @as(c.PFN_vkDestroyDevice, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyDevice"))) orelse return error.FunctionNotFound,
                },
                .queues = queues,
                .physical_device = physical_device,
            };
        }

        fn get_device_queue(self: Device, family_index: u32) c.VkQueue {
            var queue: c.VkQueue = undefined;
            self.dispatch.get_device_queue(self.handle, family_index, 0, &queue);

            return queue;
        }

        fn get_swapchain_images(self: Device, swapchain: c.VkSwapchainKHR, allocator: std.mem.Allocator) ![]c.VkImage {
            var count: u32 = undefined;

            try check(self.dispatch.get_swapchain_images(self.handle, swapchain, &count, null));
            const images = try allocator.alloc(c.VkImage, count);

            try check(self.dispatch.get_swapchain_images(self.handle, swapchain, &count, images.ptr));

            return images;
        }

        fn get_image_memory_requirements(self: Device, image: c.VkImage) c.VkMemoryRequirements {
            var requirements: c.VkMemoryRequirements = undefined;
            self.dispatch.get_image_memory_requirements(self.handle, image, &requirements);

            return requirements;
        }

        fn get_buffer_memory_requirements(self: Device, buffer: c.VkBuffer) c.VkMemoryRequirements {
            var requirements: c.VkMemoryRequirements = undefined;
            self.dispatch.get_buffer_memory_requirements(self.handle, buffer, &requirements);

            return requirements;
        }

        fn bind_buffer_memory(self: Device, buffer: c.VkBuffer, memory: c.VkDeviceMemory) !void {
            try check(self.dispatch.bind_buffer_memory(self.handle, buffer, memory, 0));
        }

        fn bind_image_memory(self: Device, image: c.VkImage, memory: c.VkDeviceMemory) !void {
            try check(self.dispatch.bind_image_memory(self.handle, image, memory, 0));
        }

        fn create_image(self: Device, info: c.VkImageCreateInfo) !c.VkImage {
            var image: c.VkImage = undefined;
            try check(self.dispatch.create_image(self.handle, &info, null, &image));

            return image;
        }

        fn create_image_view(self: Device, info: c.VkImageViewCreateInfo) !c.VkImageView {
            var view: c.VkImageView = undefined;
            try check(self.dispatch.create_image_view(self.handle, &info, null, &view));

            return view;
        }

        fn create_swapchain(self: Device, info: c.VkSwapchainCreateInfoKHR) !c.VkSwapchainKHR {
            var handle: c.VkSwapchainKHR = undefined;
            try check(self.dispatch.create_swapchain(self.handle, &info, null, &handle));

            return handle;
        }
        fn create_shader_module(self: Device, info: c.VkShaderModuleCreateInfo) !c.VkShaderModule {
            var shader_module: c.VkShaderModule = undefined;
            try check(self.dispatch.create_shader_module(self.handle, &info, null, &shader_module));

            return shader_module;
        }

        fn create_pipeline_layout(self: Device, info: c.VkPipelineLayoutCreateInfo) !c.VkPipelineLayout {
            var layout: c.VkPipelineLayout = undefined;
            try check(self.dispatch.create_pipeline_layout(self.handle, &info, null, &layout));

            return layout;
        }

        fn create_descriptor_pool(self: Device, info: c.VkDescriptorPoolCreateInfo) !c.VkDescriptorPool {
            var pool: c.VkDescriptorPool = undefined;
            try check(self.dispatch.create_descriptor_pool(self.handle, &info, null, &pool));

            return pool;
        }

        fn create_graphics_pipeline(self: Device, info: c.VkGraphicsPipelineCreateInfo) !c.VkPipeline {
            var pipeline: c.VkPipeline = undefined;

            try check(self.dispatch.create_graphics_pipeline(self.handle, null, 1, &info, null, &pipeline));

            return pipeline;
        }

        fn create_render_pass(self: Device, info: c.VkRenderPassCreateInfo) !c.VkRenderPass {
            var render_pass: c.VkRenderPass = undefined;
            try check(self.dispatch.create_render_pass(self.handle, &info, null, &render_pass));

            return render_pass;
        }

        fn create_framebuffer(self: Device, info: c.VkFramebufferCreateInfo) !c.VkFramebuffer {
            var framebuffer: c.VkFramebuffer = undefined;
            try check(self.dispatch.create_framebuffer(self.handle, &info, null, &framebuffer));

            return framebuffer;
        }

        fn create_command_pool(self: Device, info: c.VkCommandPoolCreateInfo) !c.VkCommandPool {
            var command_pool: c.VkCommandPool = undefined;
            try check(self.dispatch.create_command_pool(self.handle, &info, null, &command_pool));

            return command_pool;
        }

        fn create_semaphore(self: Device, info: c.VkSemaphoreCreateInfo) !c.VkSemaphore {
            var semaphore: c.VkSemaphore = undefined;
            try check(self.dispatch.create_semaphore(self.handle, &info, null, &semaphore));

            return semaphore;
        }

        fn create_fence(self: Device, info: c.VkFenceCreateInfo) !c.VkFence {
            var fence: c.VkFence = undefined;
            try check(self.dispatch.create_fence(self.handle, &info, null, &fence));

            return fence;
        }

        fn create_buffer(self: Device, info: c.VkBufferCreateInfo) !c.VkBuffer {
            var buffer: c.VkBuffer = undefined;
            try check(self.dispatch.create_buffer(self.handle, &info, null, &buffer));

            return buffer;
        }

        fn create_descriptor_set_layout(self: Device, info: c.VkDescriptorSetLayoutCreateInfo) !c.VkDescriptorSetLayout {
            var desc: c.VkDescriptorSetLayout = undefined;
            try check(self.dispatch.create_descriptor_set_layout(self.handle, &info, null, &desc));

            return desc;
        }

        fn map_memory(self: Device, memory: c.VkDeviceMemory, comptime T: type, len: usize, dst: *?*anyopaque) !void {
            try check(self.dispatch.map_memory(self.handle, memory, 0, len * @sizeOf(T), 0, dst));
        }

        fn unmap_memory(self: Device, memory: c.VkDeviceMemory) void {
            self.dispatch.unmap_memory(self.handle, memory);
        }

        fn wait_for_fences(self: Device, fence: *c.VkFence) !void {
            // const MAX: u64 = 0xFFFFFFFFFFFFFFFF;
            const MAX: u64 = 0xFFFFFF;
            try check(self.dispatch.wait_for_fences(self.handle, 1, fence, c.VK_TRUE, MAX));
        }

        fn reset_fences(self: Device, fence: *c.VkFence) !void {
            try check(self.dispatch.reset_fences(self.handle, 1, fence));
        }

        fn allocate_command_buffers(self: Device, info: c.VkCommandBufferAllocateInfo, allocator: std.mem.Allocator) ![]c.VkCommandBuffer {
            var command_buffers = try allocator.alloc(c.VkCommandBuffer, info.commandBufferCount);
            try check(self.dispatch.allocate_command_buffers(self.handle, &info, &command_buffers[0]));

            return command_buffers;
        }

        fn allocate_descriptor_sets(self: Device, info: c.VkDescriptorSetAllocateInfo, allocator: std.mem.Allocator) ![]c.VkDescriptorSet {
            var descriptor = try allocator.alloc(c.VkDescriptorSet, info.descriptorSetCount);
            try check(self.dispatch.allocate_descriptor_sets(self.handle, &info, &descriptor[0]));

            return descriptor;
        }

        fn allocate_memory(self: Device, info: c.VkMemoryAllocateInfo) !c.VkDeviceMemory {
            var memory: c.VkDeviceMemory = undefined;
            try check(self.dispatch.allocate_memory(self.handle, &info, null, &memory));

            return memory;
        }

        fn acquire_next_image(self: Device, swapchain: c.VkSwapchainKHR, semaphore: c.VkSemaphore) !u32 {
            const MAX: u64 = 0xFFFFFFFFFFFFFFFF;
            var index: u32 = undefined;

            try check(self.dispatch.acquire_next_image(self.handle, swapchain, MAX, semaphore, null, &index));

            return index;
        }

        fn queue_submit(self: Device, info: c.VkSubmitInfo, fence: c.VkFence) !void {
            try check(self.dispatch.queue_submit(self.queues[0].handle, 1, &info, fence));
        }

        fn queue_present(self: Device, info: c.VkPresentInfoKHR) !void {
            try check(self.dispatch.queue_present(self.queues[1].handle, &info));
        }

        fn queue_wait_idle(self: Device, queue: c.VkQueue) !void {
            try check(self.dispatch.queue_wait_idle(queue));
        }

        fn begin_command_buffer(self: Device, command_buffer: c.VkCommandBuffer, info: c.VkCommandBufferBeginInfo) !void {
            try check(self.dispatch.begin_command_buffer(command_buffer, &info));
        }

        fn cmd_begin_render_pass(self: Device, command_buffer: c.VkCommandBuffer, info: c.VkRenderPassBeginInfo) void {
            self.dispatch.cmd_begin_render_pass(command_buffer, &info, c.VK_SUBPASS_CONTENTS_INLINE);
        }

        fn cmd_bind_pipeline(self: Device, command_buffer: c.VkCommandBuffer, pipeline: c.VkPipeline) void {
            self.dispatch.cmd_bind_pipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        }

        fn cmd_bind_vertex_buffer(self: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
            self.dispatch.cmd_bind_vertex_buffer(command_buffer, 0, 1, &buffer, &0);
        }

        fn cmd_bind_index_buffer(self: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
            self.dispatch.cmd_bind_index_buffer(command_buffer, buffer, 0, c.VK_INDEX_TYPE_UINT16);
        }

        fn cmd_set_viewport(self: Device, command_buffer: c.VkCommandBuffer, viewport: c.VkViewport) void {
            self.dispatch.cmd_set_viewport(command_buffer, 0, 1, &viewport);
        }

        fn cmd_set_scissor(self: Device, command_buffer: c.VkCommandBuffer, scissor: c.VkRect2D) void {
            self.dispatch.cmd_set_scissor(command_buffer, 0, 1, &scissor);
        }

        fn cmd_copy_buffer(self: Device, command_buffer: c.VkCommandBuffer, src: c.VkBuffer, dst: c.VkBuffer, copy: c.VkBufferCopy) void {
            self.dispatch.cmd_copy_buffer(command_buffer, src, dst, 1, &copy);
        }

        fn cmd_draw(self: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
            self.dispatch.cmd_draw(command_buffer, size, 1, 0, 0);
        }

        fn cmd_draw_indexed(self: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
            self.dispatch.cmd_draw_indexed(command_buffer, size, 1, 0, 0, 0);
        }

        fn cmd_bind_descriptor_sets(self: Device, command_buffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, first: u32, count: u32, descriptor_sets: []const c.VkDescriptorSet, offsets: ?[]const u32) void {
            const len: u32 = if (offsets) |o| @as(u32, @intCast(o.len)) else 0;
            self.dispatch.cmd_bind_descriptor_sets(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, layout, first, count, descriptor_sets.ptr, len, @ptrCast(offsets));
        }

        fn cmd_push_constants(self: Device, command_buffer: c.VkCommandBuffer, layout: c.VkPipelineLayout, offset: u32, size: u32, value: ?*const anyopaque) void {
            self.dispatch.cmd_push_constants(command_buffer, layout, c.VK_SHADER_STAGE_VERTEX_BIT, offset, size, value);
        }

        fn update_descriptor_sets(self: Device, write: c.VkWriteDescriptorSet) void {
            self.dispatch.update_descriptor_sets(self.handle, 1, &write, 0, null);
        }

        fn end_render_pass(self: Device, command_buffer: c.VkCommandBuffer) void {
            self.dispatch.end_render_pass(command_buffer);
        }

        fn end_command_buffer(self: Device, command_buffer: c.VkCommandBuffer) !void {
            try check(self.dispatch.end_command_buffer(command_buffer));
        }

        fn reset_command_buffer(self: Device, command_buffer: c.VkCommandBuffer) !void {
            try check(self.dispatch.reset_command_buffer(command_buffer, 0));
        }

        fn destroy_command_pool(self: Device, command_pool: c.VkCommandPool) void {
            self.dispatch.destroy_command_pool(self.handle, command_pool, null);
        }

        fn destroy_swapchain(self: Device, swapchain: c.VkSwapchainKHR) void {
            self.dispatch.destroy_swapchain(self.handle, swapchain, null);
        }

        fn destroy_shader_module(self: Device, shader_module: c.VkShaderModule) void {
            self.dispatch.destroy_shader_module(self.handle, shader_module, null);
        }

        fn destroy_pipeline(self: Device, pipeline: c.VkPipeline) void {
            self.dispatch.destroy_pipeline(self.handle, pipeline, null);
        }

        fn destroy_pipeline_layout(self: Device, pipeline_layout: c.VkPipelineLayout) void {
            self.dispatch.destroy_pipeline_layout(self.handle, pipeline_layout, null);
        }

        fn destroy_render_pass(self: Device, render_pass: c.VkRenderPass) void {
            self.dispatch.destroy_render_pass(self.handle, render_pass, null);
        }

        fn destroy_semaphore(self: Device, semaphore: c.VkSemaphore) void {
            self.dispatch.destroy_semaphore(self.handle, semaphore, null);
        }

        fn destroy_fence(self: Device, fence: c.VkFence) void {
            self.dispatch.destroy_fence(self.handle, fence, null);
        }

        fn destroy_image_view(self: Device, image_view: c.VkImageView) void {
            self.dispatch.destroy_image_view(self.handle, image_view, null);
        }

        fn destroy_framebuffer(self: Device, framebuffer: c.VkFramebuffer) void {
            self.dispatch.destroy_framebuffer(self.handle, framebuffer, null);
        }

        fn destroy_buffer(self: Device, buffer: c.VkBuffer) void {
            self.dispatch.destroy_buffer(self.handle, buffer, null);
        }

        fn destroy_descriptor_set_layout(self: Device, layout: c.VkDescriptorSetLayout) void {
            self.dispatch.destroy_descriptor_set_layout(self.handle, layout, null);
        }

        fn destroy_descriptor_pool(self: Device, pool: c.VkDescriptorPool) void {
            self.dispatch.destroy_descriptor_pool(self.handle, pool, null);
        }

        fn free_memory(self: Device, memory: c.VkDeviceMemory) void {
            self.dispatch.free_memory(self.handle, memory, null);
        }

        fn free_command_buffer(self: Device, command_pool: c.VkCommandPool, command_buffer: c.VkCommandBuffer) void {
            self.dispatch.free_command_buffers(self.handle, command_pool, 1, &command_buffer);
        }

        fn free_descriptor_sets(self: Device, descriptor_pool: c.VkDescriptorPool, n: usize, descriptor_sets: []const c.VkDescriptorSet) !void {
            try check(self.dispatch.free_descriptor_sets(self.handle, descriptor_pool, @intCast(n), &descriptor_sets[0]));
        }

        fn destroy(self: Device) void {
            self.dispatch.destroy(self.handle, null);
        }
    };

    const Swapchain = struct {
        handle: c.VkSwapchainKHR,
        extent: c.VkExtent2D,
        image_views: ArrayList(c.VkImageView),
        framebuffers: ArrayList(c.VkFramebuffer),
        depth_image_view: c.VkImageView,
        depth_image_memory: c.VkDeviceMemory,
        arena: std.heap.ArenaAllocator,

        fn new(device: Device, instance: Instance, window: Window, graphics_pipeline: GraphicsPipeline, opt_arena: ?std.heap.ArenaAllocator) !Swapchain {
            var arena = opt_arena orelse std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();

            const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;

            const capabilities = instance.get_physical_device_surface_capabilities(device.physical_device, window.surface) catch |e| {
                logger.log(.Error, "Could not access physical device capabilities", .{});

                return e;
            };

            const extent: c.VkExtent2D = blk: {
                if (capabilities.currentExtent.width != 0xFFFFFFFF) {
                    break :blk capabilities.currentExtent;
                } else {
                    break :blk .{
                        .width = std.math.clamp(window.extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
                        .height = std.math.clamp(window.extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
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

            const handle = device.create_swapchain(.{
                .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                .surface = window.surface,
                .minImageCount = image_count,
                .imageFormat = graphics_pipeline.format.format,
                .imageColorSpace = graphics_pipeline.format.colorSpace,
                .imageExtent = extent,
                .imageSharingMode = if (uniques_queue_family_index.items.len == 1) c.VK_SHARING_MODE_EXCLUSIVE else c.VK_SHARING_MODE_CONCURRENT,
                .presentMode = present_mode,
                .preTransform = capabilities.currentTransform,
                .clipped = c.VK_TRUE,
                .imageArrayLayers = 1,
                .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
                .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
                .queueFamilyIndexCount = @as(u32, @intCast(uniques_queue_family_index.items.len)),
                .pQueueFamilyIndices = uniques_queue_family_index.items.ptr,
                .oldSwapchain = null,
            }) catch |e| {
                logger.log(.Error, "Failed to create sawpchain", .{});

                return e;
            };

            _ = arena.reset(.free_all);

            const images = device.get_swapchain_images(handle, allocator) catch |e| {
                logger.log(.Error, "Failed to get swapchain images", .{});

                return e;
            };

            var image_views = ArrayList(c.VkImageView).init(allocator, @intCast(images.len)) catch |e| {
                logger.log(.Error, "Could not allocate image views array", .{});

                return e;
            };

            for (0..images.len) |i| {
                image_views.push(device.create_image_view(.{
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
                    .width = extent.width,
                    .height = extent.height,
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

            const depth_image_memory = device.allocate_memory(.{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = image_memory_requirements.size,
                .memoryTypeIndex = @intCast(memory_index),
            }) catch |e| {
                logger.log(.Error, "Failed to allocate depth image memory", .{});

                return e;
            };

            device.bind_image_memory(depth_image, depth_image_memory) catch |e| {
                logger.log(.Error, "Failed to bind depth image memory", .{});

                return e;
            };

            const depth_image_view = device.create_image_view(.{
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

            var framebuffers = ArrayList(c.VkFramebuffer).init(allocator, @intCast(images.len)) catch {
                logger.log(.Error, "Failed to create framebuffers array",  .{});

                return error.OutOfMemory;
            };

            for (0..image_views.items.len) |i| {
                framebuffers.push(device.create_framebuffer(.{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .renderPass = graphics_pipeline.render_pass,
                    .attachmentCount = 2,
                    .pAttachments = &[_]c.VkImageView {image_views.items[i], depth_image_view},
                    .width = extent.width,
                    .height = extent.height,
                    .layers = 1,
                }) catch |e| {
                    logger.log(.Error, "Failed to crate frambuffer", .{});

                    return e;
                }) catch |e| {
                    logger.log(.Error, "Could not insert element in framebuffes array", .{});

                    return e;
                    };
                }

            return .{
                .handle = handle,
                .image_views = image_views,
                .framebuffers = framebuffers,
                .extent = extent,
                .depth_image_view = depth_image_view,
                .depth_image_memory = depth_image_memory,
                .arena = arena,
            };
        }

        fn recreate(
            self: *Swapchain,
            device: Device,
            instance: Instance,
            pipeline: GraphicsPipeline,
            window: *Window,
            command_pool: *CommandPool,
            sync: *Sync
        ) !void {
            device.queue_wait_idle(device.queues[0].handle) catch {
                logger.log(.Error, "device did not wait for present queue", .{});

                return;
            };

            while (true) {
                const extent = Platform.get_framebuffer_size(window.handle);
                sync.nanos_per_frame = Platform.get_nanos_per_frame(window.handle) catch blk: {
                    break :blk Sync.default;
                };

                if (extent.width == 0 or extent.height == 0) {
                    Platform.wait_events();
                } else if (extent.width != window.extent.width or extent.height != window.extent.height) {
                    window.extent.width = extent.width;
                    window.extent.height = extent.height;
                    window.emiter.value = .{
                        .u32 = .{ extent.width, extent.height },
                    };

                    window.emiter.changed = true;
                } else {
                    break;
                }

                std.time.sleep(60 * Sync.default);
            }


            self.destroy(device);

            const new_swapchain = try Swapchain.new(device, instance, window.*, pipeline, self.arena);

            self.handle = new_swapchain.handle;
            self.extent = new_swapchain.extent;
            self.image_views = new_swapchain.image_views;
            self.framebuffers = new_swapchain.framebuffers;
            self.depth_image_view = new_swapchain.depth_image_view;
            self.depth_image_memory = new_swapchain.depth_image_memory;
            self.arena = new_swapchain.arena;

            command_pool.invalidate_all();
        }

        fn acquire_next_image(self: Swapchain, device: Device, sync: Sync) !u32 {
            return try device.acquire_next_image(self.handle, sync.image_available);
        }

        fn draw_next_frame(
            self: *Swapchain,
            device: Device,
            instance: Instance,
            pipeline: GraphicsPipeline,
            window: *Window,
            command_pool: *CommandPool,
            data: Data,
            sync: *Sync
        ) !void {
            self.draw_frame(device, pipeline, command_pool, data, sync) catch |e| {
                if(e == VkResult.SuboptimalKhr or e == VkResult.OutOfDateKhr) {
                    try self.recreate(device, instance, pipeline, window, command_pool, sync);

                    logger.log(.Debug, "Swapchain recreated", .{});
                } else {
                    return e;
                }
            };
        }

        fn draw_frame(
            self: Swapchain,
            device: Device,
            pipeline: GraphicsPipeline,
            command_pool: *CommandPool,
            data: Data,
            sync: *Sync,
        ) !void {
            const image_index = try self.acquire_next_image(device, sync.*);

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

            sync.changed = true;

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

        fn destroy(self: *Swapchain, device: Device) void {
            device.free_memory(self.depth_image_memory);
            device.destroy_image_view(self.depth_image_view);
            device.destroy_swapchain(self.handle);

            _ = self.arena.reset(.free_all);
        }
    };

    const Window = struct {
        handle: *Platform.Window,
        surface: c.VkSurfaceKHR,
        extent: c.VkExtent2D,
        emiter: *Emiter = undefined,

        fn new(instance: Instance, extent: ?c.VkExtent2D) !Window {
            const handle = Platform.create_window(extent, &configuration.application_name[0]) catch |e| {
                logger.log(.Error, "Platform failed to create window handle", .{});

                return e;
            };

            const surface = Platform.create_window_surface(instance.handle, handle, null) catch |e| {
                logger.log(.Error, "Failed to create window surface", .{});

                return e;
            };

            const window_extent = extent orelse blk: {
                break :blk Platform.get_framebuffer_size(handle);
            };

            return .{
                .handle = handle,
                .surface = surface,
                .extent = window_extent
            };
        }

        pub fn register_emiter(self: *Window, emiter: *Emiter) void {
            self.emiter = emiter;
        }

        fn destroy(self: Window, instance: Instance) void {
            instance.destroy_surface(self.surface);
            Platform.destroy_window(self.handle);
        }
    };

    const GraphicsPipeline = struct {
        handle: c.VkPipeline,
        layout: c.VkPipelineLayout,
        render_pass: c.VkRenderPass,
        format: c.VkSurfaceFormatKHR,
        depth_format: c.VkFormat,
        descriptor: Descriptor,

        const Descriptor = struct {
            pools: ArrayList(Pool),
            layouts: ArrayList(c.VkDescriptorSetLayout),
            size_each: u32,

            arena: std.heap.ArenaAllocator,

            const Pool = struct {
                handle: c.VkDescriptorPool,
                descriptor_set_layout: c.VkDescriptorSetLayout,
                descriptor_sets: ArrayList(c.VkDescriptorSet),

                fn new(device: Device, allocator: std.mem.Allocator, layout: c.VkDescriptorSetLayout, size: u32) !Pool {
                    const handle = try device.create_descriptor_pool(.{
                        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                        .poolSizeCount = 1,
                        .pPoolSizes = &.{
                            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                            .descriptorCount = size,
                        },
                        .maxSets = size,
                    });

                    return .{
                        .handle = handle,
                        .descriptor_set_layout = layout,
                        .descriptor_sets = try ArrayList(c.VkDescriptorSet).init(allocator, size),
                    };
                }

                fn allocate(self: *Pool, device: Device, count: u32, allocator: std.mem.Allocator) ![]const c.VkDescriptorSet {
                    if (!(self.descriptor_sets.items.len + count < self.descriptor_sets.capacity)) {
                        return error.NoSpace;
                    }

                    var layouts = ArrayList(c.VkDescriptorSetLayout).init(allocator, count) catch |e| {
                        logger.log(.Error, "Failed to create layouts array", .{});

                        return e;
                    };

                    for (0..count) |_| {
                        layouts.push(self.descriptor_set_layout) catch |e| {
                            logger.log(.Error, "Could not insert layou in descriptor set layouts array", .{});

                            return e;
                        };
                    }

                    defer layouts.deinit();

                    const descriptor_sets = device.allocate_descriptor_sets(.{
                            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                            .descriptorPool = self.handle,
                            .descriptorSetCount = count,
                            .pSetLayouts = layouts.items.ptr,
                        }, allocator) catch |e| {
                        logger.log(.Error, "Failed to create descriptor sets", .{});

                        return e;
                    };

                    for (0..count) |i| {
                        self.descriptor_sets.push(descriptor_sets[i]) catch |e| {
                            logger.log(.Error, "Failed to insert element in descriptor sets array", .{});

                            return e;
                        };
                    }

                    return descriptor_sets;
                }

                fn destroy(self: *Pool, device: Device) void {
                    device.free_descriptor_sets(self.handle, self.descriptor_sets.items.len, self.descriptor_sets.items) catch {};
                }
            };

            fn new(size_each: u32) !Descriptor {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                const allocator = arena.allocator();

                return .{
                    .pools = try ArrayList(Pool).init(allocator, 1),
                    .layouts = try ArrayList(c.VkDescriptorSetLayout).init(allocator, 1),
                    .size_each = size_each,
                    .arena = arena,
                };
            }

            fn add_layout(self: *Descriptor, layout: c.VkDescriptorSetLayout) !usize {
                const id = self.layouts.items.len;
                try self.layouts.push(layout);

                return id;
            }

            fn allocate(self: *Descriptor, device: Device, layout_id: usize, count: u32) ![]const c.VkDescriptorSet {
                const allocator = self.arena.allocator();
                const descriptor_sets = blk: for (0..self.pools.items.len) |i| {
                    const sets = self.pools.items[i].allocate(device, count, allocator) catch {
                        continue;
                    };

                    break :blk sets;
                } else {
                    try self.pools.push(try Pool.new(device, allocator, self.layouts.items[layout_id], self.size_each));
                    break :blk try self.pools.items[self.pools.items.len - 1].allocate(device, count, allocator);
                };

                return descriptor_sets;
            }

            fn destroy(self: *Descriptor, device: Device) void {
                for (0..self.pools.items.len) |i| {
                    self.pools.items[i].destroy(device);
                }

                for (self.layouts.items) |layout| {
                    device.destroy_descriptor_set_layout(layout);
                }

                _ = self.arena.deinit();
            }
        };

        fn new(device: Device, instance: Instance, window: Window, allocator: std.mem.Allocator) !GraphicsPipeline {
            const vert_code = Io.read_file("assets/vert.spv", allocator) catch |e| {
                logger.log(.Error, "Could not read vertex shader byte code", .{});

                return e;
            };

            const frag_code = Io.read_file("assets/frag.spv", allocator) catch |e| {
                logger.log(.Error, "Could not read fragment shader byte code", .{});

                return e;
            };

            const vert_module = device.create_shader_module(.{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = vert_code.len,
                .pCode = @as([*c]const u32, @ptrCast(@alignCast(vert_code))),
            }) catch |e| {
                logger.log(.Error, "Failed to create vertex shader module", .{});

                return e;
            };

            defer device.destroy_shader_module(vert_module);

            const frag_module = device.create_shader_module(.{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = frag_code.len,
                .pCode = @as([*c]const u32, @ptrCast(@alignCast(frag_code))),
            }) catch |e| {
                logger.log(.Error, "Failed to create fragment shader module", .{});

                return e;
            };

            defer device.destroy_shader_module(frag_module);

            const shader_stage_infos = &[_]c.VkPipelineShaderStageCreateInfo {
                .{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .module = vert_module,
                    .pName = "main",
                },
                .{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = frag_module,
                    .pName = "main",
                },
            };

            const dynamic_states = &[_]c.VkDynamicState { c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
            const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .dynamicStateCount = dynamic_states.len,
                .pDynamicStates = dynamic_states.ptr,
            };

            const vertex_input_state_info: c.VkPipelineVertexInputStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .vertexBindingDescriptionCount = 1,
                .pVertexBindingDescriptions = &Data.Model.Vertex.binding_description,
                .vertexAttributeDescriptionCount = Data.Model.Vertex.attribute_descriptions.len,
                .pVertexAttributeDescriptions = Data.Model.Vertex.attribute_descriptions.ptr,
            };

            const input_assembly_state_info: c.VkPipelineInputAssemblyStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            };

            const viewport_state_info: c.VkPipelineViewportStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .viewportCount = 1,
                .pViewports = &.{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @as(f32, @floatFromInt(configuration.default_width)),
                    .height = @as(f32, @floatFromInt(configuration.default_height)),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                },
                .pScissors = &.{
                    .offset = .{.x = 0, .y = 0},
                    .extent = .{
                        .width = configuration.default_width,
                        .height = configuration.default_height,
                    }
                },
            };

            const rasterizer_state_info: c.VkPipelineRasterizationStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = c.VK_FALSE,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .lineWidth = 1.0,
                .cullMode = c.VK_CULL_MODE_BACK_BIT,
                .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0.0,
                .depthBiasClamp = 0.0,
            };

            const multisampling_state_info: c.VkPipelineMultisampleStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .sampleShadingEnable = c.VK_FALSE,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .minSampleShading = 1.0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            };

            const color_blend_state_info: c.VkPipelineColorBlendStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &.{
                    .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                    .blendEnable = c.VK_FALSE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                    .alphaBlendOp = c.VK_BLEND_OP_ADD,
                },
                .blendConstants = .{ 0.0, 0.0, 0.0, 0.0 },
            };

            const depth_stencil_state_info: c.VkPipelineDepthStencilStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .depthTestEnable = c.VK_TRUE,
                .depthWriteEnable = c.VK_TRUE,
                .depthCompareOp = c.VK_COMPARE_OP_LESS,
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = c.VK_FALSE,
                .minDepthBounds = 0.0,
                .maxDepthBounds = 1.0,
            };

            const descriptor_set_layout = try device.create_descriptor_set_layout(.{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                .bindingCount = 1,
                .pBindings = &[_]c.VkDescriptorSetLayoutBinding {
                    .{
                        .binding = 0,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .descriptorCount = 1,
                        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
                        .pImmutableSamplers = null,
                    },
                }
            });

            const layout = device.create_pipeline_layout(.{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .setLayoutCount = 2,
                .pSetLayouts = &[_] c.VkDescriptorSetLayout {descriptor_set_layout, descriptor_set_layout},
                .pushConstantRangeCount = 0,
                .pPushConstantRanges = null,
            }) catch |e| {
                logger.log(.Error, "Failed to create pipeline layout", .{});

                return e;
            };

            var descriptor = Descriptor.new(16) catch |e| {
                logger.log(.Error, "Failed to create descriptor pool handle", .{});

                return e;
            };

            _ = try descriptor.add_layout(descriptor_set_layout);

            const formats = instance.get_physical_device_surface_formats(device.physical_device, window.surface, allocator) catch |e| {
                logger.log(.Error, "Failed to list surface formats", .{});

                return e;
            };

            const format = blk: for (formats) |format| {
                if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                    break :blk format;
                }
            } else {
                logger.log(.Warn, "Could not find a good surface format falling back to first in list", .{});

                break :blk formats[0];
            };

            const depth_formats = [_] c.VkFormat {
                c.VK_FORMAT_D32_SFLOAT,
                c.VK_FORMAT_D32_SFLOAT_S8_UINT,
                c.VK_FORMAT_D24_UNORM_S8_UINT,
            };

            const flags = c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
            const depth_format = blk: for (depth_formats) |candidate| {
                const format_properties = instance.get_physical_device_format_properties(device.physical_device, candidate);
                if ((format_properties.linearTilingFeatures & flags) == flags or (format_properties.optimalTilingFeatures & flags) == flags) {
                    break :blk candidate;
                }
            } else {
                logger.log(.Error, "Failed to find suitable depth format", .{});

                return error.DepthFormat;
            };

            const render_pass = device.create_render_pass(.{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                .attachmentCount = 2,
                .pAttachments = &[_] c.VkAttachmentDescription {
                    .{
                        .format = format.format,
                        .samples = c.VK_SAMPLE_COUNT_1_BIT,
                        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                    },
                    .{
                        .format = depth_format,
                        .samples = c.VK_SAMPLE_COUNT_1_BIT,
                        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                        .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                    }
                },
                .subpassCount = 1,
                .pSubpasses = &.{
                    .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    .colorAttachmentCount = 1,
                    .pColorAttachments = &.{
                        .attachment = 0,
                        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    },
                    .pDepthStencilAttachment = &.{
                        .attachment = 1,
                        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
                    },
                },
                .dependencyCount = 1,
                .pDependencies = &.{
                    .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                    .dstSubpass = 0,
                    .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                    .srcAccessMask = 0,
                    .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                    .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                },
            }) catch |e| {
                logger.log(.Error, "Failed to create render pass", .{});

                return e;
            };

            const handle = device.create_graphics_pipeline(.{
                .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                .stageCount = shader_stage_infos.len,
                .pStages = shader_stage_infos.ptr,
                .pVertexInputState = &vertex_input_state_info,
                .pInputAssemblyState = &input_assembly_state_info,
                .pViewportState = &viewport_state_info,
                .pRasterizationState = &rasterizer_state_info,
                .pMultisampleState = &multisampling_state_info,
                .pDynamicState = &dynamic_state_info,
                .pColorBlendState = &color_blend_state_info,
                .pDepthStencilState = &depth_stencil_state_info,
                .layout = layout,
                .renderPass = render_pass,
                .subpass = 0,
                .basePipelineHandle = null,
            }) catch |e| {
                logger.log(.Error, "Failed to create graphics pipeline", .{});

                return e;
            };

            return .{
                .handle = handle,
                .layout = layout,
                .render_pass = render_pass,
                .descriptor = descriptor,
                .format = format,
                .depth_format = depth_format,
            };
        }

        fn destroy(self: *GraphicsPipeline, device: Device) void {
            self.descriptor.destroy(device);
            device.destroy_pipeline_layout(self.layout);
            device.destroy_render_pass(self.render_pass);
            device.destroy_pipeline(self.handle);
        }
    };

    const CommandPool = struct {
        handle: c.VkCommandPool,
        buffers: ArrayList(Buffer),
        arena: std.heap.ArenaAllocator,

        const Buffer = struct {
            handle: c.VkCommandBuffer,
            is_valid: bool = false,
            id: u32,

            fn record(self: *Buffer, device: Device, pipeline: GraphicsPipeline, swapchain: Swapchain, data: Data) !void {
                try device.begin_command_buffer(self.handle, .{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .flags = 0,
                    .pInheritanceInfo = null,
                });

                device.cmd_begin_render_pass(self.handle, .{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                    .renderPass = pipeline.render_pass,
                    .framebuffer = swapchain.framebuffers.items[self.id],
                    .renderArea = .{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = swapchain.extent,
                    },
                    .clearValueCount = 2,
                    .pClearValues= &[_] c.VkClearValue {
                        .{
                            .color = .{ .float32 = .{0.0, 0.0, 0.0, 1.0}, }
                        },
                        .{
                            .depthStencil = .{ .depth = 1.0, .stencil = 0 },
                        }
                        },
                });

                device.cmd_set_viewport(self.handle, .{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @as(f32, @floatFromInt(swapchain.extent.width)),
                    .height = @as(f32, @floatFromInt(swapchain.extent.height)),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                });

                device.cmd_set_scissor(self.handle, .{
                    .offset = .{ .x = 0, .y = 0},
                    .extent = swapchain.extent,
                });

                device.cmd_bind_pipeline(self.handle, pipeline.handle);

                for (0..data.models.len) |i| {
                    if (data.models[i].len == 0) continue;

                    device.cmd_bind_vertex_buffer(self.handle, data.models[i].vertex.handle);
                    device.cmd_bind_index_buffer(self.handle, data.models[i].index.handle);

                    for (data.models[i].items.items) |item| {
                        device.cmd_bind_descriptor_sets(self.handle, pipeline.layout, 0, 2, &[_] c.VkDescriptorSet {data.global.descriptor_set, item.descriptor_set}, null);
                        device.cmd_draw_indexed(self.handle, data.models[i].len);
                    }
                }

                device.end_render_pass(self.handle);
                try device.end_command_buffer(self.handle);

                self.is_valid = true;
            }
        };

        fn invalidate_all(self: *CommandPool) void {
            for (0..self.buffers.items.len) |i| {
                self.buffers.items[i].is_valid = false;
            }
        }

        fn new(device: Device, swapchain: Swapchain) !CommandPool {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();

            const handle = device.create_command_pool(.{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                .queueFamilyIndex = device.queues[0].family,
            }) catch |e| {
                logger.log(.Error, "Failed to create command pool", .{});

                return e;
            };

            const count: u32 = @intCast(swapchain.framebuffers.items.len);
            var buffers = try ArrayList(Buffer).init(allocator, count);
            const bs = device.allocate_command_buffers(.{
                    .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                    .commandPool = handle,
                    .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                    .commandBufferCount = count,
                }, allocator) catch |e| {
                logger.log(.Error, "Failed to allocate command buffer", .{});

                return e;
            };

            for (0..count) |i| {
                try buffers.push(.{
                    .handle = bs[i],
                    .id = @intCast(i),
                });
            }

            return .{
                .buffers = buffers,
                .handle = handle,
                .arena = arena,
            };
        }

        fn destroy(self: *CommandPool, device: Device) void {
            for (0..self.buffers.items.len) |i| {
                device.free_command_buffer(self.handle, self.buffers.items[i].handle);
            }

            device.destroy_command_pool(self.handle);
            _ = self.arena.deinit();
        }
    };

    const Sync = struct {
        image_available: c.VkSemaphore,
        render_finished: c.VkSemaphore,
        in_flight_fence: c.VkFence,
        timer: std.time.Timer,
        nanos_per_frame: u32,
        changed: bool = false,

        const default: u32 = @intCast(1000000000 / 60);

        fn new(device: Device, window: Window) !Sync {
            const timer = try std.time.Timer.start();

            const nanos_per_frame = Platform.get_nanos_per_frame(window.handle) catch blk: {
                logger.log(.Error, "Could not get the especific frame rate of window, using 60 fps as default", .{});
                break :blk default;
            };

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
                .timer = timer,
                .nanos_per_frame = nanos_per_frame,
            };
        }

        fn update(self: *Sync, device: Device) void {
            if (self.changed) {
                device.wait_for_fences(&self.in_flight_fence) catch {
                    logger.log(.Error, "CPU did not wait for draw call", .{});
                };
                device.reset_fences(&self.in_flight_fence) catch {
                    logger.log(.Error, "Failed to reset CPU fence", .{});
                };

                self.changed = false;
            }

            const delta = self.timer.lap();
            if (delta < self.nanos_per_frame) {
                std.time.sleep(self.nanos_per_frame - delta);
                self.timer.reset();
            }
        }

        fn destroy(self: Sync, device: Device) void {
            device.destroy_semaphore(self.image_available);
            device.destroy_semaphore(self.render_finished);
            device.destroy_fence(self.in_flight_fence);
        }
    };

    const Data = struct {
        global: Global,
        models: []Model,
        arena: std.heap.ArenaAllocator,

        const Global = struct {
            buffer: Buffer,
            mapped: *Uniform,
            descriptor_set: c.VkDescriptorSet,

            const Uniform = struct {
                view: [4][4]f32,
                proj: [4][4]f32,
            };

            fn new(
                device: Device,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                descriptor: *GraphicsPipeline.Descriptor,
                allocator: std.mem.Allocator
            ) !Global {
                const buffer = try Buffer.new(
                    device,
                    memory_properties,
                    c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                    Uniform,
                    null,
                    1,
                    allocator
                );

                var mapped: *Uniform = undefined;
                try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                mapped.view = Matrix.scale(1.0, 1.0, 1.0);
                mapped.proj = Matrix.scale(1.0, 1.0, 1.0);

                const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

                device.update_descriptor_sets(.{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .dstSet = descriptor_set,
                    .dstBinding = 0,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .pBufferInfo = &.{
                        .buffer = buffer.handle,
                        .offset = 0,
                        .range = @sizeOf(Uniform),
                    },
                    .pImageInfo = null,
                    .pTexelBufferView = null,
                });

                return .{
                    .buffer = buffer,
                    .mapped = mapped,
                    .descriptor_set = descriptor_set,
                };
            }

            fn destroy(self: Global, device: Device) void {
                device.unmap_memory(self.buffer.memory);
                self.buffer.destroy(device);
            }
        };

        const Model = struct {
            items: ArrayList(Item) = undefined,

            index: Buffer = undefined,
            vertex: Buffer = undefined,
            len: u32 = 0,

            const Item = struct {
                descriptor_set: c.VkDescriptorSet,
                mapped: *Uniform,
                buffer: Buffer,

                const Uniform = struct {
                    model: [4][4]f32,
                    color: [4][4]f32,
                };

                fn set_model(self: *Item, uniform: Uniform) !void {
                    @memcpy(@as([*]Uniform, @ptrCast(@alignCast(self.mapped))), &[_]Uniform { uniform });
                }

                fn new(
                    device: Device,
                    memory_properties: c.VkPhysicalDeviceMemoryProperties,
                    descriptor: *GraphicsPipeline.Descriptor,
                    uniform: Uniform,
                    allocator: std.mem.Allocator
                ) !Item {
                    var mapped: *Uniform = undefined;
                    const buffer = try Buffer.new(
                        device,
                        memory_properties,
                        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                        Uniform,
                        null,
                        1,
                        allocator,
                    );

                    try device.map_memory(buffer.memory, Uniform, 1, @ptrCast(&mapped));
                    mapped.* = uniform;

                    const descriptor_set = (try descriptor.allocate(device, 0, 1))[0];

                    device.update_descriptor_sets(.{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                        .dstSet = descriptor_set,
                        .dstBinding = 0,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .pBufferInfo = &.{
                            .buffer = buffer.handle,
                            .offset = 0,
                            .range = @sizeOf(Uniform),
                        },
                        .pImageInfo = null,
                        .pTexelBufferView = null,
                    });

                    return .{
                        .descriptor_set = descriptor_set,
                        .mapped = mapped,
                        .buffer = buffer,
                    };
                }

                fn destroy(self: Item, device: Device) void {
                    device.unmap_memory(self.buffer.memory);
                    self.buffer.destroy(device);
                }
            };

            const Vertex = struct {
                position: [3]f32,
                color: [3]f32 = .{1.0, 1.0, 1.0},

                const binding_description: c.VkVertexInputBindingDescription = .{
                    .binding = 0,
                    .stride = @sizeOf(Vertex),
                    .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
                };

                const attribute_descriptions = &[_]c.VkVertexInputAttributeDescription {
                    .{
                        .binding = 0,
                        .location = 0,
                        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                        .offset = @offsetOf(Vertex, "position"),
                    },
                    .{
                        .binding = 0,
                        .location = 1,
                        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                        .offset = @offsetOf(Vertex, "color"),
                    },
                };
            };

            fn new(
                device: Device,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                allocator: std.mem.Allocator,
                typ: Object.Type
            ) !Model {
                const object = try Object.new(typ, allocator);
                const Index = @TypeOf(object.index.items[0]);
                const index = try Buffer.new(
                    device,
                    memory_properties,
                    c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    Index,
                    object.index,
                    object.index.items.len,
                    allocator,
                );

                var vertices = try ArrayList(Vertex).init(allocator, @intCast(object.vertex.items.len));
                for (object.vertex.items) |vert| {
                    try vertices.push(.{
                        .position = .{vert.x, vert.y, vert.z},
                    });
                }

                const vertex = try Buffer.new(
                    device,
                    memory_properties,
                    c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    Vertex,
                    vertices,
                    vertices.items.len,
                    allocator
                );

                const items = try ArrayList(Item).init(allocator, 1);

                return .{
                    .index = index,
                    .vertex = vertex,
                    .items = items,
                    .len = @intCast(object.index.items.len)
                };
            }

            fn add_item(
                self: *Model,
                device: Device,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                uniform: Item.Uniform,
                descriptor: *GraphicsPipeline.Descriptor,
                allocator: std.mem.Allocator
            ) !u16 {
                try self.items.push(try Item.new(device, memory_properties, descriptor, uniform, allocator));
                return @intCast(self.items.items.len - 1);
            }

            fn destroy(self: Model, device: Device) void {
                if (self.len == 0) return;
                for (self.items.items) |item| {
                    item.destroy(device);
                }

                self.vertex.destroy(device);
                self.index.destroy(device);
            }
        };

        const Buffer = struct {
            handle: c.VkBuffer,
            memory: c.VkDeviceMemory,

            fn new(
                device: Device,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                opt_usage: ?c.VkBufferUsageFlags,
                opt_properties: ?c.VkMemoryPropertyFlags,
                comptime T: type,
                data: ?ArrayList(T),
                len: usize,
                allocator: std.mem.Allocator,
            ) !Buffer {
                const usage = opt_usage orelse c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
                const properties = opt_properties orelse c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

                const buffer = try device.create_buffer(.{
                    .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                    .size = @sizeOf(T) * len,
                    .usage = usage,
                    .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                });

                const memory_requirements = device.get_buffer_memory_requirements(buffer);

                const index = blk: for (0..memory_properties.memoryTypeCount) |i| {
                    if ((memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                        break :blk i;
                    }
                } else {
                    logger.log(.Error, "Could not find memory type that suit the need of buffer allocation", .{});
                    return error.NoMemoryRequirementsPassed;
                };

                const memory = try device.allocate_memory(.{
                    .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                    .allocationSize = memory_requirements.size,
                    .memoryTypeIndex = @as(u32, @intCast(index)),
                });

                try device.bind_buffer_memory(buffer, memory);

                if (data) |b| {
                    const staging_buffer = try Buffer.new(device, memory_properties, null, null, T, null, len, allocator);
                    var dst: *T = undefined;
                    try device.map_memory(staging_buffer.memory, T, len, @ptrCast(&dst));
                    @memcpy(@as([*]T, @ptrCast(@alignCast(dst))), b.items);
                    device.unmap_memory(staging_buffer.memory);

                    const command_pool = device.create_command_pool(.{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                        .queueFamilyIndex = device.queues[0].family,
                    }) catch |e| {
                        logger.log(.Error, "Failed to create command pool", .{});

                        return e;
                    };

                    const command_buffers = device.allocate_command_buffers(.{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                        .commandPool = command_pool,
                        .commandBufferCount = 1,
                        }, allocator) catch |e| {
                        logger.log(.Error, "Failed to allocate command buffer", .{});

                        return e;
                    };

                    try device.begin_command_buffer(command_buffers[0], .{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
                    });

                    device.cmd_copy_buffer(command_buffers[0], staging_buffer.handle, buffer, .{
                        .srcOffset = 0,
                        .dstOffset = 0,
                        .size = @sizeOf(T) * len,
                    });

                    try device.end_command_buffer(command_buffers[0]);
                    try device.queue_submit(
                        .{
                            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                            .commandBufferCount = 1,
                            .pCommandBuffers = &command_buffers[0],
                        }, null,
                    );

                    try device.queue_wait_idle(device.queues[0].handle);

                    device.free_command_buffer(command_pool, command_buffers[0]);
                    device.destroy_buffer(staging_buffer.handle);
                    device.free_memory(staging_buffer.memory);
                    allocator.free(command_buffers);
                }

                return .{
                    .handle = buffer,
                    .memory = memory,
                };
            }

            fn destroy(self: Buffer, device: Device) void {
                device.destroy_buffer(self.handle);
                device.free_memory(self.memory);
            }
        };

        fn new(device: Device, memory_properties: c.VkPhysicalDeviceMemoryProperties, descriptor: *GraphicsPipeline.Descriptor) !Data {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();

            const models = try allocator.alloc(Model, @intFromEnum(Object.Type.None));
            @memset(models, .{});

            return .{
                .global = try Global.new(device, memory_properties, descriptor, allocator),
                .models = models,
                .arena = arena,
            };
        }

        fn register_changes(
            self: *Data,
            device: Device,
            memory_properties: c.VkPhysicalDeviceMemoryProperties,
            descriptor: *GraphicsPipeline.Descriptor,
            command_pool: *CommandPool,
            game: *Game,
        ) !void {
            const allocator = self.arena.allocator();

            if (game.object_handle.has_change()) {
                for (game.object_handle.to_update.items) |update| {
                    const object = game.object_handle.objects.items[update.id];
                    const k = @intFromEnum(object.typ);

                    if (self.models[k].len == 0) {
                        self.models[k] = try Model.new(device, memory_properties, allocator, object.typ);
                    }

                    switch (update.data) {
                        .model => |model| self.models[k].items.items[object.id].mapped.model = model,
                        .color => |color| self.models[k].items.items[object.id].mapped.color = color,
                        .new => {
                            game.object_handle.objects.items[update.id].id = try self.models[k].add_item(device, memory_properties, .{
                                .model = object.model,
                                .color = object.color,
                                }, descriptor, allocator);

                            command_pool.invalidate_all();
                        },
                    }
                }

                try game.object_handle.clear_updates();
            } if (game.camera.changed) {
                game.camera.changed = false;
                self.global.mapped.view = game.camera.view;
                self.global.mapped.proj = game.camera.proj;
            }
        }

        fn destroy(self: Data, device: Device) void {
            self.global.destroy(device);

            for (self.models) |model| {
                model.destroy(device);
            }

            _ = self.arena.deinit();
        }
    };

    pub fn new() !Vulkan {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const allocator = arena.allocator();

        defer { _ = arena.deinit(); }

        try Platform.init();

        const instance = Instance.new(allocator) catch |e| {
            logger.log(.Error, "Failed to create instance", .{});

            return e;
        };

        const window = Window.new(instance, .{.width = configuration.default_width, .height = configuration.default_height }) catch |e| {
            logger.log(.Error, "Failed to create window", .{});

            return e;
        };

        const device = Device.new(instance, window.surface, allocator) catch |e| {
            logger.log(.Error, "Failed to create device", .{});

            return e;
        };

        var graphics_pipeline = GraphicsPipeline.new(device, instance, window, allocator) catch |e| {
            logger.log(.Error, "Failed to create graphics_pipeline", .{});

            return e;
        };

        const swapchain = Swapchain.new(device, instance, window, graphics_pipeline, null) catch |e| {
            logger.log(.Error, "Failed to create swapchain", .{});

            return e;
        };

        const sync = Sync.new(device, window) catch |e| {
            logger.log(.Error, "Failed to create sync objects", .{});

            return e;
        };

        const data = Data.new(device, instance.get_physical_device_memory_properties(device.physical_device), &graphics_pipeline.descriptor) catch |e| {
            logger.log(.Error, "Failed to create objects data", .{});

            return e;
        };

        const command_pool = CommandPool.new(device, swapchain) catch |e| {
            logger.log(.Error, "Failed to create command pool", .{});

            return e;
        };

        return .{
            .instance = instance,
            .window = window,
            .device = device,
            .swapchain = swapchain,
            .graphics_pipeline = graphics_pipeline,
            .command_pool = command_pool,
            .sync = sync,
            .data = data,
        };
    }

    pub fn draw(self: *Vulkan, game: *Game) !void {
        self.sync.update(self.device);

        if (game.object_handle.has_change() or game.camera.changed) {
            self.data.register_changes(
                self.device,
                self.instance.get_physical_device_memory_properties(self.device.physical_device),
                &self.graphics_pipeline.descriptor,
                &self.command_pool,
                game,
            ) catch |e| {
                logger.log(.Error, "Failed to register changes in frame", .{});

                return e;
            };

            try self.swapchain.draw_next_frame(self.device, self.instance, self.graphics_pipeline, &self.window, &self.command_pool, self.data, &self.sync);
        }
    }

    pub fn shutdown(self: *Vulkan) void {
        self.command_pool.destroy(self.device);
        self.data.destroy(self.device);
        self.sync.destroy(self.device);
        self.graphics_pipeline.destroy(self.device);
        self.swapchain.destroy(self.device);
        self.device.destroy();
        self.window.destroy(self.instance);
        self.instance.destroy();

        Platform.shutdown();
    }

    const VkResult = error {
        NotReady,
        Timeout,
        EventSet,
        EventReset,
        OutOfHostMemory,
        OutOfDeviceMemory,
        InitializationFailed,
        DeviceLost,
        MemoryMapFailed,
        LayerNotPresent,
        ExtensionNotPresent,
        FeatureNotPresent,
        IncompatibleDriver,
        TooManyObjects,
        FormatNotSupported,
        FragmentedPool,
        Unknown,
        InvalidExternalHandle,
        Fragmentation,
        InvalidOpaqueCaptureAddress,
        PipelineCompileRequired,
        SurfaceLostKhr,
        NativeWindowInUseKhr,
        SuboptimalKhr,
        OutOfDateKhr,
        IncompatibleDisplayKhr,
        Incomplete,
        ValidationFailedExt,
        InvalidShaderNv,
        ImageUsageNotSupportedKhr,
        VideoPictureLayoutNotSupportedKhr,
        VideoProfileOperationNotSupportedKhr,
        VideoProfileFormatNotSupportedKhr,
        VideoProfileCodecNotSupportedKhr,
        VideoStdVersionNotSupportedKhr,
        InvalidDrmFormatModifierPlaneLayoutExt,
        NotPermittedKhr,
        FullScreenExclusiveModeLostExt,
        ThreadIdleKhr,
        ThreadDoneKhr,
        OperationDeferredKhr,
        OperationNotDeferredKhr,
        InvalidVideoStdParametersKhr,
        CompressionExhaustedExt,
        IncompatibleShaderBinaryExt,
        OutOfPoolMemoryKhr,
        Else,
    };

    fn check(result: i32) VkResult!void {
        switch (result) {
            c.VK_SUCCESS => return,
            c.VK_NOT_READY => { logger.log(.Debug, "Vulkan result failed with: 'NotReady", .{}); return VkResult.NotReady; },
            c.VK_TIMEOUT => { logger.log(.Debug, "Vulkan result failed with: 'Timeout", .{}); return VkResult.Timeout; },
            c.VK_EVENT_SET => { logger.log(.Debug, "Vulkan result failed with: 'EventSet", .{}); return VkResult.EventSet; },
            c.VK_EVENT_RESET => { logger.log(.Debug, "Vulkan result failed with: 'EventReset", .{}); return VkResult.EventReset; },
            c.VK_INCOMPLETE => { logger.log(.Debug, "Vulkan result failed with: Incomplete", .{}); return VkResult.Incomplete; },
            c.VK_ERROR_OUT_OF_HOST_MEMORY => { logger.log(.Debug, "Vulkan result failed with 'OutOfHostMemory", .{}); return VkResult.OutOfHostMemory; },
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY => { logger.log(.Debug, "Vulkan result failed with: 'OutOfDeviceMemory'", .{}); return VkResult.OutOfDeviceMemory; },
            c.VK_ERROR_INITIALIZATION_FAILED => { logger.log(.Debug, "Vulkan result failed with: 'InitializationFailed'", .{}); return VkResult.InitializationFailed; },
            c.VK_ERROR_DEVICE_LOST => { logger.log(.Debug, "Vulkan result failed with: 'DeviceLost'", .{}); return VkResult.DeviceLost; },
            c.VK_ERROR_MEMORY_MAP_FAILED => { logger.log(.Debug, "Vulkan result failed with: 'MemoryMapFailed'", .{}); return VkResult.MemoryMapFailed; },
            c.VK_ERROR_LAYER_NOT_PRESENT => { logger.log(.Debug, "Vulkan result failed with: 'LayerNotPresent'", .{}); return VkResult.LayerNotPresent; },
            c.VK_ERROR_EXTENSION_NOT_PRESENT => { logger.log(.Debug, "Vulkan result failed with: 'ExtensionNotPresent'", .{}); return VkResult.ExtensionNotPresent; },
            c.VK_ERROR_FEATURE_NOT_PRESENT => { logger.log(.Debug, "Vulkan result failed with: 'FeatureNotPresent'", .{}); return VkResult.FeatureNotPresent; },
            c.VK_ERROR_INCOMPATIBLE_DRIVER => { logger.log(.Debug, "Vulkan result failed with: 'IncompatibleDriver'", .{}); return VkResult.IncompatibleDriver; },
            c.VK_ERROR_TOO_MANY_OBJECTS => { logger.log(.Debug, "Vulkan result failed with: 'TooManyObjects'", .{}); return VkResult.TooManyObjects; },
            c.VK_ERROR_FORMAT_NOT_SUPPORTED => { logger.log(.Debug, "Vulkan result failed with: 'FormatNotSupported'", .{}); return VkResult.FormatNotSupported; },
            c.VK_ERROR_FRAGMENTED_POOL => { logger.log(.Debug, "Vulkan result failed with: 'FragmentedPool'", .{}); return VkResult.FragmentedPool; },
            c.VK_ERROR_UNKNOWN => { logger.log(.Debug, "Vulkan result failed with: 'Unknown'", .{}); return VkResult.Unknown; },
            c.VK_ERROR_INVALID_EXTERNAL_HANDLE => { logger.log(.Debug, "Vulkan result failed with: 'InvalidExternalHandle'", .{}); return VkResult.InvalidExternalHandle; },
            c.VK_ERROR_FRAGMENTATION => { logger.log(.Debug, "Vulkan result failed with: 'Fragmentation'", .{}); return VkResult.Fragmentation; },
            c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => { logger.log(.Debug, "Vulkan result failed with: 'InvalidOpaqueCaptureAddress'", .{}); return VkResult.InvalidOpaqueCaptureAddress; },
            c.VK_PIPELINE_COMPILE_REQUIRED => { logger.log(.Debug, "Vulkan result failed with: 'PipelineCompileRequired'", .{}); return VkResult.PipelineCompileRequired; },
            c.VK_ERROR_SURFACE_LOST_KHR => { logger.log(.Debug, "Vulkan result failed with: 'SurfaceLostKhr'", .{}); return VkResult.SurfaceLostKhr; },
            c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => { logger.log(.Debug, "Vulkan result failed with: 'NativeWindowInUseKhr'", .{}); return VkResult.NativeWindowInUseKhr; },
            c.VK_SUBOPTIMAL_KHR => { logger.log(.Debug, "Vulkan result failed with: 'SuboptimalKhr'", .{}); return VkResult.SuboptimalKhr; },
            c.VK_ERROR_OUT_OF_DATE_KHR => { logger.log(.Debug, "Vulkan result failed with: 'OutOfDateKhr'", .{}); return VkResult.OutOfDateKhr; },
            c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => { logger.log(.Debug, "Vulkan result failed with: 'IncompatibleDisplayKhr'", .{}); return VkResult.IncompatibleDisplayKhr; },
            c.VK_ERROR_VALIDATION_FAILED_EXT => { logger.log(.Debug, "Vulkan result failed with: 'ValidationFailedExt'", .{}); return VkResult.ValidationFailedExt; },
            c.VK_ERROR_INVALID_SHADER_NV => { logger.log(.Debug, "Vulkan result failed with: 'InvalidShaderNv'", .{}); return VkResult.InvalidShaderNv; },
            c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'ImageUsageNotSupportedKhr'", .{}); return VkResult.ImageUsageNotSupportedKhr; },
            c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'VideoPictureLayoutNotSupportedKhr'", .{}); return VkResult.VideoPictureLayoutNotSupportedKhr; },
            c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'VideoProfileOperationNotSupportedKhr'", .{}); return VkResult.VideoProfileOperationNotSupportedKhr; },
            c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'VideoProfileFormatNotSupportedKhr'", .{}); return VkResult.VideoProfileFormatNotSupportedKhr; },
            c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'VideoProfileCodecNotSupportedKhr'", .{}); return VkResult.VideoProfileCodecNotSupportedKhr; },
            c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'VideoStdVersionNotSupportedKhr'", .{}); return VkResult.VideoStdVersionNotSupportedKhr; },
            c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => { logger.log(.Debug, "Vulkan result failed with: 'InvalidDrmFormatModifierPlaneLayoutExt'", .{}); return VkResult.InvalidDrmFormatModifierPlaneLayoutExt; },
            c.VK_ERROR_NOT_PERMITTED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'NotPermittedKhr'", .{}); return VkResult.NotPermittedKhr; },
            c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => { logger.log(.Debug, "Vulkan result failed with: 'FullScreenExclusiveModeLostExt'", .{}); return VkResult.FullScreenExclusiveModeLostExt; },
            c.VK_THREAD_IDLE_KHR => { logger.log(.Debug, "Vulkan result failed with: 'ThreadIdleKhr'", .{}); return VkResult.ThreadIdleKhr; },
            c.VK_THREAD_DONE_KHR => { logger.log(.Debug, "Vulkan result failed with: 'ThreadDoneKhr'", .{}); return VkResult.ThreadDoneKhr; },
            c.VK_OPERATION_DEFERRED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'OperationDeferredKhr'", .{}); return VkResult.OperationDeferredKhr; },
            c.VK_OPERATION_NOT_DEFERRED_KHR => { logger.log(.Debug, "Vulkan result failed with: 'OperationNotDeferredKhr'", .{}); return VkResult.OperationNotDeferredKhr; },
            c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => { logger.log(.Debug, "Vulkan result failed with: 'InvalidVideoStdParametersKhr'", .{}); return VkResult.InvalidVideoStdParametersKhr; },
            c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => { logger.log(.Debug, "Vulkan result failed with: 'CompressionExhaustedExt'", .{}); return VkResult.CompressionExhaustedExt; },
            c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => { logger.log(.Debug, "Vulkan result failed with: 'IncompatibleShaderBinaryExt'", .{}); return VkResult.IncompatibleShaderBinaryExt; },
            c.VK_ERROR_OUT_OF_POOL_MEMORY_KHR => { logger.log(.Debug, "Vulkan result failed with: 'OutOfPoolMemoryKhr'", .{}); return VkResult.OutOfPoolMemoryKhr; },

            else => { logger.log(.Debug, "Vulkan result failed with code: ({})", .{result}); return VkResult.Else; }
        }
    }

    fn bit(one: u32, other: u32) bool {
        return (one & other) != 0;
    }

    fn boolean(flag: u32) bool {
        return flag == c.VK_TRUE;
    }
};
