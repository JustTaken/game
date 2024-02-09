const std = @import("std");
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("GLFW/glfw3.h");
});

const _utility = @import("../utility.zig");
const configuration = _utility.Configuration;

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

    pub fn create_window_surface(instance: Vulkan.Instance, window: *Window, callback: ?*Vulkan.AllocationCallbacks) !Vulkan.Surface {
        var surface: Vulkan.Surface = undefined;
        if (c.glfwCreateWindowSurface(instance.handler, window, callback, &surface) != c.VK_SUCCESS) return error.lksjdafklj;
        return surface;
    }

    pub fn get_framebuffer_size(window: *Window) Vulkan.Extent {
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
        handler: c.VkInstance,
        allocator: std.mem.Allocator,
        dispatch: Dispatch,

        pub const Dispatch = struct {
            destroy_surface: *const fn (c.VkInstance, Surface, ?*const AllocationCallbacks) callconv(.C) void,
            enumerate_physical_devices: *const fn (c.VkInstance, *u32, ?[*]PhysicalDevice) callconv(.C) i32,
            enumerate_device_extension_properties: *const fn (PhysicalDevice, ?[*]const u8, *u32, ?[*]ExtensionProperties) callconv(.C) i32,
            get_physical_device_properties: *const fn (PhysicalDevice, ?*PhysicalDeviceProperties) callconv(.C) void,
            get_physical_device_features: *const fn (PhysicalDevice, ?*PhysicalDeviceFeatures) callconv(.C) void,
            get_physical_device_surface_formats: *const fn (PhysicalDevice, Surface, *u32, ?[*]SurfaceFormat) callconv(.C) i32,
            get_physical_device_surface_present_modes: *const fn (PhysicalDevice, Surface, *u32, ?[*]PresentMode) callconv(.C) i32,
            get_physical_device_queue_family_properties: *const fn (PhysicalDevice, *u32, ?[*]QueueFamilyProperties) callconv(.C) void,
            get_physical_device_surface_capabilities: *const fn (PhysicalDevice, Surface, *SurfaceCapabilities) callconv(.C) i32,
            get_physical_device_surface_support: *const fn (PhysicalDevice, u32, Surface, *u32) callconv(.C) i32,
            get_physical_device_memory_properties: *const fn (PhysicalDevice, *PhysicalDeviceMemoryProperties) callconv(.C) void,
            get_physical_device_format_properties: *const fn (PhysicalDevice, Format, *FormatProperties) callconv(.C) void,
            create_device: *const fn (PhysicalDevice, *const c.VkDeviceCreateInfo, ?*const AllocationCallbacks, ?*c.VkDevice) callconv(.C) i32,
            destroy: *const fn (c.VkInstance, ?*const AllocationCallbacks) callconv(.C) void,

        };

        pub const Application = struct {
            version: u32,
            name: []const u8,
        };

        pub const Config = struct {
            application: Application,
            layers: ?[][*:0]const u8 = null,
            extensions: [][*:0]const u8,
            allocation_callbacks: ?*AllocationCallbacks = null,
        };

        pub fn new(config: Config, allocator: std.mem.Allocator) !Instance {
            var instance: c.VkInstance = undefined;
            const PFN_vkCreateInstance = @as(c.PFN_vkCreateInstance, @ptrCast(c.glfwGetInstanceProcAddress(null, "vkCreateInstance"))) orelse return error.FunctionNotFound;

            try check(PFN_vkCreateInstance(
                &.{
                    .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                    .pApplicationInfo = &.{
                        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                        .pApplicationName = @as([*:0]const u8, @ptrCast(config.application.name)),
                        .applicationVersion = config.application.version,
                        .pEngineName = @as([*:0]const u8, @ptrCast(config.application.name)),
                        .engineVersion = config.application.version,
                        .apiVersion = ApiVersion,
                    },
                    .enabledExtensionCount = @as(u32, @intCast(config.extensions.len)),
                    .ppEnabledExtensionNames = config.extensions.ptr,
                    .ppEnabledLayerNames = if (config.layers) |l| l.ptr else null,
                    .enabledLayerCount = if (config.layers) |l| @as(u32, @intCast(l.len)) else 0,
                },
                config.allocation_callbacks,
                &instance
            ));

            const PFN_vkGetInstanceProcAddr = @as(c.PFN_vkGetInstanceProcAddr, @ptrCast(c.glfwGetInstanceProcAddress(instance, "vkGetInstanceProcAddr"))) orelse return error.FunctionNotFound;

            return .{
                .handler = instance,
                .allocator = allocator,
                .dispatch = .{
                    .destroy_surface = @as(c.PFN_vkDestroySurfaceKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkDestroySurfaceKHR"))) orelse return error.FunctionNotFound,
                    .enumerate_physical_devices = @as(c.PFN_vkEnumeratePhysicalDevices, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkEnumeratePhysicalDevices"))) orelse return error.FunctionNotFound,
                    .enumerate_device_extension_properties = @as(c.PFN_vkEnumerateDeviceExtensionProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkEnumerateDeviceExtensionProperties"))) orelse return error.FunctionNotFound,
                    .create_device = @as(c.PFN_vkCreateDevice, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkCreateDevice"))) orelse return error.FunctionNotFound,
                    .get_physical_device_properties = @as(c.PFN_vkGetPhysicalDeviceProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_features = @as(c.PFN_vkGetPhysicalDeviceFeatures, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFeatures"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_formats = @as(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_present_modes = @as(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_queue_family_properties = @as(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceQueueFamilyProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_capabilities = @as(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_surface_support = @as(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceSupportKHR"))) orelse return error.FunctionNotFound,
                    .get_physical_device_memory_properties = @as(c.PFN_vkGetPhysicalDeviceMemoryProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceMemoryProperties"))) orelse return error.FunctionNotFound,
                    .get_physical_device_format_properties = @as(c.PFN_vkGetPhysicalDeviceFormatProperties, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFormatProperties"))) orelse return error.FunctionNotFound,
                    .destroy = @as(c.PFN_vkDestroyInstance, @ptrCast(PFN_vkGetInstanceProcAddr(instance, "vkDestroyInstance"))) orelse return error.FunctionNotFound,
                },
            };
        }

        pub fn destroy_surface(self: *Instance, surface: Surface) void {
            self.dispatch.destroy_surface(self.handler, surface, null);
        }

        pub fn enumerate_physical_devices(self: *Instance) ![]PhysicalDevice {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_physical_devices(self.handler, &count, null));
            const physical_devices = self.allocator.alloc(PhysicalDevice, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(self.dispatch.enumerate_physical_devices(self.handler, &count, physical_devices.ptr));


            return physical_devices;
        }

        pub fn enumerate_device_extension_properties(self: *Instance, physical_device: PhysicalDevice) ![]ExtensionProperties {
            var count: u32 = undefined;

            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, null));
            const extension_properties = self.allocator.alloc(ExtensionProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, extension_properties.ptr));

            return extension_properties;
        }

        pub fn get_physical_device_properties(self: *Instance, physical_device: PhysicalDevice) PhysicalDeviceProperties {
            var properties: PhysicalDeviceProperties = undefined;
            self.dispatch.get_physical_device_properties(physical_device, &properties);

            return properties;
        }

        pub fn get_physical_device_features(self: *Instance, physical_device: PhysicalDevice) PhysicalDeviceFeatures {
            var features: PhysicalDeviceFeatures = undefined;
            self.dispatch.get_physical_device_features(physical_device, &features);

            return features;
        }

        pub fn get_physical_device_format_properties(self: *Instance, physical_device: PhysicalDevice, format: Format) FormatProperties {
            var properties: FormatProperties = undefined;
            self.dispatch.get_physical_device_format_properties(physical_device, format, &properties);
            return properties;
        }

        pub fn get_physical_device_surface_formats(self: *Instance, physical_device: PhysicalDevice, surface: Surface) ![]SurfaceFormat {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, null));
            const formats = self.allocator.alloc(SurfaceFormat, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(self.dispatch.get_physical_device_surface_formats(physical_device, surface, &count, formats.ptr));

            return formats;
        }

        pub fn get_physical_device_surface_present_modes(self: *Instance, physical_device: PhysicalDevice, surface: Surface) ![]PresentMode {
            var count: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, null));
            const present_modes = self.allocator.alloc(PresentMode, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface, &count, present_modes.ptr));

            return present_modes;
        }

        pub fn get_physical_device_queue_family_properties(self: *Instance, physical_device: PhysicalDevice) ![]QueueFamilyProperties {
            var count: u32 = undefined;
            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, null);
            const properties = self.allocator.alloc(QueueFamilyProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, properties.ptr);

            return properties;
        }

        pub fn get_physical_device_surface_capabilities(self: *Instance, physical_device: PhysicalDevice, surface: Surface) !SurfaceCapabilities {
            var capabilities: SurfaceCapabilities = undefined;
            try check(self.dispatch.get_physical_device_surface_capabilities(physical_device, surface, &capabilities));
            return capabilities;
        }

        pub fn get_physical_device_surface_support(self: *Instance, physical_device: PhysicalDevice, family: u32, surface: Surface) !bool {
            var flag: u32 = undefined;
            try check(self.dispatch.get_physical_device_surface_support(physical_device, family, surface, &flag));

            return flag == c.VK_TRUE;
        }

        pub fn get_physical_device_memory_properties(self: *Instance, physical_device: PhysicalDevice) PhysicalDeviceMemoryProperties {
            var properties: PhysicalDeviceMemoryProperties = undefined;
            self.dispatch.get_physical_device_memory_properties(physical_device, &properties);

            return properties;
        }

        pub fn destroy(self: *Instance) void {
            self.dispatch.destroy(self.handler, null);
        }
    };

    pub const Device = struct {
        handler: c.VkDevice,
        dispatch: Dispatch,
        allocator: std.mem.Allocator,

        pub const Dispatch = struct {
            get_device_queue: *const fn (c.VkDevice, u32, u32, *Queue) callconv(.C) void,
            get_swapchain_images: *const fn (c.VkDevice, c.VkSwapchainKHR, *u32, ?[*]Image) callconv(.C) i32,
            create_swapchain: *const fn (c.VkDevice, *const c.VkSwapchainCreateInfoKHR, ?*const AllocationCallbacks, *c.VkSwapchainKHR) callconv(.C) i32,
            create_image_view: *const fn (c.VkDevice, *const c.VkImageViewCreateInfo, ?*const AllocationCallbacks, *c.VkImageView) callconv(.C) i32,
            destroy: *const fn (c.VkDevice, ?*const AllocationCallbacks) callconv(.C) void,
        };

        pub const Config = struct {
            queues: []DeviceQueueCreateInfo,
            allocation_callbacks: ?*AllocationCallbacks = null,
            features: PhysicalDeviceFeatures,
            extensions: []const [*:0]const u8,
        };

        pub const Type = enum {
            Other,
            IntegratedGpu,
            DiscreteGpu,
            VirtualGpu,
            Cpu,
        };

        pub fn new(instance: *Instance, physical_device: PhysicalDevice, config: Config, allocator: std.mem.Allocator) !Device {
            var device: c.VkDevice = undefined;

            try check(instance.dispatch.create_device(
                physical_device,
                &.{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .queueCreateInfoCount = @as(u32 , @intCast(config.queues.len)),
                    .pQueueCreateInfos = config.queues.ptr,
                    .pEnabledFeatures = &config.features,
                    .enabledExtensionCount = @as(u32, @intCast(config.extensions.len)),
                    .ppEnabledExtensionNames = config.extensions.ptr
                },
                config.allocation_callbacks,
                &device
            ));

            const PFN_vkGetDeviceProcAddr = @as(c.PFN_vkGetDeviceProcAddr, @ptrCast(c.glfwGetInstanceProcAddress(instance.handler, "vkGetDeviceProcAddr"))) orelse return error.FunctionNotFound;

            return .{
                .handler = device,
                .dispatch = .{
                    .get_device_queue = @as(c.PFN_vkGetDeviceQueue, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetDeviceQueue"))) orelse return error.FunctionNotFound,
                    .get_swapchain_images = @as(c.PFN_vkGetSwapchainImagesKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkGetSwapchainImagesKHR"))) orelse return error.FunctionNotFound,
                    .create_swapchain = @as(c.PFN_vkCreateSwapchainKHR, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateSwapchainKHR"))) orelse return error.FunctionNotFound,
                    .create_image_view = @as(c.PFN_vkCreateImageView, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkCreateImageView"))) orelse return error.FunctionNotFound,
                    .destroy = @as(c.PFN_vkDestroyDevice, @ptrCast(PFN_vkGetDeviceProcAddr(device, "vkDestroyDevice"))) orelse return error.FunctionNotFound,
                },
                .allocator = allocator,
            };
        }

        pub fn get_device_queue(self: *Device, family_index: u32) Queue {
            var queue: Queue = undefined;
            self.dispatch.get_device_queue(self.handler, family_index, 0, &queue);

            return queue;
        }

        pub fn get_swapchain_images(self: *Device, swapchain: Swapchain) ![]Image {
            var count: u32 = undefined;
            try check(self.dispatch.get_swapchain_images(self.handler, swapchain.handler, &count, null));

            const images = self.allocator.alloc(Image, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(self.dispatch.get_swapchain_images(self.handler, swapchain.handler, &count, images.ptr));

            return images;
        }

        pub fn destroy(self: *Device) void {
            self.dispatch.destroy(self.handler, null);
        }
    };

    pub const Swapchain = struct {
        handler: c.VkSwapchainKHR,

        pub const ImageView = struct {
            handler: c.VkImageView,

            pub const Config = struct {
                image: Image,
                format: Format,
                view_type: c.VkImageViewType = c.VK_IMAGE_VIEW_TYPE_2D,
                subresource_range: c.VkImageSubresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                allocation_callbacks: ?*AllocationCallbacks = null,
            };

            pub fn new(device: Device, config: ImageView.Config) !ImageView {
                var view: c.VkImageView = undefined;
                try check(device.dispatch.create_image_view(device.handler, &.{
                    .image = config.image,
                    .viewType = config.view_type,
                    .subresourceRange = config.subresource_range,
                    }, config.allocation_callbacks, &view));

                return .{
                    .handler = view,
                };
            }
        };

        pub const Config = struct {
            image_count: u32,
            image_format: Format,
            surface: Surface,
            image_color_space: ColorSpace,
            extent: Extent,
            queue_families: []u32,
            sharing_mode: SharingMode,
            present_mode: PresentMode,
            pre_transform: SurfaceTransformFlagBits,

            old_swapchain: c.VkSwapchainKHR = null,
            allocation_callbacks: ?*AllocationCallbacks = null,
            composite_alpha: CompositeAlphaFlagBits = COMPOSITE_ALPHA_OPAQUE_BIT,
            clipped: u32 = TRUE,
            array_layers: u32 = 1,
            image_usage: ImageUsageFlags = IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        };

        pub fn new(device: *Device, config: Swapchain.Config) !Swapchain {
            var swapchain: c.VkSwapchainKHR = undefined;
            try check(device.dispatch.create_swapchain(device.handler, &.{
                .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                .surface = config.surface,
                .minImageCount = config.image_count,
                .imageFormat = config.image_format,
                .imageColorSpace = config.image_color_space,
                .imageExtent = config.extent,
                .imageSharingMode = config.sharing_mode,
                .presentMode = config.present_mode,
                .preTransform = config.pre_transform,
                .clipped = config.clipped,
                .imageArrayLayers = config.array_layers,
                .compositeAlpha = config.composite_alpha,
                .imageUsage = config.image_usage,
                .queueFamilyIndexCount = @as(u32 , @intCast(config.queue_families.len)),
                .pQueueFamilyIndices = config.queue_families.ptr,
                .oldSwapchain = config.old_swapchain,
                }, config.allocation_callbacks, &swapchain));

            return .{
                .handler = swapchain,
            };
        }
    };


    fn check(result: i32) !void {
        switch (result) {
            SUCCESS => return,
            c.VK_NOT_READY => configuration.logger.log(.Warn, "Result failed with error: 'NotReady", .{}),
            c.VK_TIMEOUT => configuration.logger.log(.Warn, "Result failed with error: 'Timeout", .{}),
            c.VK_EVENT_SET => configuration.logger.log(.Warn, "Result failed with error: 'EventSet", .{}),
            c.VK_EVENT_RESET => configuration.logger.log(.Warn, "Result failed with error: 'EventReset", .{}),
            c.VK_INCOMPLETE => configuration.logger.log(.Warn, "Result failed with error: Incomplete", .{}),
            c.VK_ERROR_OUT_OF_HOST_MEMORY => configuration.logger.log(.Warn, "Result failed with 'OutOfHostMemory", .{}),
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY => configuration.logger.log(.Warn, "Result failed with error: 'OutOfDeviceMemory'", .{}),
            c.VK_ERROR_INITIALIZATION_FAILED => configuration.logger.log(.Warn, "Result failed with error: 'InitializationFailed'", .{}),
            c.VK_ERROR_DEVICE_LOST => configuration.logger.log(.Warn, "Result failed with error: 'DeviceLost'", .{}),
            c.VK_ERROR_MEMORY_MAP_FAILED => configuration.logger.log(.Warn, "Result Failed with error: 'MemoryMapFailed'", .{}),
            c.VK_ERROR_LAYER_NOT_PRESENT => configuration.logger.log(.Warn, "Result Failed with error: 'LayerNotPresent'", .{}),
            c.VK_ERROR_EXTENSION_NOT_PRESENT => configuration.logger.log(.Warn, "Result Failed with error: 'ExtensionNotPresent'", .{}),
            c.VK_ERROR_FEATURE_NOT_PRESENT => configuration.logger.log(.Warn, "Result Failed with error: 'FeatureNotPresent'", .{}),
            c.VK_ERROR_INCOMPATIBLE_DRIVER => configuration.logger.log(.Warn, "Result Failed with error: 'IncompatibleDriver'", .{}),
            c.VK_ERROR_TOO_MANY_OBJECTS => configuration.logger.log(.Warn, "Result Failed with error: 'TooManyObjects'", .{}),
            c.VK_ERROR_FORMAT_NOT_SUPPORTED => configuration.logger.log(.Warn, "Result Failed with error: 'FormatNotSupported'", .{}),
            c.VK_ERROR_FRAGMENTED_POOL => configuration.logger.log(.Warn, "Result Failed with error: 'FragmentedPool'", .{}),
            c.VK_ERROR_UNKNOWN => configuration.logger.log(.Warn, "Result Failed with error: 'Unknown'", .{}),
            c.VK_ERROR_INVALID_EXTERNAL_HANDLE => configuration.logger.log(.Warn, "Result Failed with error: 'InvalidExternalHandle'", .{}),
            c.VK_ERROR_FRAGMENTATION => configuration.logger.log(.Warn, "Result Failed with error: 'Fragmentation'", .{}),
            c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => configuration.logger.log(.Warn, "Result Failed with error: 'InvalidOpaqueCaptureAddress'", .{}),
            c.VK_PIPELINE_COMPILE_REQUIRED => configuration.logger.log(.Warn, "Result Failed with error: 'PipelineCompileRequired'", .{}),
            c.VK_ERROR_SURFACE_LOST_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'SurfaceLostKhr'", .{}),
            c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'NativeWindowInUseKhr'", .{}),
            c.VK_SUBOPTIMAL_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'SuboptimalKhr'", .{}),
            c.VK_ERROR_OUT_OF_DATE_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'OutOfDateKhr'", .{}),
            c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'IncompatibleDisplayKhr'", .{}),
            c.VK_ERROR_VALIDATION_FAILED_EXT => configuration.logger.log(.Warn, "Result Failed with error: 'ValidationFailedExt'", .{}),
            c.VK_ERROR_INVALID_SHADER_NV => configuration.logger.log(.Warn, "Result Failed with error: 'InvalidShaderNv'", .{}),
            c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'ImageUsageNotSupportedKhr'", .{}),
            c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'VideoPictureLayoutNotSupportedKhr'", .{}),
            c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'VideoProfileOperationNotSupportedKhr'", .{}),
            c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'VideoProfileFormatNotSupportedKhr'", .{}),
            c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'VideoProfileCodecNotSupportedKhr'", .{}),
            c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'VideoStdVersionNotSupportedKhr'", .{}),
            c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => configuration.logger.log(.Warn, "Result Failed with error: 'InvalidDrmFormatModifierPlaneLayoutExt'", .{}),
            c.VK_ERROR_NOT_PERMITTED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'NotPermittedKhr'", .{}),
            c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => configuration.logger.log(.Warn, "Result Failed with error: 'FullScreenExclusiveModeLostExt'", .{}),
            c.VK_THREAD_IDLE_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'ThreadIdleKhr'", .{}),
            c.VK_THREAD_DONE_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'ThreadDoneKhr'", .{}),
            c.VK_OPERATION_DEFERRED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'OperationDeferredKhr'", .{}),
            c.VK_OPERATION_NOT_DEFERRED_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'OperationNotDeferredKhr'", .{}),
            c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'InvalidVideoStdParametersKhr'", .{}),
            c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => configuration.logger.log(.Warn, "Result Failed with error: 'CompressionExhaustedExt'", .{}),
            c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => configuration.logger.log(.Warn, "Result Failed with error: 'IncompatibleShaderBinaryExt'", .{}),
            c.VK_ERROR_OUT_OF_POOL_MEMORY_KHR => configuration.logger.log(.Warn, "Result Failed with error: 'OutOfPoolMemoryKhr'", .{}),

            else => configuration.logger.log(.Warn, "Result was not a success, ({})", .{result}),
        }

        return error.Failed;
    }

    pub fn bit(one: u32, other: u32) bool {
        return (one & other) != 0;
    }

    pub fn boolean(flag: u32) bool {
        return flag == TRUE;
    }

    pub const ApiVersion = c.VK_MAKE_API_VERSION(0, 1, 3, 0);
    pub const ApplicationInfo = c.VkApplicationInfo;
    pub const InstanceCreateInfo = c.VkInstanceCreateInfo;
    pub const ExtensionProperties = c.VkExtensionProperties;
    pub const AllocationCallbacks = c.VkAllocationCallbacks;
    pub const Extent = c.VkExtent2D;
    pub const Format = c.VkFormat;
    pub const FormatProperties = c.VkFormatProperties;

    pub const Surface = c.VkSurfaceKHR;
    pub const SurfaceFormat = c.VkSurfaceFormatKHR;
    pub const SurfaceCapabilities = c.VkSurfaceCapabilitiesKHR;

    pub const PresentMode = c.VkPresentModeKHR;
    pub const SharingMode = c.VkSharingMode;
    pub const ColorSpace = c.VkColorSpaceKHR;
    pub const CompositeAlphaFlagBits = c.VkCompositeAlphaFlagBitsKHR;
    pub const SurfaceTransformFlagBits = c.VkSurfaceTransformFlagBitsKHR;

    pub const Image = c.VkImage;
    pub const ImageUsageFlags = c.VkImageUsageFlags;

    pub const PhysicalDevice = c.VkPhysicalDevice;
    pub const PhysicalDeviceFeatures = c.VkPhysicalDeviceFeatures;
    pub const PhysicalDeviceProperties = c.VkPhysicalDeviceProperties;
    pub const PhysicalDeviceMemoryProperties = c.VkPhysicalDeviceMemoryProperties;

    pub const Queue = c.VkQueue;
    pub const QueueFamilyProperties = c.VkQueueFamilyProperties;
    pub const QueueComputeBit = c.VK_QUEUE_COMPUTE_BIT;
    pub const QueueGraphicsBit = c.VK_QUEUE_GRAPHICS_BIT;
    pub const QueueTransferBit = c.VK_QUEUE_TRANSFER_BIT;
    pub const DeviceQueueCreateInfo = c.VkDeviceQueueCreateInfo;

    pub const FORMAT_B8G8R8A8_SRGB = c.VK_FORMAT_B8G8R8A8_SRGB;
    pub const COLOR_SPACE_SRGB_NONLINEAR = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    pub const IMAGE_USAGE_COLOR_ATTACHMENT_BIT = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    pub const SWAPCHAIN_EXTENSION_NAME = c.VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    pub const SHARING_MODE_CONCURRENT = c.VK_SHARING_MODE_CONCURRENT;
    pub const SHARING_MODE_EXCLUSIVE = c.VK_SHARING_MODE_EXCLUSIVE;
    pub const COMPOSITE_ALPHA_OPAQUE_BIT = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    pub const FORMAT_D32_SFLOAT = c.VK_FORMAT_D32_SFLOAT;
    pub const FORMAT_D32_SFLOAT_S8_UINT = c.VK_FORMAT_D32_SFLOAT_S8_UINT;
    pub const FORMAT_D24_UNORM_S8_UINT= c.VK_FORMAT_D24_UNORM_S8_UINT;
    pub const FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT = c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;

    pub const PRESENT_MODE_MAILBOX = c.VK_PRESENT_MODE_MAILBOX_KHR;
    pub const PRESENT_MODE_FIFO = c.VK_PRESENT_MODE_FIFO_KHR;
    pub const TRUE = c.VK_TRUE;
    pub const SUCCESS = c.VK_SUCCESS;
};
