const std = @import("std");
const _utility = @import("../utility.zig");

pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("GLFW/glfw3.h");
});

const configuration = _utility.Configuration;
const Io = _utility.Io;

const REQUIRED_DEVICE_EXTENSIONS = [_][*:0]const u8 { c.VK_KHR_SWAPCHAIN_EXTENSION_NAME };

pub const Glfw = struct {
    pub const Window = c.GLFWwindow;

    pub const Press = c.GLFW_PRESS;
    pub const KeyF = c.GLFW_KEY_F;

    pub fn init() !void {
        if (c.glfwInit() != c.GLFW_TRUE) {
            configuration.logger.log(.Error, "Glfw failed to initialize", .{});

            return error.GlfwInit;
        }

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            configuration.logger.log(.Error, "Vulkan lib not found", .{});

            return error.VulkanInit;
        }
    }

    pub fn create_window(width: u32, height: u32, name: [*c]const u8) !*Window {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        return c.glfwCreateWindow(@intCast(width), @intCast(height), name, null, null) orelse error.WindowInit;
    }

    pub fn destroy_window(window: *Window) void {
        c.glfwDestroyWindow(window);
    }

    pub fn create_window_surface(instance: Vulkan.Instance, window: *Window, callback: ?*c.VkAllocationCallbacks) !c.VkSurfaceKHR {
        var surface: c.VkSurfaceKHR = undefined;
        if (c.glfwCreateWindowSurface(instance.handle, window, callback, &surface) != c.VK_SUCCESS) return error.lksjdafklj;

        return surface;
    }

    pub fn window_should_close(window: *Window) bool {
        return c.glfwWindowShouldClose(window) != 0;
    }

    pub fn get_framebuffer_size(window: *Window) c.VkExtent2D {
        var width: i32 = undefined;
        var height: i32 = undefined;

        c.glfwGetFramebufferSize(window, &width, &height);

        return .{
            .width = @as(u32, @intCast(width)),
            .height = @as(u32, @intCast(height)),
        };
    }

    pub fn get_required_instance_extensions(allocator: std.mem.Allocator) ![][*:0]const u8 {
        var count: u32 = undefined;
        const extensions_c = c.glfwGetRequiredInstanceExtensions(&count);
        const extensions = try allocator.alloc([*:0]const u8, count);

        for (0..count) |i| {
            extensions[i] = extensions_c[i];
        }

        return extensions;
    }

    pub fn wait_events() void {
        c.glfwWaitEvents();
    }

    pub fn get_key(window: *Window, key: i32) i32 {
        return c.glfwGetKey(window, key);
    }

    pub fn get_time() f64 {
        return c.glfwGetTime();
    }

    pub fn poll_events() void {
        c.glfwPollEvents();
    }

    pub fn shutdown() void {
        c.glfwTerminate();
    }
};

pub const Vulkan = struct {
    pub const Instance = struct {
        handle: c.VkInstance,
        dispatch: Dispatch,

        pub const Dispatch = struct {
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

        pub fn new(allocator: std.mem.Allocator) !Instance {
            var instance: c.VkInstance = undefined;
            const PFN_vkCreateInstance = @as(c.PFN_vkCreateInstance, @ptrCast(c.glfwGetInstanceProcAddress(null, "vkCreateInstance"))) orelse return error.FunctionNotFound;
            const extensions = Glfw.get_required_instance_extensions(allocator) catch |e| {
                configuration.logger.log(.Error, "No window extension list was provided by the platform", .{});

                return e;
            };

            try check(PFN_vkCreateInstance(
                &.{
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
                &instance
            ));

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

        pub fn create_device(self: Instance, physical_device: c.VkPhysicalDevice, info: c.VkDeviceCreateInfo) !c.VkDevice {
            var device: c.VkDevice = undefined;
            try check(self.dispatch.create_device(physical_device, &info, null, &device));

            return device;
        }

        pub fn destroy_surface(self: Instance, surface: c.VkSurfaceKHR) void {
            self.dispatch.destroy_surface(self.handle, surface, null);
        }

        pub fn enumerate_physical_devices(self: Instance, allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_physical_devices(self.handle, &count, null));
            const physical_devices = allocator.alloc(c.VkPhysicalDevice, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});

                return error.OutOfMemory;
            };
            try check(self.dispatch.enumerate_physical_devices(self.handle, &count, physical_devices.ptr));

            return physical_devices;
        }

        pub fn enumerate_device_extension_properties(self: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkExtensionProperties {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, null));
            const extension_properties = allocator.alloc(c.VkExtensionProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});

                return error.OutOfMemory;
            };
            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, extension_properties.ptr));

            return extension_properties;
        }

        pub fn get_physical_device_properties(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceProperties {
            var properties: c.VkPhysicalDeviceProperties = undefined;
            self.dispatch.get_physical_device_properties(physical_device, &properties);

            return properties;
        }

        pub fn get_physical_device_features(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceFeatures {
            var features: c.VkPhysicalDeviceFeatures = undefined;
            self.dispatch.get_physical_device_features(physical_device, &features);

            return features;
        }

        pub fn get_physical_device_format_properties(self: Instance, physical_device: c.VkPhysicalDevice, format: c.VkFormat) c.VkFormatProperties {
            var properties: c.VkFormatProperties = undefined;
            self.dispatch.get_physical_device_format_properties(physical_device, format, &properties);

            return properties;
        }

        pub fn get_physical_device_surface_formats(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkSurfaceFormatKHR {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, null));
            const formats = allocator.alloc(c.VkSurfaceFormatKHR, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});

                return error.OutOfMemory;
            };
            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, formats.ptr));

            return formats;
        }

        pub fn get_physical_device_surface_present_modes(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkPresentModeKHR {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, null));
            const present_modes = allocator.alloc(c.VkPresentModeKHR, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});

                return error.OutOfMemory;
            };
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, present_modes.ptr));

            return present_modes;
        }

        pub fn get_physical_device_queue_family_properties(self: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkQueueFamilyProperties {
            var count: u32 = undefined;
            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, null);
            const properties = allocator.alloc(c.VkQueueFamilyProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, properties.ptr);

            return properties;
        }

        pub fn get_physical_device_surface_capabilities(self: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceCapabilitiesKHR {
            var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
            try check(self.dispatch.get_physical_device_surface_capabilities(physical_device, surface, &capabilities));

            return capabilities;
        }

        pub fn get_physical_device_surface_support(self: Instance, physical_device: c.VkPhysicalDevice, family: u32, surface: c.VkSurfaceKHR) !bool {
            var flag: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_support(physical_device, family, surface, &flag));

            return flag == c.VK_TRUE;
        }

        pub fn get_physical_device_memory_properties(self: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceMemoryProperties {
            var properties: c.VkPhysicalDeviceMemoryProperties = undefined;
            self.dispatch.get_physical_device_memory_properties(physical_device, &properties);

            return properties;
        }


        pub fn destroy(self: Instance) void {
            self.dispatch.destroy(self.handle, null);
        }
    };

    pub const Device = struct {
        handle: c.VkDevice,
        physical_device: c.VkPhysicalDevice,
        memory_properties: c.VkPhysicalDeviceMemoryProperties,
        queues: [4]Queue,

        dispatch: Dispatch,

        const Queue = struct {
            handle: c.VkQueue,
            family: u32,

            fn uniques(queues: []const u32, allocator: std.mem.Allocator) !std.ArrayList(u32) {
                var uniques_array = std.ArrayList(u32).initCapacity(allocator, 1) catch |e| {
                    configuration.logger.log(.Error, "Out of memory", .{});

                    return e;
                };

                const first = [_]u32 {queues[0]};
                uniques_array.appendSlice(&first) catch |e| {
                    configuration.logger.log(.Error, "Out of memory", .{});

                    return e;
                };

                var size: u32 = 0;

                for (queues) |family| {
                    for (0..size + 1) |i| {
                        if (family == uniques_array.items[i]) break;
                    } else {
                        uniques_array.append(family) catch |e| {
                            configuration.logger.log(.Error, "Failed to add member to uniques queue family index list", .{});

                            return e;
                        };

                        size += 1;
                    }
                }

                return uniques_array;
            }
        };

        pub const Dispatch = struct {
            allocate_command_buffer: *const fn (c.VkDevice, *const c.VkCommandBufferAllocateInfo, *c.VkCommandBuffer) callconv(.C) i32,
            allocate_memory: *const fn (c.VkDevice, *const c.VkMemoryAllocateInfo, ?*const c.VkAllocationCallbacks, *c.VkDeviceMemory) callconv(.C) i32,
            queue_submit: *const fn (c.VkQueue, u32, *const c.VkSubmitInfo, c.VkFence) callconv(.C) i32,
            queue_present: *const fn (c.VkQueue, *const c.VkPresentInfoKHR) callconv(.C) i32,
            queue_wait_idle: *const fn (c.VkQueue) callconv(.C) i32,
            get_image_memory_requirements: *const fn (c.VkDevice, c.VkImage, *c.VkMemoryRequirements) callconv(.C) void,
            get_device_queue: *const fn (c.VkDevice, u32, u32, *c.VkQueue) callconv(.C) void,
            get_swapchain_images: *const fn (c.VkDevice, c.VkSwapchainKHR, *u32, ?[*]c.VkImage) callconv(.C) i32,
            get_buffer_memory_requirements: *const fn (c.VkDevice, c.VkBuffer, *c.VkMemoryRequirements) callconv(.C) void,
            bind_buffer_memory: *const fn (c.VkDevice, c.VkBuffer, c.VkDeviceMemory, u64) callconv(.C) i32,
            acquire_next_image: *const fn (c.VkDevice, c.VkSwapchainKHR, u64, c.VkSemaphore, c.VkFence, *u32) callconv(.C) i32,
            create_swapchain: *const fn (c.VkDevice, *const c.VkSwapchainCreateInfoKHR, ?*const c.VkAllocationCallbacks, *c.VkSwapchainKHR) callconv(.C) i32,
            wait_for_fences : *const fn (c.VkDevice, u32, *const c.VkFence, u32, u64) callconv(.C) i32,
            reset_fences: *const fn (c.VkDevice, u32, *const c.VkFence) callconv(.C) i32,
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

            end_render_pass: *const fn (c.VkCommandBuffer) callconv(.C) void,
            end_command_buffer: *const fn (c.VkCommandBuffer) callconv(.C) i32,
            reset_command_buffer: *const fn (c.VkCommandBuffer, c.VkCommandBufferResetFlags) callconv(.C) i32,

            free_memory: *const fn (c.VkDevice, c.VkDeviceMemory, ?*const c.VkAllocationCallbacks) callconv(.C) void,
            free_command_buffers: *const fn (c.VkDevice, c.VkCommandPool, u32, *const c.VkCommandBuffer) callconv (.C) void,
            map_memory: *const fn (c.VkDevice, c.VkDeviceMemory, u64, u64, u32, *?*anyopaque) callconv(.C) i32,
            unmap_memory: *const fn (c.VkDevice, c.VkDeviceMemory) callconv(.C) void,
            destroy: *const fn (c.VkDevice, ?*const c.VkAllocationCallbacks) callconv(.C) void,
        };

        pub const Type = enum {
            Other,
            IntegratedGpu,
            DiscreteGpu,
            VirtualGpu,
            Cpu,
        };

        pub fn new(instance: Instance, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) !Device {
            var queue_families: [4]u32 = undefined;
            const physical_device = blk: {
                const physical_devices = instance.enumerate_physical_devices(allocator) catch |e| {
                    configuration.logger.log(.Error, "Failed to list physical devices", .{});

                    return e;
                };

            var points: u32 = 1;
            var p_device: ?c.VkPhysicalDevice = null;

            for (physical_devices) |physical_device| {
                var families: [4]?u32 = .{null, null, null, null};
                const rating: u32 = rate: {
                    const extensions_properties = instance.enumerate_device_extension_properties(physical_device, allocator) catch {
                        configuration.logger.log(.Warn, "Could not get properties of one physical device, skipping", .{});

                        break :rate 0;
                    };

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
                        configuration.logger.log(.Error, "Failed to get queue family properties", .{});
                        return e;
                    };

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
                    configuration.logger.log(.Error, "Failed to find suitable GPU", .{});

                    return error.PhysicalDeviceNotFount;
                }
            };

            const priority: [1]f32 = .{1};
            const families = Queue.uniques(&queue_families, allocator) catch |e| {
                configuration.logger.log(.Error, "Could not get uniques queue family index for the selecter physical device", .{});

                return e;
            };

            var queue_create_infos: []c.VkDeviceQueueCreateInfo = allocator.alloc(c.VkDeviceQueueCreateInfo, families.items.len) catch |e| {
                configuration.logger.log(.Error, "Out of memory", .{});

                return e;
            };

            for (families.items, 0..) |family, i| {
                queue_create_infos[i] = .{
                    .queueFamilyIndex = family,
                    .queueCount = 1,
                    .pQueuePriorities = &priority,
                };
            }

            const device = instance.create_device(
                physical_device,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .queueCreateInfoCount = @as(u32 , @intCast(queue_create_infos.len)),
                    .pQueueCreateInfos = queue_create_infos.ptr,
                    .pEnabledFeatures = &instance.get_physical_device_features(physical_device),
                    .enabledExtensionCount = @as(u32, @intCast(REQUIRED_DEVICE_EXTENSIONS.len)),
                    .ppEnabledExtensionNames = &REQUIRED_DEVICE_EXTENSIONS[0],
                },
            ) catch |e| {
                configuration.logger.log(.Error, "Failed to create logical device handle", .{});

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

            const memory_properties = instance.get_physical_device_memory_properties(physical_device);

            return .{
                .handle = device,
                .dispatch = .{
                    .get_device_queue = PFN_vkGetDeviceQueue,
                    .allocate_command_buffer = @as(c.PFN_vkAllocateCommandBuffers, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAllocateCommandBuffers"))) orelse return error.FunctionNotFound,
                    .allocate_memory = @as(c.PFN_vkAllocateMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkAllocateMemory"))) orelse return error.FunctionNotFound,
                    .queue_submit = @as(c.PFN_vkQueueSubmit, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueueSubmit"))) orelse return error.FunctionNotFound,
                    .queue_present = @as(c.PFN_vkQueuePresentKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueuePresentKHR"))) orelse return error.FunctionNotFound,
                    .queue_wait_idle = @as(c.PFN_vkQueueWaitIdle, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkQueueWaitIdle"))) orelse return error.FunctionNotFound,
                    .get_swapchain_images = @as(c.PFN_vkGetSwapchainImagesKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetSwapchainImagesKHR"))) orelse return error.FunctionNotFound,
                    .get_image_memory_requirements = @as(c.PFN_vkGetImageMemoryRequirements, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetImageMemoryRequirements"))) orelse return error.FunctionNotFound,
                    .get_buffer_memory_requirements = @as(c.PFN_vkGetBufferMemoryRequirements, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetBufferMemoryRequirements"))) orelse return error.FunctionNotFound,
                    .bind_buffer_memory = @as(c.PFN_vkBindBufferMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkBindBufferMemory"))) orelse return error.FunctionNotFound,
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
                    .destroy_command_pool = @as(c.PFN_vkDestroyCommandPool, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyCommandPool"))) orelse return error.FunctionNotFound,
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
                    .end_render_pass = @as(c.PFN_vkCmdEndRenderPass, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCmdEndRenderPass"))) orelse return error.FunctionNotFound,
                    .end_command_buffer = @as(c.PFN_vkEndCommandBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkEndCommandBuffer"))) orelse return error.FunctionNotFound,
                    .reset_command_buffer = @as(c.PFN_vkResetCommandBuffer, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkResetCommandBuffer"))) orelse return error.FunctionNotFound,
                    .free_memory = @as(c.PFN_vkFreeMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkFreeMemory"))) orelse return error.FunctionNotFound,
                    .free_command_buffers = @as(c.PFN_vkFreeCommandBuffers, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkFreeCommandBuffers"))) orelse return error.FunctionNotFound,
                    .map_memory = @as(c.PFN_vkMapMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkMapMemory"))) orelse return error.FunctionNotFound,
                    .unmap_memory = @as(c.PFN_vkUnmapMemory, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkUnmapMemory"))) orelse return error.FunctionNotFound,
                    .destroy = @as(c.PFN_vkDestroyDevice, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyDevice"))) orelse return error.FunctionNotFound,
                },
                .queues = queues,
                .physical_device = physical_device,
                .memory_properties = memory_properties,
            };
        }

        pub fn get_device_queue(self: Device, family_index: u32) c.VkQueue {
            var queue: c.VkQueue = undefined;
            self.dispatch.get_device_queue(self.handle, family_index, 0, &queue);

            return queue;
        }

        pub fn get_swapchain_images(self: Device, swapchain: c.VkSwapchainKHR, allocator: std.mem.Allocator) ![]c.VkImage {
            var count: u32 = undefined;

            try check(self.dispatch.get_swapchain_images(self.handle, swapchain, &count, null));
            const images = allocator.alloc(c.VkImage, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});

                return error.OutOfMemory;
            };
            try check(self.dispatch.get_swapchain_images(self.handle, swapchain, &count, images.ptr));

            return images;
        }

        pub fn get_image_memory_requirements(self: Device, image: c.VkImage) c.VkMemoryRequirements {
            var requirements: c.VkMemoryRequirements = undefined;
            self.dispatch.get_image_memory_requirements(self.handle, image, &requirements);

            return requirements;
        }

        pub fn get_buffer_memory_requirements(self: Device, buffer: c.VkBuffer) c.VkMemoryRequirements {
            var requirements: c.VkMemoryRequirements = undefined;
            self.dispatch.get_buffer_memory_requirements(self.handle, buffer, &requirements);

            return requirements;
        }

        pub fn bind_buffer_memory(self: Device, buffer: c.VkBuffer, memory: c.VkDeviceMemory) !void {
            try check(self.dispatch.bind_buffer_memory(self.handle, buffer, memory, 0));
        }

        pub fn create_image_view(self: Device, info: c.VkImageViewCreateInfo) !c.VkImageView {
            var view: c.VkImageView = undefined;
            try check(self.dispatch.create_image_view(self.handle, &info, null, &view));

            return view;
        }

        pub fn create_shader_module(self: Device, info: c.VkShaderModuleCreateInfo) !c.VkShaderModule {
            var shader_module: c.VkShaderModule = undefined;
            try check(self.dispatch.create_shader_module(self.handle, &info, null, &shader_module));

            return shader_module;
        }

        pub fn create_pipeline_layout(self: Device, info: c.VkPipelineLayoutCreateInfo) !c.VkPipelineLayout {
            var layout: c.VkPipelineLayout = undefined;
            try check(self.dispatch.create_pipeline_layout(self.handle, &info, null, &layout));

            return layout;
        }

        pub fn create_graphics_pipeline(self: Device, info: c.VkGraphicsPipelineCreateInfo) !c.VkPipeline {
            var pipeline: c.VkPipeline = undefined;
            try check(self.dispatch.create_graphics_pipeline(self.handle, null, 1, &info, null, &pipeline));

            return pipeline;
        }

        pub fn create_render_pass(self: Device, info: c.VkRenderPassCreateInfo) !c.VkRenderPass {
            var render_pass: c.VkRenderPass = undefined;
            try check(self.dispatch.create_render_pass(self.handle, &info, null, &render_pass));

            return render_pass;
        }

        pub fn create_framebuffer(self: Device, info: c.VkFramebufferCreateInfo) !c.VkFramebuffer {
            var framebuffer: c.VkFramebuffer = undefined;
            try check(self.dispatch.create_framebuffer(self.handle, &info, null, &framebuffer));

            return framebuffer;
        }

        pub fn create_command_pool(self: Device, info: c.VkCommandPoolCreateInfo) !c.VkCommandPool {
            var command_pool: c.VkCommandPool = undefined;
            try check(self.dispatch.create_command_pool(self.handle, &info, null, &command_pool));

            return command_pool;
        }

        pub fn create_semaphore(self: Device, info: c.VkSemaphoreCreateInfo) !c.VkSemaphore {
            var semaphore: c.VkSemaphore = undefined;
            try check(self.dispatch.create_semaphore(self.handle, &info, null, &semaphore));

            return semaphore;
        }

        pub fn create_fence(self: Device, info: c.VkFenceCreateInfo) !c.VkFence {
            var fence: c.VkFence = undefined;
            try check(self.dispatch.create_fence(self.handle, &info, null, &fence));

            return fence;
        }

        pub fn create_buffer(self: Device, info: c.VkBufferCreateInfo) !c.VkBuffer {
            var buffer: c.VkBuffer = undefined;
            try check(self.dispatch.create_buffer(self.handle, &info, null, &buffer));

            return buffer;
        }

        pub fn map_memory(self: Device, memory: c.VkDeviceMemory, comptime T: type, buffer: []const T) !void {
            var data: ?*anyopaque = undefined;

            try check(self.dispatch.map_memory(self.handle, memory, 0, buffer.len * @sizeOf(T), 0, &data));
            @memcpy(@as([*]T, @ptrCast(@alignCast(data))), buffer);
            self.unmap_memory(memory);
        }

        pub fn unmap_memory(self: Device, memory: c.VkDeviceMemory) void {
            self.dispatch.unmap_memory(self.handle, memory);
        }

        pub fn wait_for_fences(self: Device, fence: *c.VkFence) !void {
            const MAX: u64 = 0xFFFFFFFFFFFFFFFF;
            try check(self.dispatch.wait_for_fences(self.handle, 1, fence, c.VK_TRUE, MAX));
        }

        pub fn reset_fences(self: Device, fence: *c.VkFence) !void {
            try check(self.dispatch.reset_fences(self.handle, 1, fence));
        }

        pub fn allocate_command_buffer(self: Device, info: c.VkCommandBufferAllocateInfo) !c.VkCommandBuffer {
            var command_buffer: c.VkCommandBuffer = undefined;
            try check(self.dispatch.allocate_command_buffer(self.handle, &info, &command_buffer));

            return command_buffer;
        }

        pub fn allocate_memory(self: Device, info: c.VkMemoryAllocateInfo) !c.VkDeviceMemory {
            var memory: c.VkDeviceMemory = undefined;
            try check(self.dispatch.allocate_memory(self.handle, &info, null, &memory));

            return memory;
        }

        pub fn acquire_next_image(self: Device, swapchain: *Swapchain, semaphore: c.VkSemaphore) !u32 {
            const MAX: u64 = 0xFFFFFFFFFFFFFFFF;
            var index: u32 = undefined;
            try check(self.dispatch.acquire_next_image(self.handle, swapchain.handle, MAX, semaphore, null, &index));

            return index;
        }

        pub fn queue_submit(self: Device, info: c.VkSubmitInfo, fence: c.VkFence) !void {
            try check(self.dispatch.queue_submit(self.queues[0].handle, 1, &info, fence));
        }

        pub fn queue_present(self: Device, info: c.VkPresentInfoKHR) !void {
            try check(self.dispatch.queue_present(self.queues[1].handle, &info));
        }

        pub fn queue_wait_idle(self: Device, queue: c.VkQueue) !void {
            try check(self.dispatch.queue_wait_idle(queue));
        }

        pub fn begin_command_buffer(self: Device, command_buffer: c.VkCommandBuffer, info: c.VkCommandBufferBeginInfo) !void {
            try check(self.dispatch.begin_command_buffer(command_buffer, &info));
        }

        pub fn cmd_begin_render_pass(self: Device, command_buffer: c.VkCommandBuffer, info: c.VkRenderPassBeginInfo) void {
            self.dispatch.cmd_begin_render_pass(command_buffer, &info, c.VK_SUBPASS_CONTENTS_INLINE);
        }

        pub fn cmd_bind_pipeline(self: Device, command_buffer: c.VkCommandBuffer, pipeline: c.VkPipeline) void {
            self.dispatch.cmd_bind_pipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        }

        pub fn cmd_bind_vertex_buffer(self: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
            self.dispatch.cmd_bind_vertex_buffer(command_buffer, 0, 1, &buffer, &0);
        }

        pub fn cmd_bind_index_buffer(self: Device, command_buffer: c.VkCommandBuffer, buffer: c.VkBuffer) void {
            self.dispatch.cmd_bind_index_buffer(command_buffer, buffer, 0, c.VK_INDEX_TYPE_UINT16);
        }

        pub fn cmd_set_viewport(self: Device, command_buffer: c.VkCommandBuffer, viewport: c.VkViewport) void {
            self.dispatch.cmd_set_viewport(command_buffer, 0, 1, &viewport);
        }

        pub fn cmd_set_scissor(self: Device, command_buffer: c.VkCommandBuffer, scissor: c.VkRect2D) void {
            self.dispatch.cmd_set_scissor(command_buffer, 0, 1, &scissor);
        }

        pub fn cmd_copy_buffer(self: Device, command_buffer: c.VkCommandBuffer, src: c.VkBuffer, dst: c.VkBuffer, copy: c.VkBufferCopy) void {
            self.dispatch.cmd_copy_buffer(command_buffer, src, dst, 1, &copy);
        }

        pub fn cmd_draw(self: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
            self.dispatch.cmd_draw(command_buffer, size, 1, 0, 0);
        }

        pub fn cmd_draw_indexed(self: Device, command_buffer: c.VkCommandBuffer, size: u32) void {
            self.dispatch.cmd_draw_indexed(command_buffer, size, 1, 0, 0, 0);
        }

        pub fn end_render_pass(self: Device, command_buffer: c.VkCommandBuffer) void {
            self.dispatch.end_render_pass(command_buffer);
        }

        pub fn end_command_buffer(self: Device, command_buffer: c.VkCommandBuffer) !void {
            try check(self.dispatch.end_command_buffer(command_buffer));
        }

        pub fn reset_command_buffer(self: Device, command_buffer: c.VkCommandBuffer) !void {
            try check(self.dispatch.reset_command_buffer(command_buffer, 0));
        }

        pub fn destroy_command_pool(self: Device, command_pool: c.VkCommandPool) void {
            self.dispatch.destroy_command_pool(self.handle, command_pool);
        }

        pub fn destroy_swapchain(self: Device, swapchain: c.VkSwapchainKHR) void {
            self.dispatch.destroy_swapchain(self.handle, swapchain, null);
        }

        pub fn destroy_shader_module(self: Device, shader_module: c.VkShaderModule) void {
            self.dispatch.destroy_shader_module(self.handle, shader_module, null);
        }

        pub fn destroy_pipeline(self: Device, pipeline: c.VkPipeline) void {
            self.dispatch.destroy_pipeline(self.handle, pipeline, null);
        }

        pub fn destroy_pipeline_layout(self: Device, pipeline_layout: c.VkPipelineLayout) void {
            self.dispatch.destroy_pipeline_layout(self.handle, pipeline_layout, null);
        }

        pub fn destroy_render_pass(self: Device, render_pass: c.VkRenderPass) void {
            self.dispatch.destroy_render_pass(self.handle, render_pass, null);
        }

        pub fn destroy_semaphore(self: Device, semaphore: c.VkSemaphore) void {
            self.dispatch.destroy_semaphore(self.handle, semaphore, null);
        }

        pub fn destroy_fence(self: Device, fence: c.VkFence) void {
            self.dispatch.destroy_fence(self.handle, fence, null);
        }

        pub fn destroy_image_view(self: Device, image_view: c.VkImageView) void {
            self.dispatch.destroy_image_view(self.handle, image_view, null);
        }

        pub fn destroy_framebuffer(self: Device, framebuffer: c.VkFramebuffer) void {
            self.dispatch.destroy_framebuffer(self.handle, framebuffer, null);
        }

        pub fn destroy_buffer(self: Device, buffer: c.VkBuffer) void {
            self.dispatch.destroy_buffer(self.handle, buffer, null);
        }

        pub fn free_memory(self: Device, memory: c.VkDeviceMemory) void {
            self.dispatch.free_memory(self.handle, memory, null);
        }

        pub fn free_command_buffers(self: Device, command_pool: c.VkCommandPool, n: u32, command_buffer: *const c.VkCommandBuffer) void {
            self.dispatch.free_command_buffers(self.handle, command_pool, n, command_buffer);
        }

        pub fn destroy(self: Device) void {
            self.dispatch.destroy(self.handle, null);
        }
    };

    pub const Swapchain = struct {
        handle: c.VkSwapchainKHR,
        extent: c.VkExtent2D,
        image_views: []c.VkImageView,
        format: c.VkFormat,
        depth_format: c.VkFormat,
        framebuffers: []c.VkFramebuffer,
        arena: std.heap.ArenaAllocator,

        pub fn new(device: Device, instance: Instance, window: Window, opt_arena: ?std.heap.ArenaAllocator) !Swapchain {
            var arena = opt_arena orelse std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();

            const formats = instance.get_physical_device_surface_formats(device.physical_device, window.surface, allocator) catch |e| {
                configuration.logger.log(.Error, "Failed to list surface formats", .{});

                return e;
            };

            const format = blk: for (formats) |format| {
                if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                    break :blk format;
                }
            } else {
                configuration.logger.log(.Warn, "Could not find a good surface format falling back to first in list", .{});

                break :blk formats[0];
            };

            const present_modes = instance.get_physical_device_surface_present_modes(device.physical_device, window.surface, allocator) catch |e| {
                configuration.logger.log(.Error, "Failed to list present modes", .{});

                return e;
            };

            const present_mode = blk: for (present_modes) |mode| {
                if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) break :blk mode;
            } else {
                configuration.logger.log(.Warn, "Could not find a better present mode falling back to 'Fifo'", .{});

                break :blk c.VK_PRESENT_MODE_FIFO_KHR;
            };

            const capabilities = instance.get_physical_device_surface_capabilities(device.physical_device, window.surface) catch |e| {
                configuration.logger.log(.Error, "Could not access physical device capabilities", .{});

                return e;
            };

            const extent: c.VkExtent2D = blk: {
                if (capabilities.currentExtent.width != 0xFFFFFFFF) {
                    break :blk capabilities.currentExtent;
                } else {
                    const window_extent = Glfw.get_framebuffer_size(window.handle);
                    break :blk .{
                        .width = std.math.clamp(window_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
                        .height = std.math.clamp(window_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
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

            const uniques_queue_family_index = Device.Queue.uniques(&.{
                device.queues[0].family,
                device.queues[1].family,
            }, allocator) catch |e| {
                configuration.logger.log(.Error, "Failed to get uniques queue family index list", .{});

                return e;
            };

            var handle: c.VkSwapchainKHR = undefined;
            try check(device.dispatch.create_swapchain(device.handle, &.{
                .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                .surface = window.surface,
                .minImageCount = image_count,
                .imageFormat = format.format,
                .imageColorSpace = format.colorSpace,
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
                }, null, &handle));

            const images = device.get_swapchain_images(handle, allocator) catch |e| {
                configuration.logger.log(.Error, "Failed to get swapchain images", .{});

                return e;
            };

            const image_views = allocator.alloc(c.VkImageView, images.len) catch |e| {
                configuration.logger.log(.Error, "Out of memory", .{});

                return e;
            };

            for (0..images.len) |i| {
                image_views[i] = device.create_image_view(.{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                    .image = images[i],
                    .format = format.format,
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
                    configuration.logger.log(.Error, "Failed to get image view from image", .{});

                    return e;
                };
            }

            const depth_formats = [_]c.VkFormat {
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
                configuration.logger.log(.Error, "Failed to find suitable depth format", .{});

                return error.DepthFormat;
            };

            return .{
                .handle = handle,
                .image_views = image_views,
                .format = format.format,
                .depth_format = depth_format,
                .extent = extent,
                .framebuffers = try allocator.alloc(c.VkFramebuffer, images.len),
                .arena = arena,
            };
        }

        pub fn has_to_recreate(e: VkResult) bool {
            return (e == VkResult.SuboptimalKhr or e == VkResult.OutOfDateKhr);
        }

        pub fn recreate(self: *Swapchain, device: Device, instance: Instance, pipeline: GraphicsPipeline, window: Window) !void {
            while (true) {
                var extent = Glfw.get_framebuffer_size(window.handle);
                if (extent.width == 0 or extent.height == 0) {
                    Glfw.wait_events();
                    extent = Glfw.get_framebuffer_size(window.handle);
                } else {
                    break;
                }
            }

            self.destroy(device);
            const new_swapchain = try new(device, instance, window, self.arena);
            const allocator = self.arena.allocator();

            self.handle = new_swapchain.handle;
            self.image_views = new_swapchain.image_views;
            self.format = new_swapchain.format;
            self.depth_format = new_swapchain.depth_format;
            self.extent = new_swapchain.extent;
            self.framebuffers = try allocator.alloc(c.VkFramebuffer, new_swapchain.image_views.len);

            for (0..new_swapchain.image_views.len) |i| {
                self.framebuffers[i] = device.create_framebuffer(.{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .renderPass = pipeline.render_pass,
                    .attachmentCount = 1,
                    .pAttachments = &new_swapchain.image_views[i],
                    .width = new_swapchain.extent.width,
                    .height = new_swapchain.extent.height,
                    .layers = 1,
                }) catch |e| {
                    configuration.logger.log(.Error, "Failed to crate frambuffer", .{});

                    return e;
                };
            }
        }

        pub fn acquire_next_image(self: *Swapchain, device: Device, sync: Sync) !u32 {
            return try device.acquire_next_image(self, sync.image_available);
        }

        pub fn queue_pass(self: Swapchain, device: Device, command_pool: CommandPool, sync: Sync, index: u32) !void {
            try device.queue_submit(.{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &sync.image_available,
                .pWaitDstStageMask = &@as(u32, @intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)),
                .commandBufferCount = 1,
                .pCommandBuffers = &command_pool.buffer,
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &sync.render_finished,
            }, sync.in_flight_fence);

            try device.queue_present(.{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &sync.render_finished,
                .swapchainCount = 1,
                .pSwapchains = &self.handle,
                .pImageIndices = &index,
                .pResults = null,
            });
        }

        pub fn destroy(self: *Swapchain, device: Device) void {
            _ = self.arena.reset(.free_all);

            device.destroy_swapchain(self.handle);
        }
    };

    pub const Window = struct {
        handle: *Glfw.Window,
        surface: c.VkSurfaceKHR,
        width: u32,
        height: u32,

        pub fn new(instance: Instance, width: u32, height: u32) !Window {
            const handle = Glfw.create_window(width, height, &configuration.application_name[0]) catch |e| {
                configuration.logger.log(.Error, "Glfw failed to create window", .{});

                return e;
            };
            const surface = Glfw.create_window_surface(instance, handle, null) catch |e| {
                configuration.logger.log(.Error, "Failed to create window surface", .{});

                return e;
            };

            return .{
                .handle = handle,
                .surface = surface,
                .width = width,
                .height = height,
            };
        }

        pub fn destroy(self: Window, instance: Instance) void {
            configuration.logger.log(.Info, "Closing window", .{});
            instance.destroy_surface(self.surface);
            Glfw.destroy_window(self.handle);
        }
    };

    pub const GraphicsPipeline = struct {
        handle: c.VkPipeline,
        layout: c.VkPipelineLayout,
        render_pass: c.VkRenderPass,

        pub fn new(device: Device, swapchain: Swapchain, allocator: std.mem.Allocator) !GraphicsPipeline {
            const vert_code = Io.read_file("assets/vert.spv", allocator) catch |e| {
                configuration.logger.log(.Error, "Could not read vertex shader byte code", .{});

                return e;
            };

            const frag_code = Io.read_file("assets/frag.spv", allocator) catch |e| {
                configuration.logger.log(.Error, "Could not read fragment shader byte code", .{});

                return e;
            };

            const vert_module = device.create_shader_module(.{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = vert_code.len,
                .pCode = @as([*c]const u32, @ptrCast(@alignCast(vert_code))),
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to create vertex shader module", .{});

                return e;
            };

            defer device.destroy_shader_module(vert_module);

            const frag_module = device.create_shader_module(.{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = frag_code.len,
                .pCode = @as([*c]const u32, @ptrCast(@alignCast(frag_code))),
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to create fragment shader module", .{});

                return e;
            };

            defer device.destroy_shader_module(frag_module);

            const shader_stage_infos = [_]c.VkPipelineShaderStageCreateInfo {
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

            const dynamic_states = [_]c.VkDynamicState { c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
            const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .dynamicStateCount = dynamic_states.len,
                .pDynamicStates = &dynamic_states[0],
            };

            const vertex_input_state_info: c.VkPipelineVertexInputStateCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .vertexBindingDescriptionCount = 1,
                .pVertexBindingDescriptions = &BufferHandle.Vertex.binding_description,
                .vertexAttributeDescriptionCount = BufferHandle.Vertex.attribute_descriptions.len,
                .pVertexAttributeDescriptions = &BufferHandle.Vertex.attribute_descriptions[0],
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
                    .width = @as(f32, @floatFromInt(swapchain.extent.width)),
                    .height = @as(f32, @floatFromInt(swapchain.extent.height)),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                },
                .pScissors = &.{
                    .offset = .{.x = 0, .y = 0},
                    .extent = swapchain.extent,
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

            const layout = device.create_pipeline_layout(.{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .setLayoutCount = 0,
                .pSetLayouts = null,
                .pushConstantRangeCount = 0,
                .pPushConstantRanges = null,
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to create pipeline layout", .{});

                return e;
            };

            const render_pass = device.create_render_pass(.{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                .attachmentCount = 1,
                .pAttachments = &.{
                    .format = swapchain.format,
                    .samples = c.VK_SAMPLE_COUNT_1_BIT,
                    .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                    .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                },
                .subpassCount = 1,
                .pSubpasses = &.{
                    .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    .colorAttachmentCount = 1,
                    .pColorAttachments = &.{
                        .attachment = 0,
                        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    },
                },
                .dependencyCount = 1,
                .pDependencies = &.{
                    .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                    .dstSubpass = 0,
                    .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .srcAccessMask = 0,
                    .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                },
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to create render pass", .{});

                return e;
            };

            const handle = device.create_graphics_pipeline(.{
                    .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                    .stageCount = shader_stage_infos.len,
                    .pStages = &shader_stage_infos[0],
                    .pVertexInputState = &vertex_input_state_info,
                    .pInputAssemblyState = &input_assembly_state_info,
                    .pViewportState = &viewport_state_info,
                    .pRasterizationState = &rasterizer_state_info,
                    .pMultisampleState = &multisampling_state_info,
                    .pDynamicState = &dynamic_state_info,
                    .pColorBlendState = &color_blend_state_info,
                    .layout = layout,
                    .renderPass = render_pass,
                    .subpass = 0,
                    .basePipelineHandle = null,
                    .pDepthStencilState = null,
                }) catch |e| {
                    configuration.logger.log(.Error, "Failed to create graphics pipeline", .{});

                    return e;
            };

            for (0..swapchain.image_views.len) |i| {
                swapchain.framebuffers[i] = device.create_framebuffer(.{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .renderPass = render_pass,
                    .attachmentCount = 1,
                    .pAttachments = &swapchain.image_views[i],
                    .width = swapchain.extent.width,
                    .height = swapchain.extent.height,
                    .layers = 1,
                }) catch |e| {
                    configuration.logger.log(.Error, "Failed to crate frambuffer", .{});

                    return e;
                };
            }

            return .{
                .handle = handle,
                .layout = layout,
                .render_pass = render_pass,
            };
        }

        pub fn destroy(self: GraphicsPipeline, device: Device) void {
            device.destroy_pipeline(self.handle);
            device.destroy_pipeline_layout(self.layout);
            device.destroy_render_pass(self.render_pass);
        }
    };

    pub const CommandPool = struct {
        handle: c.VkCommandPool,
        buffer: c.VkCommandBuffer,

        pub fn record(self: CommandPool, device: Device, pipeline: GraphicsPipeline, swapchain: Swapchain, buffers: BufferHandle, index: u32) !void {
            try device.reset_command_buffer(self.buffer);
            try device.begin_command_buffer(self.buffer, .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = 0,
                .pInheritanceInfo = null,
            });

            device.cmd_begin_render_pass(self.buffer, .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .renderPass = pipeline.render_pass,
                .framebuffer = swapchain.framebuffers[index],
                .renderArea = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = swapchain.extent,
                },
                .pClearValues= &.{ .color = .{ .float32 = .{0.0, 0.0, 0.0, 1.0}, } },
                .clearValueCount = 1,
            });

            device.cmd_bind_pipeline(self.buffer, pipeline.handle);
            device.cmd_bind_vertex_buffer(self.buffer, buffers.vertex.handle);
            device.cmd_bind_index_buffer(self.buffer, buffers.index.handle);
            device.cmd_set_viewport(self.buffer, .{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(swapchain.extent.width)),
                .height = @as(f32, @floatFromInt(swapchain.extent.height)),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            });

            device.cmd_set_scissor(self.buffer, .{
                .offset = .{ .x = 0, .y = 0},
                .extent = swapchain.extent,
            });

            // device.cmd_draw(self.buffer, BufferHandle.Vertex.default.len);
            device.cmd_draw_indexed(self.buffer, BufferHandle.Index.default.len);
            device.end_render_pass(self.buffer);
            device.end_command_buffer(self.buffer) catch {
                configuration.logger.log(.Warn, "Failed to end command buffer", .{});
            };
        }

        pub fn new(device: Device) !CommandPool {
            const handle = device.create_command_pool(.{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                .queueFamilyIndex = device.queues[0].family,
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to create command pool", .{});

                return e;
            };

            const buffer= device.allocate_command_buffer(.{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = handle,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = 1,
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to allocate command buffer", .{});

                return e;
            };

            return .{
                .buffer = buffer,
                .handle = handle,
            };
        }

        pub fn destroy(self: CommandPool, device: Device) void {
            device.destroy_command_pool(self.handle);
        }
    };

    pub const Sync = struct {
        image_available: c.VkSemaphore,
        render_finished: c.VkSemaphore,
        in_flight_fence: c.VkFence,

        pub fn new(device: Device) !Sync {
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
            };
        }

        pub fn wait(self: *Sync, device: Device) !void {
            try device.wait_for_fences(&self.in_flight_fence);
            try device.reset_fences(&self.in_flight_fence);
        }

        pub fn destroy(self: Sync, device: Device) void {
            device.destroy_semaphore(self.image_available);
            device.destroy_semaphore(self.render_finished);
            device.destroy_fence(self.in_flight_fence);
        }
    };

    pub const BufferHandle = struct {
        index: Buffer,
        vertex: Buffer,

        pub const Buffer = struct {
            handle: c.VkBuffer,
            memory: c.VkDeviceMemory,

            fn new(
                device: Device,
                command_pool: c.VkCommandPool,
                memory_properties: c.VkPhysicalDeviceMemoryProperties,
                opt_usage: ?c.VkBufferUsageFlags,
                opt_properties: ?c.VkMemoryPropertyFlags,
                comptime T: type,
                data: ?[]const T,
                size: u32,
            ) !Buffer {
                const usage = opt_usage orelse c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
                const properties = opt_properties orelse c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

                const buffer = try device.create_buffer(.{
                    .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                    .size = size,
                    .usage = usage,
                    .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                });

                const memory_requirements = device.get_buffer_memory_requirements(buffer);

                const index = blk: for (0..memory_properties.memoryTypeCount) |i| {
                    if ((memory_requirements.memoryTypeBits & (@as(u32, @intCast(1)) << @as(u5, @intCast(i)))) != 0 and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                        break :blk i;
                    }
                } else {
                    configuration.logger.log(.Error, "Could not find memory type that suit the need of buffer allocation", .{});
                    return error.NoMemoryRequirementsPassed;
                };

                const memory = try device.allocate_memory(.{
                    .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                    .allocationSize = memory_requirements.size,
                    .memoryTypeIndex = @as(u32, @intCast(index)),
                });

                try device.bind_buffer_memory(buffer, memory);

                if (data) |b| {
                    const staging_buffer = try Buffer.new(device, command_pool, memory_properties, null, null, T, null, size);
                    try device.map_memory(staging_buffer.memory, T, b);

                    const command_buffer = device.allocate_command_buffer(.{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                        .commandPool = command_pool,
                        .commandBufferCount = 1,
                    }) catch |e| {
                        configuration.logger.log(.Error, "Failed to allocate command buffer", .{});

                        return e;
                    };

                    try device.begin_command_buffer(command_buffer, .{
                        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
                    });

                    device.cmd_copy_buffer(command_buffer, staging_buffer.handle, buffer, .{
                        .srcOffset = 0,
                        .dstOffset = 0,
                        .size = size,
                    });

                    try device.end_command_buffer(command_buffer);

                    try device.queue_submit(.{
                        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                        .commandBufferCount = 1,
                        .pCommandBuffers = &command_buffer,
                        }, null);

                    try device.queue_wait_idle(device.queues[0].handle);

                    device.free_command_buffers(command_pool, 1, &command_buffer);
                    device.destroy_buffer(staging_buffer.handle);
                    device.free_memory(staging_buffer.memory);
                }

                return .{
                    .handle = buffer,
                    .memory = memory,
                };
            }

            pub fn destroy(self: Buffer, device: Device) void {
                device.destroy_buffer(self.handle);
                device.free_memory(self.memory);
            }
        };

        pub const Index = struct {
            pub const default = [_]u16 {
                    0, 1, 2, 2, 3, 0
            };

            pub fn new(device: Device, command_pool: CommandPool) !Buffer {
                return try Buffer.new(
                    device,
                    command_pool.handle,
                    device.memory_properties,
                    c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    u16,
                    &default,
                    @sizeOf(u16) * default.len
                );
            }
        };

        pub const Vertex = struct {
            position: [2]f32,
            color: [3]f32,

            const Self = @This();

            pub const binding_description: c.VkVertexInputBindingDescription = .{
                .binding = 0,
                .stride = @sizeOf(Self),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            };

            pub const attribute_descriptions: [2]c.VkVertexInputAttributeDescription = .{
                .{
                    .binding = 0,
                    .location = 0,
                    .format = c.VK_FORMAT_R32G32_SFLOAT,
                    .offset = @offsetOf(Self, "position"),
                },
                .{
                    .binding = 0,
                    .location = 1,
                    .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                    .offset = @offsetOf(Self, "color"),
                },
            };

            pub const default = [_]Self {
                Self {
                    .position = .{0.0, -0.5},
                    .color = .{1.0, 0.0, 0.0},
                },
                Self {
                    .position = .{0.5, 0.5},
                    .color = .{0.0, 1.0, 0.0},
                },
                Self {
                    .position = .{-0.5, 0.5},
                    .color = .{1.0, 1.0, 1.0},
                },
            };

            pub fn new(device: Device, command_pool: CommandPool) !Buffer {
                return try Buffer.new(
                    device, command_pool.handle,
                    device.memory_properties,
                    c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                    c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                    Self,
                    &default,
                    @sizeOf(Self) * default.len
                );
            }
        };

        pub fn new(device: Device, command_pool: CommandPool) !BufferHandle {
            return .{
                .vertex = try Vertex.new(device, command_pool),
                .index = try Index.new(device, command_pool),
            };
        }

        pub fn destroy(self: BufferHandle, device: Device) void {
            self.index.destroy(device);
            self.vertex.destroy(device);
        }
    };

    pub const VkResult = error {
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
            c.VK_NOT_READY => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'NotReady", .{});
                return VkResult.NotReady;
            },
            c.VK_TIMEOUT => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'Timeout", .{});
                return VkResult.Timeout;
            },
            c.VK_EVENT_SET => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'EventSet", .{});
                return VkResult.EventSet;
            },
            c.VK_EVENT_RESET => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'EventReset", .{});
                return VkResult.EventReset;
            },
            c.VK_INCOMPLETE =>{
                configuration.logger.log(.Debug, "Result failed with VkResult: Incomplete", .{});
            },
            c.VK_ERROR_OUT_OF_HOST_MEMORY => {
                configuration.logger.log(.Debug, "Result failed with 'OutOfHostMemory", .{});
                return VkResult.OutOfHostMemory;
            },
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'OutOfDeviceMemory'", .{});
                return VkResult.OutOfDeviceMemory;
            },
            c.VK_ERROR_INITIALIZATION_FAILED => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'InitializationFailed'", .{});
                return VkResult.InitializationFailed;
            },
            c.VK_ERROR_DEVICE_LOST => {
                configuration.logger.log(.Debug, "Result failed with VkResult: 'DeviceLost'", .{});
                return VkResult.DeviceLost;
            },
            c.VK_ERROR_MEMORY_MAP_FAILED => {
                configuration.logger.log(.Debug, "Result was not a success: 'MemoryMapFailed'", .{});
                return VkResult.MemoryMapFailed;
            },
            c.VK_ERROR_LAYER_NOT_PRESENT => {
                configuration.logger.log(.Debug, "Result was not a success: 'LayerNotPresent'", .{});
                return VkResult.LayerNotPresent;
            },
            c.VK_ERROR_EXTENSION_NOT_PRESENT => {
                configuration.logger.log(.Debug, "Result was not a success: 'ExtensionNotPresent'", .{});
                return VkResult.ExtensionNotPresent;
            },
            c.VK_ERROR_FEATURE_NOT_PRESENT => {
                configuration.logger.log(.Debug, "Result was not a success: 'FeatureNotPresent'", .{});
                return VkResult.FeatureNotPresent;
            },
            c.VK_ERROR_INCOMPATIBLE_DRIVER => {
                configuration.logger.log(.Debug, "Result was not a success: 'IncompatibleDriver'", .{});
                return VkResult.IncompatibleDriver;
            },
            c.VK_ERROR_TOO_MANY_OBJECTS => {
                configuration.logger.log(.Debug, "Result was not a success: 'TooManyObjects'", .{});
                return VkResult.TooManyObjects;
            },
            c.VK_ERROR_FORMAT_NOT_SUPPORTED => {
                configuration.logger.log(.Debug, "Result was not a success: 'FormatNotSupported'", .{});
                return VkResult.FormatNotSupported;
            },
            c.VK_ERROR_FRAGMENTED_POOL => {
                configuration.logger.log(.Debug, "Result was not a success: 'FragmentedPool'", .{});
                return VkResult.FragmentedPool;
            },
            c.VK_ERROR_UNKNOWN => {
                configuration.logger.log(.Debug, "Result was not a success: 'Unknown'", .{});
                return VkResult.Unknown;
            },
            c.VK_ERROR_INVALID_EXTERNAL_HANDLE => {
                configuration.logger.log(.Debug, "Result was not a success: 'InvalidExternalHandle'", .{});
                return VkResult.InvalidExternalHandle;
            },
            c.VK_ERROR_FRAGMENTATION => {
                configuration.logger.log(.Debug, "Result was not a success: 'Fragmentation'", .{});
                return VkResult.Fragmentation;
            },
            c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => {
                configuration.logger.log(.Debug, "Result was not a success: 'InvalidOpaqueCaptureAddress'", .{});
                return VkResult.InvalidOpaqueCaptureAddress;
            },
            c.VK_PIPELINE_COMPILE_REQUIRED => {
                configuration.logger.log(.Debug, "Result was not a success: 'PipelineCompileRequired'", .{});
                return VkResult.PipelineCompileRequired;
            },
            c.VK_ERROR_SURFACE_LOST_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'SurfaceLostKhr'", .{});
                return VkResult.SurfaceLostKhr;
            },
            c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'NativeWindowInUseKhr'", .{});
                return VkResult.NativeWindowInUseKhr;
            },
            c.VK_SUBOPTIMAL_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'SuboptimalKhr'", .{});
                return VkResult.SuboptimalKhr;
            },
            c.VK_ERROR_OUT_OF_DATE_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'OutOfDateKhr'", .{});
                return VkResult.OutOfDateKhr;
            },
            c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'IncompatibleDisplayKhr'", .{});
                return VkResult.IncompatibleDisplayKhr;
            },
            c.VK_ERROR_VALIDATION_FAILED_EXT => {
                configuration.logger.log(.Debug, "Result was not a success: 'ValidationFailedExt'", .{});
                return VkResult.ValidationFailedExt;
            },
            c.VK_ERROR_INVALID_SHADER_NV => {
                configuration.logger.log(.Debug, "Result was not a success: 'InvalidShaderNv'", .{});
                return VkResult.InvalidShaderNv;
            },
            c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'ImageUsageNotSupportedKhr'", .{});
                return VkResult.ImageUsageNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'VideoPictureLayoutNotSupportedKhr'", .{});
                return VkResult.VideoPictureLayoutNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'VideoProfileOperationNotSupportedKhr'", .{});
                return VkResult.VideoProfileOperationNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'VideoProfileFormatNotSupportedKhr'", .{});
                return VkResult.VideoProfileFormatNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'VideoProfileCodecNotSupportedKhr'", .{});
                return VkResult.VideoProfileCodecNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'VideoStdVersionNotSupportedKhr'", .{});
                return VkResult.VideoStdVersionNotSupportedKhr;
            },
            c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => {
                configuration.logger.log(.Debug, "Result was not a success: 'InvalidDrmFormatModifierPlaneLayoutExt'", .{});
                return VkResult.InvalidDrmFormatModifierPlaneLayoutExt;
            },
            c.VK_ERROR_NOT_PERMITTED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'NotPermittedKhr'", .{});
                return VkResult.NotPermittedKhr;
            },
            c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => {
                configuration.logger.log(.Debug, "Result was not a success: 'FullScreenExclusiveModeLostExt'", .{});
                return VkResult.FullScreenExclusiveModeLostExt;
            },
            c.VK_THREAD_IDLE_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'ThreadIdleKhr'", .{});
                return VkResult.ThreadIdleKhr;
            },
            c.VK_THREAD_DONE_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'ThreadDoneKhr'", .{});
                return VkResult.ThreadDoneKhr;
            },
            c.VK_OPERATION_DEFERRED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'OperationDeferredKhr'", .{});
                return VkResult.OperationDeferredKhr;
            },
            c.VK_OPERATION_NOT_DEFERRED_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'OperationNotDeferredKhr'", .{});
                return VkResult.OperationNotDeferredKhr;
            },
            c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'InvalidVideoStdParametersKhr'", .{});
                return VkResult.InvalidVideoStdParametersKhr;
            },
            c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => {
                configuration.logger.log(.Debug, "Result was not a success: 'CompressionExhaustedExt'", .{});
                return VkResult.CompressionExhaustedExt;
            },
            c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => {
                configuration.logger.log(.Debug, "Result was not a success: 'IncompatibleShaderBinaryExt'", .{});
                return VkResult.IncompatibleShaderBinaryExt;
            },
            c.VK_ERROR_OUT_OF_POOL_MEMORY_KHR => {
                configuration.logger.log(.Debug, "Result was not a success: 'OutOfPoolMemoryKhr'", .{});
                return VkResult.OutOfPoolMemoryKhr;
            },

            else => {
                configuration.logger.log(.Debug, "Result was not a success, ({})", .{result});
                return VkResult.Else;
            }
        }
    }

    pub fn bit(one: u32, other: u32) bool {
        return (one & other) != 0;
    }

    pub fn boolean(flag: u32) bool {
        return flag == c.VK_TRUE;
    }
};
