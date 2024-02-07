const std = @import("std");
const _vulkan = @import("vulkan.zig");
const _utility = @import("../utility.zig");
const _wrapper = @import("wrapper.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

const vk = _vulkan;
const Glfw = _wrapper.Glfw;
const configuration = _utility.Configuration;

extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

const REQUIRED_DEVICE_EXTENSIONS = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};

var SNAP_ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const SNAP_ALLOCATOR = SNAP_ARENA.allocator();

pub const Backend = struct {
    instance: Instance,
    window: Window,
    device: Device,
    // swapchain: Swapchain,

    const Instance = struct {
        handler: vk.Instance,
        dispatch: Dispatch,

        const Dispatch = vk.InstanceWrapper(.{
            .destroyInstance = true,
            .createDevice = true,
            .destroySurfaceKHR = true,
            .enumeratePhysicalDevices = true,
            .getPhysicalDeviceProperties = true,
            .getPhysicalDeviceFeatures = true,
            .enumerateDeviceExtensionProperties = true,
            .getPhysicalDeviceSurfaceFormatsKHR = true,
            .getPhysicalDeviceSurfacePresentModesKHR = true,
            .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .getPhysicalDeviceSurfaceSupportKHR = true,
            .getPhysicalDeviceMemoryProperties = true,
            .getDeviceProcAddr = true,
        });

        fn new() !Instance {
            const base_dispatch = vk.BaseWrapper(.{
                .createInstance = true,
                .getInstanceProcAddr = true,
            }).load(glfwGetInstanceProcAddress) catch {
                configuration.logger.log(.Error, "Failed to get base dispatch function pointers", .{});
                return error.BaseDispatch;
            };

            var glfw_extension_count: u32 = undefined;
            const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_extension_count);

            const app_info = vk.ApplicationInfo{
                .p_application_name = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                .application_version = configuration.version,
                .p_engine_name = @as([*:0]const u8, @ptrCast(configuration.application_name)),
                .engine_version = configuration.version,
                .api_version = vk.API_VERSION_1_3,
            };

            const handler = base_dispatch.createInstance(&.{
                .p_application_info = &app_info,
                .enabled_extension_count = glfw_extension_count,
                .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(glfw_extensions)),
                }, null) catch {
                configuration.logger.log(.Error, "Failed to get instance dispatch function pointers", .{});
                return error.InstanceCreateFailed;
            };

            return .{
                .handler = handler,
                .dispatch = Instance.Dispatch.load(handler, base_dispatch.dispatch.vkGetInstanceProcAddr) catch {
                    configuration.logger.log(.Error, "Failed to create intance dispatch", .{});
                    return error.InstanceDispatchLoadFailed;
                },
            };
        }

        fn destroy(self: Instance) void {
            self.dispatch.destroyInstance(self.handler, null);
        }
    };

    const Window = struct {
        handler: *c.GLFWwindow,
        surface: vk.SurfaceKHR,
        width: u32,
        height: u32,

        fn new(instance_handler: vk.Instance, width: u32, height: u32) !Window {

            const handler = Glfw.create_window(width, height, &configuration.application_name[0]) catch {
                configuration.logger.log(.Error, "Glfw failed to create window", .{});
                return error.WindowCreate;
            }

            var surface: vk.SurfaceKHR = undefined;
            if (glfwCreateWindowSurface(instance_handler, handler, null, &surface) != .success) {
                configuration.logger.log(.Error, "Failed to create window surface", .{});
                return error.SurfaceInit;
            }

            return .{
                .handler = handler,
                .surface = surface,
                .width = width,
                .height = height,
            };
        }

        fn destroy(self: Window, instance: Instance) void {
            instance.dispatch.destroySurfaceKHR(instance.handler, self.surface, null);
            c.glfwDestroyWindow(self.handler);
        }
    };

    const Swapchain = struct {
        handler: vk.SwapchainKHR,
        image_format: vk.SurfaceFormatKHR,
        image_views: []vk.ImageView,
        images: []vk.Image,

        frames_in_flight: u8,
        image_count: u8,

        fn new() void {
        }
    };

    const Device = struct {
        logical_device: vk.Device,
        queue_allocator: QueueAllocator,

        physical_device: vk.PhysicalDevice,
        physical_device_properties: vk.PhysicalDeviceProperties,
        physical_device_properties_memory: vk.PhysicalDeviceMemoryProperties,
        physical_device_features: vk.PhysicalDeviceFeatures,

        dispatch: Dispatch,

        const Dispatch = vk.DeviceWrapper(.{
            .destroyDevice = true,
            .getDeviceQueue = true,
            .createSemaphore = true,
            .createFence = true,
            .createImageView = true,
            .destroyImageView = true,
            .destroySemaphore = true,
            .destroyFence = true,
            .getSwapchainImagesKHR = true,
            .createSwapchainKHR = true,
            .destroySwapchainKHR = true,
            .acquireNextImageKHR = true,
            .deviceWaitIdle = true,
            .waitForFences = true,
            .resetFences = true,
            .queueSubmit = true,
            .queuePresentKHR = true,
            .createCommandPool = true,
            .destroyCommandPool = true,
            .allocateCommandBuffers = true,
            .freeCommandBuffers = true,
            .queueWaitIdle = true,
            .createShaderModule = true,
            .destroyShaderModule = true,
            .createPipelineLayout = true,
            .destroyPipelineLayout = true,
            .createRenderPass = true,
            .destroyRenderPass = true,
            .createGraphicsPipelines = true,
            .destroyPipeline = true,
            .createFramebuffer = true,
            .destroyFramebuffer = true,
            .beginCommandBuffer = true,
            .endCommandBuffer = true,
            .allocateMemory = true,
            .freeMemory = true,
            .createBuffer = true,
            .destroyBuffer = true,
            .getBufferMemoryRequirements = true,
            .mapMemory = true,
            .unmapMemory = true,
            .bindBufferMemory = true,
            .cmdBeginRenderPass = true,
            .cmdEndRenderPass = true,
            .cmdBindPipeline = true,
            .cmdDraw = true,
            .cmdSetViewport = true,
            .cmdSetScissor = true,
            .cmdBindVertexBuffers = true,
            .cmdCopyBuffer = true,
        });


        const QueueAllocator = struct {
            graphics: Queue,
            present: Queue,
            transfer: Queue,
            compute: Queue,

            fn new(
                instance_dispatch: Instance.Dispatch,
                physical_device: vk.PhysicalDevice,
                surface: vk.SurfaceKHR
            ) !QueueAllocator {
                var family_count: u32 = undefined;
                var graphics: ?u32 = null;
                var present: ?u32 = null;
                var transfer: ?u32 = null;
                var compute: ?u32 = null;

                instance_dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, null);
                const families = SNAP_ALLOCATOR.alloc(vk.QueueFamilyProperties, family_count) catch {
                    configuration.logger.log(.Error, "Out of memory", .{});
                    return error.OutOfMemory;
                };
                instance_dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, families.ptr);

                var min_transfer_score: u8 = 0xFF;
                for (families, 0..) |properties, i| {
                    var current_transfer_score: u8 = 0;
                    const family: u32 = @intCast(i);

                    if (present == null and ((instance_dispatch.getPhysicalDeviceSurfaceSupportKHR(physical_device, family, surface) catch return error.NoSupport) == vk.TRUE)) present = family;
                    if (graphics == null and properties.queue_flags.graphics_bit) {
                        graphics = family;
                        current_transfer_score += 1;
                    }

                    if (compute == null and properties.queue_flags.compute_bit) {
                        compute = family;
                        current_transfer_score += 1;
                    }

                    if (transfer == null and properties.queue_flags.transfer_bit and current_transfer_score <= min_transfer_score) {
                        transfer = family;
                        min_transfer_score = current_transfer_score;
                    }
                }

                const graphics_family = graphics orelse return error.NoGraphics;
                const present_family = present orelse return error.NoPresent;
                const transfer_family = transfer orelse return error.NoTransfer;
                const compute_family = compute orelse return error.NoCompute;

                return .{
                    .graphics = .{
                        .handler = null,
                        .family = graphics_family
                    },
                    .present = .{
                        .handler = null,
                        .family = present_family
                    },
                    .transfer = .{
                        .handler = null,
                        .family = transfer_family
                    },
                    .compute = .{
                        .handler = null,
                        .family = compute_family
                    }
                };
            }

            fn fill(self: *QueueAllocator, device_dispatch: Device.Dispatch, logical_device: vk.Device) void {
                self.graphics.handler = device_dispatch.getDeviceQueue(logical_device, self.graphics.family, 0);
                self.present.handler = device_dispatch.getDeviceQueue(logical_device, self.present.family, 0);
                self.transfer.handler = device_dispatch.getDeviceQueue(logical_device, self.transfer.family, 0);
                self.compute.handler = device_dispatch.getDeviceQueue(logical_device, self.compute.family, 0);
            }

            const Queue = struct {
                handler: ?vk.Queue,
                family: u32,
            };
        };

        fn new(
            instance: Instance,
            surface: vk.SurfaceKHR,
        ) !Device {

            const physical_device = blk: {
                var device_count: u32 = undefined;
                _ = try instance.dispatch.enumeratePhysicalDevices(instance.handler, &device_count, null);
                const physical_devices = try SNAP_ALLOCATOR.alloc(vk.PhysicalDevice, device_count);
                _ = try instance.dispatch.enumeratePhysicalDevices(instance.handler, &device_count, physical_devices.ptr);

                var points: u32 = 1;
                var p_device: ?vk.PhysicalDevice = null;

                for (physical_devices) |physical_device| {
                    const rate = rate: {
                        var extension_count: u32 = undefined;

                        _ = instance.dispatch.enumerateDeviceExtensionProperties(physical_device, null, &extension_count, null) catch break :rate 0;
                        const extensions_properties = SNAP_ALLOCATOR.alloc(vk.ExtensionProperties, extension_count) catch {
                            configuration.logger.log(.Error, "Out of memory", .{});
                            return error.OutOfMemory;
                        };
                        _ = instance.dispatch.enumerateDeviceExtensionProperties(physical_device, null, &extension_count, extensions_properties.ptr) catch break :rate 0;

                        const has_extension = ext: for (REQUIRED_DEVICE_EXTENSIONS) |extension| {
                            for (extensions_properties) |propertie| {
                                if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&propertie.extension_name, 0))) break :ext true;
                            }
                        } else {
                            break :ext false;
                        };

                        if (!has_extension) break :rate 0;

                        var format_count: u32 = undefined;
                        var present_mode_count: u32 = undefined;
                        _ = instance.dispatch.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null) catch break :rate 0;
                        _ = instance.dispatch.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null) catch break :rate 0;
                        if (!(format_count > 0 and present_mode_count > 0)) break :rate 0;

                        _ = QueueAllocator.new(instance.dispatch, physical_device, surface) catch break :rate 0;

                        var sum: u8 = 1;

                        const physical_device_props = instance.dispatch.getPhysicalDeviceProperties(physical_device);
                        const physical_device_feats = instance.dispatch.getPhysicalDeviceFeatures(physical_device);

                        if (physical_device_feats.geometry_shader == 0) break :rate 0;
                        if (physical_device_feats.sampler_anisotropy == 0) break :rate 0;
                        if (physical_device_props.device_type == .discrete_gpu) sum += 1;

                        sum += switch (physical_device_props.device_type) {
                            .discrete_gpu => 3,
                            .integrated_gpu => 2,
                            .virtual_gpu => 1,
                            .cpu => 1,
                            else => 0,
                        };

                        break :rate sum;
                    };

                    if (rate >= points) {
                        points = rate;
                        p_device = physical_device;
                    }
                }

                if (p_device) |physical_device| {
                    break :blk physical_device;
                } else {
                    configuration.logger.log(.Error, "Failed to find suitable GPU", .{});
                    return error.PhysicalDeviceNotFount;
                }
            };

            var queue_allocator = try QueueAllocator.new(instance.dispatch, physical_device, surface);

            const logical_device = blk: {
                const priority: [1]f32 = .{1};
                const families = [_]u32{
                    queue_allocator.graphics.family,
                    queue_allocator.present.family,
                    queue_allocator.transfer.family,
                    queue_allocator.compute.family
                };

                var uniques: [4]i32 = .{ -1, -1, -1, -1 };
                var queue_create_info: [4]vk.DeviceQueueCreateInfo = undefined;
                var size: u32 = 0;

                for (families) |family| {
                    for (0..size + 1) |i| {
                        if (family == uniques[i]) break;
                    } else {
                        uniques[size] = @as(i32, @intCast(family));
                        queue_create_info[size] = .{
                            .queue_family_index = family,
                            .queue_count = 1,
                            .p_queue_priorities = &priority,
                        };
                        size += 1;
                    }
                }

                break :blk instance.dispatch.createDevice(physical_device, &.{
                    .queue_create_info_count = size,
                    .p_queue_create_infos = &queue_create_info,
                    .enabled_extension_count = REQUIRED_DEVICE_EXTENSIONS.len,
                    .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(&REQUIRED_DEVICE_EXTENSIONS)),
                    }, null) catch {
                    configuration.logger.log(.Error, "Could not create device", .{});
                    return error.DeviceInint;
                };
            };

            const device_dispatch = Dispatch.load(logical_device, instance.dispatch.dispatch.vkGetDeviceProcAddr) catch {
                configuration.logger.log(.Error, "Failed to load device function pointers ", .{});
                return error.DeviceDispatchLoadFailed;
            };

            queue_allocator.fill(device_dispatch, logical_device);
            const physical_device_properties = instance.dispatch.getPhysicalDeviceProperties(physical_device);
            const physical_device_properties_memory = instance.dispatch.getPhysicalDeviceMemoryProperties(physical_device);
            const physical_device_features = instance.dispatch.getPhysicalDeviceFeatures(physical_device);

            configuration.logger.log(.Info, "Selecting GPU: {s}", .{std.mem.sliceTo(&physical_device_properties.device_name, 0)});

            return .{
                .queue_allocator = queue_allocator,
                .physical_device = physical_device,
                .physical_device_properties = physical_device_properties,
                .physical_device_properties_memory = physical_device_properties_memory,
                .physical_device_features = physical_device_features,
                .logical_device = logical_device,
                .dispatch = device_dispatch,
            };
        }

        fn destroy(self: Device) void {
            self.dispatch.destroyDevice(self.logical_device, null);
        }
    };

    pub fn new() !Backend {
        defer {
            _ = SNAP_ARENA.reset(.free_all);
            configuration.logger.log(.Debug, "Successfully initialized backend", .{});
        }

        try Glfw.init();

        const instance = Instance.new() catch {
            configuration.logger.log(.Error, "Failed to create instance", .{});
            return error.InstanceCreate;
        };

        const window = Window.new(instance.handler, configuration.default_width, configuration.default_height) catch {
            configuration.logger.log(.Error, "Failed to create window", .{});
            return error.WindowCreate;
        };

        const device = Device.new(instance, window.surface) catch {
            configuration.logger.log(.Error, "Failed to create device", .{});
            return error.DeviceCreate;
        };

        return .{
            .window = window,
            .device = device,
            .instance = instance,
        };
    }

    pub fn shutdown(self: Backend) void {
        self.device.destroy();
        self.window.destroy(self.instance);
        self.instance.destroy();

        c.glfwTerminate();
    }
};
