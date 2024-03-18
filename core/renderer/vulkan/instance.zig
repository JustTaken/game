const std = @import("std");

const _config = @import("../../util/configuration.zig");
const _platform = @import("../../platform/platform.zig");
const _error = @import("error.zig");

const Platform = _platform.Platform;
const check = _error.check;

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Instance = struct {
    handle: c.VkInstance,

    pub fn new(comptime platform: type) !Instance {
        var instance: c.VkInstance = undefined;
        const vkCreateInstance = _platform.get_instance_function() catch |e| {
            logger.log(.Error, "Lib vulkan not found", .{});

            return e;
        };

        try check(vkCreateInstance(&.{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .enabledExtensionCount = @as(u32, @intCast(platform.Extensions.len)),
            .ppEnabledExtensionNames = platform.Extensions.ptr,
            .pApplicationInfo = &.{
                .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pApplicationName = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                .applicationVersion = configuration.version,
                .pEngineName = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                .engineVersion = configuration.version,
                .apiVersion = c.VK_MAKE_API_VERSION(0, 1, 3, 0),
            },
        }, null, &instance));

        try populate_instance_functions(instance);

        return .{
            .handle = instance,
        };
    }

    pub fn create_device(_: Instance, physical_device: c.VkPhysicalDevice, info: c.VkDeviceCreateInfo) !c.VkDevice {
        var device: c.VkDevice = undefined;
        try check(vkCreateDevice(physical_device, &info, null, &device));

        return device;
    }

    pub fn destroy_surface(self: Instance, surface: c.VkSurfaceKHR) void {
        vkDestroySurfaceKHR(self.handle, surface, null);
    }

    pub fn enumerate_physical_devices(self: Instance, allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
        var count: u32 = undefined;

        try check(vkEnumeratePhysicalDevices(self.handle, &count, null));
        const physical_devices = try allocator.alloc(c.VkPhysicalDevice, count);

        try check(vkEnumeratePhysicalDevices(self.handle, &count, physical_devices.ptr));

        return physical_devices;
    }

    pub fn enumerate_device_extension_properties(_: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkExtensionProperties {
        var count: u32 = undefined;

        try check(vkEnumerateDeviceExtensionProperties(physical_device, null, &count, null));
        const extension_properties = try allocator.alloc(c.VkExtensionProperties, count);

        try check(vkEnumerateDeviceExtensionProperties(physical_device, null, &count, extension_properties.ptr));

        return extension_properties;
    }

    pub fn get_physical_device_properties(_: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceProperties {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        vkGetPhysicalDeviceProperties(physical_device, &properties);

        return properties;
    }

    pub fn get_physical_device_features(_: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceFeatures {
        var features: c.VkPhysicalDeviceFeatures = undefined;
        vkGetPhysicalDeviceFeatures(physical_device, &features);

        return features;
    }

    pub fn get_physical_device_format_properties(_: Instance, physical_device: c.VkPhysicalDevice, format: c.VkFormat) c.VkFormatProperties {
        var properties: c.VkFormatProperties = undefined;
        vkGetPhysicalDeviceFormatProperties(physical_device, format, &properties);

        return properties;
    }

    pub fn get_physical_device_surface_formats(_: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkSurfaceFormatKHR {
        var count: u32 = undefined;
        try check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null));
        const formats = try allocator.alloc(c.VkSurfaceFormatKHR, count);

        try check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, formats.ptr));

        return formats;
    }

    pub fn get_physical_device_surface_present_modes(_: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: std.mem.Allocator) ![]c.VkPresentModeKHR {
        var count: u32 = undefined;
        try check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null));
        const present_modes = try allocator.alloc(c.VkPresentModeKHR, count);
        try check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, present_modes.ptr));

        return present_modes;
    }

    pub fn get_physical_device_queue_family_properties(_: Instance, physical_device: c.VkPhysicalDevice, allocator: std.mem.Allocator) ![]c.VkQueueFamilyProperties {
        var count: u32 = undefined;
        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
        const properties = try allocator.alloc(c.VkQueueFamilyProperties, count);

        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, properties.ptr);

        return properties;
    }

    pub fn get_physical_device_surface_capabilities(_: Instance, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !c.VkSurfaceCapabilitiesKHR {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities));

        return capabilities;
    }

    pub fn get_physical_device_surface_support(_: Instance, physical_device: c.VkPhysicalDevice, family: u32, surface: c.VkSurfaceKHR) !bool {
        var flag: u32 = undefined;
        try check(vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, family, surface, &flag));

        return flag == c.VK_TRUE;
    }

    pub fn get_physical_device_memory_properties(_: Instance, physical_device: c.VkPhysicalDevice) c.VkPhysicalDeviceMemoryProperties {
        var properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        vkGetPhysicalDeviceMemoryProperties(physical_device, &properties);

        return properties;
    }

    pub fn destroy(self: Instance) void {
        vkDestroyInstance(self.handle, null);
    }
};

fn populate_instance_functions(instance: c.VkInstance) !void {
    const vkGetInstanceProcAddr = try _platform.get_instance_procaddr(instance);

    vkDestroySurfaceKHR = @as(c.PFN_vkDestroySurfaceKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkDestroySurfaceKHR"))) orelse return error.FunctionNotFound;
    vkEnumeratePhysicalDevices = @as(c.PFN_vkEnumeratePhysicalDevices, @ptrCast(vkGetInstanceProcAddr(instance, "vkEnumeratePhysicalDevices"))) orelse return error.FunctionNotFound;
    vkEnumerateDeviceExtensionProperties = @as(c.PFN_vkEnumerateDeviceExtensionProperties, @ptrCast(vkGetInstanceProcAddr(instance, "vkEnumerateDeviceExtensionProperties"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceProperties = @as(c.PFN_vkGetPhysicalDeviceProperties, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceFeatures = @as(c.PFN_vkGetPhysicalDeviceFeatures, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFeatures"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceSurfaceFormatsKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceSurfacePresentModesKHR = @as(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceQueueFamilyProperties = @as(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceQueueFamilyProperties"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceSurfaceSupportKHR = @as(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceSurfaceSupportKHR"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceMemoryProperties = @as(c.PFN_vkGetPhysicalDeviceMemoryProperties, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceMemoryProperties"))) orelse return error.FunctionNotFound;
    vkGetPhysicalDeviceFormatProperties = @as(c.PFN_vkGetPhysicalDeviceFormatProperties, @ptrCast(vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceFormatProperties"))) orelse return error.FunctionNotFound;
    vkCreateDevice = @as(c.PFN_vkCreateDevice, @ptrCast(vkGetInstanceProcAddr(instance, "vkCreateDevice"))) orelse return error.FunctionNotFound;
    vkDestroyInstance = @as(c.PFN_vkDestroyInstance, @ptrCast(vkGetInstanceProcAddr(instance, "vkDestroyInstance"))) orelse return error.FunctionNotFound;
}

var vkCreateDevice: *const fn (c.VkPhysicalDevice, *const c.VkDeviceCreateInfo, ?*const c.VkAllocationCallbacks, ?*c.VkDevice) callconv(.C) i32 = undefined;
var vkEnumeratePhysicalDevices: *const fn (c.VkInstance, *u32, ?[*]c.VkPhysicalDevice) callconv(.C) i32 = undefined;
var vkEnumerateDeviceExtensionProperties: *const fn (c.VkPhysicalDevice, ?[*]const u8, *u32, ?[*]c.VkExtensionProperties) callconv(.C) i32 = undefined;
var vkGetPhysicalDeviceProperties: *const fn (c.VkPhysicalDevice, ?*c.VkPhysicalDeviceProperties) callconv(.C) void = undefined;
var vkGetPhysicalDeviceFeatures: *const fn (c.VkPhysicalDevice, ?*c.VkPhysicalDeviceFeatures) callconv(.C) void = undefined;
var vkGetPhysicalDeviceSurfaceFormatsKHR: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *u32, ?[*]c.VkSurfaceFormatKHR) callconv(.C) i32 = undefined;
var vkGetPhysicalDeviceSurfacePresentModesKHR: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *u32, ?[*]c.VkPresentModeKHR) callconv(.C) i32 = undefined;
var vkGetPhysicalDeviceQueueFamilyProperties: *const fn (c.VkPhysicalDevice, *u32, ?[*]c.VkQueueFamilyProperties) callconv(.C) void = undefined;
var vkGetPhysicalDeviceSurfaceCapabilitiesKHR: *const fn (c.VkPhysicalDevice, c.VkSurfaceKHR, *c.VkSurfaceCapabilitiesKHR) callconv(.C) i32 = undefined;
var vkGetPhysicalDeviceSurfaceSupportKHR: *const fn (c.VkPhysicalDevice, u32, c.VkSurfaceKHR, *u32) callconv(.C) i32 = undefined;
var vkGetPhysicalDeviceMemoryProperties: *const fn (c.VkPhysicalDevice, *c.VkPhysicalDeviceMemoryProperties) callconv(.C) void = undefined;
var vkGetPhysicalDeviceFormatProperties: *const fn (c.VkPhysicalDevice, c.VkFormat, *c.VkFormatProperties) callconv(.C) void = undefined;
var vkDestroySurfaceKHR: *const fn (c.VkInstance, c.VkSurfaceKHR, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
var vkDestroyInstance: *const fn (c.VkInstance, ?*const c.VkAllocationCallbacks) callconv(.C) void = undefined;
