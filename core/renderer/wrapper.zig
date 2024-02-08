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

            return .{
                .handler = instance,
                .allocator = allocator,
            };
        }

        pub fn destroy_surface(self: *Instance, surface: Surface) void {
            const PFN_vkDestroySurfaceKHR = @as(c.PFN_vkDestroySurfaceKHR, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkDestroySurfaceKHR"))) orelse return;
            PFN_vkDestroySurfaceKHR(self.handler, surface, null);
        }

        pub fn enumerate_physical_devices(self: *Instance) ![]PhysicalDevice {
            var count: u32 = undefined;
            const PFN_vkEnumeratePhysicalDevices = @as(c.PFN_vkEnumeratePhysicalDevices, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkEnumeratePhysicalDevices"))) orelse return error.FunctionNotFound;
            try check(PFN_vkEnumeratePhysicalDevices(self.handler, &count, null));
            const physical_devices = self.allocator.alloc(PhysicalDevice, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(PFN_vkEnumeratePhysicalDevices(self.handler, &count, physical_devices.ptr));

            return physical_devices;
        }

        pub fn enumerate_device_extension_properties(self: *Instance, physical_device: PhysicalDevice) ![]ExtensionProperties {
            var count: u32 = undefined;
            const PFN_vkEnumerateDeviceExtensionProperties = @as(c.PFN_vkEnumerateDeviceExtensionProperties, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkEnumerateDeviceExtensionProperties"))) orelse return error.FunctionNotFound;

            try check(PFN_vkEnumerateDeviceExtensionProperties(physical_device, null, &count, null));
            const extension_properties = self.allocator.alloc(ExtensionProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(PFN_vkEnumerateDeviceExtensionProperties(physical_device, null, &count, extension_properties.ptr));

            return extension_properties;
        }

        pub fn get_physical_device_properties(self: *Instance, physical_device: PhysicalDevice) !PhysicalDeviceProperties {
            const PFN_vkGetPhysicalDeviceProperties = @as(c.PFN_vkGetPhysicalDeviceProperties, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceProperties"))) orelse return error.FunctionNotFound;
            var properties: PhysicalDeviceProperties = undefined;
            PFN_vkGetPhysicalDeviceProperties(physical_device, &properties);

            return properties;
        }

        pub fn get_physical_device_features(self: *Instance, physical_device: PhysicalDevice) !PhysicalDeviceFeatures {
            const PFN_vkGetPhysicalDeviceFeatures = @as(c.PFN_vkGetPhysicalDeviceFeatures, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceFeatures"))) orelse return error.FunctionNotFound;
            var features: PhysicalDeviceFeatures = undefined;
            PFN_vkGetPhysicalDeviceFeatures(physical_device, &features);

            return features;
        }

        pub fn get_physical_device_surface_formats(self: *Instance, physical_device: PhysicalDevice, surface: Surface) ![]SurfaceFormat {
            var count: u32 = undefined;
            const PFN_vkGetPhysicalDeviceSurfaceFormatsKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceSurfaceFormatsKHR"))) orelse return error.FunctionNotFound;
            try check(PFN_vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null));
            const formats = self.allocator.alloc(SurfaceFormat, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(PFN_vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, formats.ptr));

            return formats;
        }

        pub fn get_physical_device_surface_present_modes(self: *Instance, physical_device: PhysicalDevice, surface: Surface) ![]PresentMode {
            var count: u32 = undefined;
            const PFN_vkGetPhysicalDeviceSurfacePresentModesKHR = @as(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceSurfacePresentModesKHR"))) orelse return error.FunctionNotFound;
            try check(PFN_vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null));
            const present_modes = self.allocator.alloc(PresentMode, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            try check(PFN_vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, present_modes.ptr));

            return present_modes;
        }

        pub fn get_physical_device_queue_family_properties(self: *Instance, physical_device: PhysicalDevice) ![]QueueFamilyProperties {
            var count: u32 = undefined;
            const PFN_vkGetPhysicalDeviceQueueFamilyProperties = @as(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceQueueFamilyProperties"))) orelse return error.FunctionNotFound;
            PFN_vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
            const properties = self.allocator.alloc(QueueFamilyProperties, count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };
            PFN_vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, properties.ptr);

            return properties;
        }

        pub fn get_physical_device_surface_capabilities(self: *Instance, physical_device: PhysicalDevice, surface: Surface) !SurfaceCapabilities {
            var capabilities: SurfaceCapabilities = undefined;
            const PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))) orelse return error.FunctionNotFound;
            try check(PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities));

            return capabilities;
        }

        pub fn get_physical_device_surface_support(self: *Instance, physical_device: PhysicalDevice, family: u32, surface: Surface) !bool {
            const PFN_vkGetPhysicalDeviceSurfaceSupportKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceSurfaceSupportKHR"))) orelse return error.FunctionNotFound;
            var flag: u32 = undefined;
            try check(PFN_vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, family, surface, &flag));

            return flag == c.VK_TRUE;
        }

        pub fn get_physical_device_memory_properties(self: *Instance, physical_device: PhysicalDevice) !PhysicalDeviceMemoryProperties {
            var properties: PhysicalDeviceMemoryProperties = undefined;
            const PFN_vkGetPhysicalDeviceMemoryProperties = @as(c.PFN_vkGetPhysicalDeviceMemoryProperties, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkGetPhysicalDeviceMemoryProperties"))) orelse return error.FunctionNotFound;
            PFN_vkGetPhysicalDeviceMemoryProperties(physical_device, &properties);

            return properties;
        }

        pub fn destroy(self: *Instance) void {
            const PFN_vkDestroyInstance = @as(c.PFN_vkDestroyInstance, @ptrCast(c.glfwGetInstanceProcAddress(self.handler, "vkDestroyInstance"))) orelse return;
            PFN_vkDestroyInstance(self.handler, null);
        }
    };

    pub const Device = struct {
        handler: c.VkDevice,
        get_proc_addr: c.PFN_vkGetDeviceProcAddr,
        allocator: std.mem.Allocator,

        pub const Config = struct {
            queue_count: u32 = 0,
            queues: [*c]const DeviceQueueCreateInfo,
            allocation_callbacks: ?*AllocationCallbacks = null,
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
            const PFN_vkCreateDevice = @as(c.PFN_vkCreateDevice, @ptrCast(c.glfwGetInstanceProcAddress(instance.handler, "vkCreateDevice"))) orelse return error.FunctionNotFound;
            try check(PFN_vkCreateDevice(
                physical_device,
                &.{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                    .queueCreateInfoCount = config.queue_count,
                    .pQueueCreateInfos = config.queues,
                },
                config.allocation_callbacks,
                &device
            ));

            const PFN_vkGetDeviceProcAddr = @as(c.PFN_vkGetDeviceProcAddr, @ptrCast(c.glfwGetInstanceProcAddress(instance.handler, "vkGetDeviceProcAddr"))) orelse return error.FunctionNotFound;

            return .{
                .handler = device,
                .get_proc_addr = PFN_vkGetDeviceProcAddr,
                .allocator = allocator,
            };
        }

        pub fn get_device_queue(self: *Device, family_index: u32) !Queue {
            var queue: Queue = undefined;
            const PFN_vkGetDeviceQueue = @as(c.PFN_vkGetDeviceQueue, @ptrCast(self.get_proc_addr.?(self.handler, "vkGetDeviceQueue"))) orelse return error.FunctionNotFound;
            PFN_vkGetDeviceQueue(self.handler, family_index, 0, &queue);

            return queue;
        }

        pub fn destroy(self: *Device) void {
            const PFN_vkDestroyDevice = @as(c.PFN_vkDestroyDevice, @ptrCast(self.get_proc_addr.?(self.handler, "vkDestroyDevice"))) orelse return;
            PFN_vkDestroyDevice(self.handler, null);
        }
    };

    pub const Extent = struct {
        width: u32,
        height: u32,
    };

    fn check(result: c.VkResult) !void {
        return switch (result) {
            c.VK_SUCCESS => {},
            else => {
                configuration.logger.log(.Warn, "Result was not a success, ({})", .{result});
                return error.VkFailed;
            },
        };
    }

    pub fn bit(one: u32, other: u32) bool {
        return (one & other) != 0;
    }

    pub fn boolean(flag: u32) bool {
        return flag == c.VK_TRUE;
    }

    pub const ApiVersion = c.VK_MAKE_API_VERSION(0, 1, 3, 0);
    pub const ApplicationInfo = c.VkApplicationInfo;
    pub const InstanceCreateInfo = c.VkInstanceCreateInfo;
    pub const ExtensionProperties = c.VkExtensionProperties;
    pub const AllocationCallbacks = c.VkAllocationCallbacks;

    pub const Surface = c.VkSurfaceKHR;
    pub const SurfaceFormat = c.VkSurfaceFormatKHR;
    pub const SurfaceCapabilities = c.VkSurfaceCapabilitiesKHR;

    pub const PresentMode = c.VkPresentModeKHR;
    pub const Swapchain = c.VkSwaphChainKHR;

    pub const Image = c.VkImage;
    pub const ImageView = c.VkImageView;

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
    pub const SWAPCHAIN_EXTENSION_NAME = c.VK_KHR_SWAPCHAIN_EXTENSION_NAME;

    pub const PRESENT_MODE_MAILBOX = c.VK_PRESENT_MODE_MAILBOX_KHR;
    pub const PRESENT_MODE_FIFO = c.VK_PRESENT_MODE_FIFO_KHR;
};
