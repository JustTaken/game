const std = @import("std");
const _utility = @import("../utility.zig");
const _wrapper = @import("wrapper.zig");

const c = _wrapper.c;
const Glfw = _wrapper.Glfw;
const Vulkan = _wrapper.Vulkan;

const configuration = _utility.Configuration;

const REQUIRED_DEVICE_EXTENSIONS = [_][*:0]const u8 { Vulkan.SWAPCHAIN_EXTENSION_NAME };

var SNAP_ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const SNAP_ALLOCATOR = SNAP_ARENA.allocator();

pub const Backend = struct {
    instance: Instance,
    window: Window,
    device: Device,
    // swapchain: Swapchain,

    const Instance = struct {
        handler: Vulkan.Instance,

        fn new() !Instance {
            const extensions = try Glfw.get_required_instance_extensions(SNAP_ALLOCATOR);
            const instance_config = Vulkan.Instance.Config {
                .application = .{
                    .name = configuration.application_name,
                    .version = configuration.version,
                },
                .extensions = extensions,
            };

            const handler = Vulkan.Instance.new(instance_config, SNAP_ALLOCATOR) catch {
                configuration.logger.log(.Error, "Failed to create instance", .{});
                return error.InstanceCreateFailed;
            };

            return .{
                .handler = handler,
            };
        }

        fn destroy(self: *Instance) void {
            self.handler.destroy();
        }
    };

    const Window = struct {
        handler: *Glfw.Window,
        surface: Vulkan.Surface,
        width: u32,
        height: u32,

        fn new(instance: Vulkan.Instance, width: u32, height: u32) !Window {
            const handler = Glfw.create_window(width, height, &configuration.application_name[0]) catch {
                configuration.logger.log(.Error, "Glfw failed to create window", .{});
                return error.WindowCreate;
            };
            const surface = Glfw.create_window_surface(instance, handler, null) catch {
                configuration.logger.log(.Error, "Failed to create window surface", .{});
                return error.SurfaceInit;
            };

            return .{
                .handler = handler,
                .surface = surface,
                .width = width,
                .height = height,
            };
        }

        fn destroy(self: Window, instance: *Vulkan.Instance) void {
            instance.destroy_surface(self.surface);
            Glfw.destroy_window(self.handler);
        }
    };

    const Swapchain = struct {
        handler: Vulkan.Swapchain,
        // image_format: Vulkan.SurfaceFormat,
        image_views: []Vulkan.Swapchain.ImageView,
        depth_format: Vulkan.Format,
        // images: []Vulkan.Image,

        frames_in_flight: u8 = 2,
        // image_count: u8,

        fn new(device: *Device, instance: *Instance, window: Window) !Swapchain {
            const formats = instance.handler.get_physical_device_surface_formats(device.physical_device, window.surface) catch {
                configuration.logger.log(.Error, "Failed to list surface formats", .{});
                return error.ListSurfaceFormats;
            };

            const format = blk: for (formats) |format| {
                if (format.format == Vulkan.FORMAT_B8G8R8A8_SRGB and format.colorSpace == Vulkan.COLOR_SPACE_SRGB_NONLINEAR) {
                    break :blk format;
                }
            } else {
                configuration.logger.log(.Warn, "Could not find a good surface format falling back to first in list", .{});
                break :blk formats[0];
            };

            const present_modes = instance.handler.get_physical_device_surface_present_modes(device.physical_device, window.surface) catch {
                configuration.logger.log(.Error, "Failed to list present modes", .{});
                return error.ListSurfaceFormats;
            };

            const present_mode = blk: for (present_modes) |mode| {
                if (mode == Vulkan.PRESENT_MODE_MAILBOX) break :blk mode;
            } else {
                configuration.logger.log(.Warn, "Could not find a better present mode falling back to 'Fifo'", .{});
                break :blk Vulkan.PRESENT_MODE_FIFO;
            };

            const capabilities = try instance.handler.get_physical_device_surface_capabilities(device.physical_device, window.surface);

            const extent: Vulkan.Extent = blk: {
                if (capabilities.currentExtent.width != 0xFFFFFFFF) {
                    break :blk capabilities.currentExtent;
                } else {
                    const extent = Glfw.get_framebuffer_size(window.handler);

                    break :blk .{
                        .width = std.math.clamp(extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
                        .height = std.math.clamp(extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
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

            const uniques_queue_family_index = Device.QueueAllocator.uniques(&.{
                device.queue_allocator.graphics.family,
                device.queue_allocator.present.family,
            }) catch |e| {
                configuration.logger.log(.Error, "Failed to get uniques queue family index list", .{});
                return e;
            };

            const swapchain_config: Vulkan.Swapchain.Config = .{
                .image_count = image_count,
                .image_format = format.format,
                .image_color_space = format.colorSpace,
                .extent = extent,
                .surface = window.surface,
                .queue_families = uniques_queue_family_index.items,
                .sharing_mode = if (uniques_queue_family_index.items.len == 1) Vulkan.SHARING_MODE_EXCLUSIVE else Vulkan.SHARING_MODE_CONCURRENT,
                .present_mode = present_mode,
                .pre_transform = capabilities.currentTransform,
            };

            const handler = Vulkan.Swapchain.new(&device.handler, swapchain_config) catch |e| {
                configuration.logger.log(.Error, "Failed to validate swapchain configuration", .{});

                return e;
            };

            const images = device.handler.get_swapchain_images(handler) catch {
                configuration.logger.log(.Error, "Failed to get swapchain images", .{});
                return error.Images;
            };

            const image_views = SNAP_ALLOCATOR.alloc(Vulkan.Swapchain.ImageView, image_count) catch {
                configuration.logger.log(.Error, "Out of memory", .{});
                return error.OutOfMemory;
            };

            for (0..image_count) |i| {
                const view_config: Vulkan.Swapchain.ImageView.Config = .{
                    .image = images[i],
                    .format = format.format,
                };

                image_views[i] = Vulkan.Swapchain.ImageView.new(device.handler, view_config) catch |e| {
                    configuration.logger.log(.Error, "Failed to get image view from image", .{});
                    return e;
                };
            }

            const depth_formats = [_]Vulkan.Format {
                Vulkan.FORMAT_D32_SFLOAT,
                Vulkan.FORMAT_D32_SFLOAT_S8_UINT,
                Vulkan.FORMAT_D24_UNORM_S8_UINT,
            };

            const flags = Vulkan.FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
            const depth_format = blk: for (depth_formats) |candidate| {
                const format_properties = instance.handler.get_physical_device_format_properties(device.physical_device, candidate);
                if ((format_properties.linearTilingFeatures & flags) == flags or (format_properties.optimalTilingFeatures & flags) == flags) {
                    break :blk candidate;
                }
            } else {
                configuration.logger.log(.Error, "Failed to find suitable depth format", .{});
                return error.DepthFormat;
            };

            return .{
                .image_views = image_views,
                .handler = handler,
                .depth_format = depth_format,
            };
        }
    };

    const Device = struct {
        handler: Vulkan.Device,
        queue_allocator: QueueAllocator,

        physical_device: Vulkan.PhysicalDevice,
        physical_device_properties: Vulkan.PhysicalDeviceProperties,
        physical_device_properties_memory: Vulkan.PhysicalDeviceMemoryProperties,
        physical_device_features: Vulkan.PhysicalDeviceFeatures,

        const QueueAllocator = struct {
            graphics: Queue,
            present: Queue,
            compute: Queue,
            transfer: Queue,

            fn new(
                instance: *Vulkan.Instance,
                physical_device: Vulkan.PhysicalDevice,
                surface: Vulkan.Surface,
            ) !QueueAllocator {
                var families: [4]?u32 = .{null, null, null, null};

                const families_properties = instance.get_physical_device_queue_family_properties(physical_device) catch {
                    configuration.logger.log(.Error, "Failed to get queue family properties", .{});
                    return error.QueueFamily;
                };

                var min_transfer_score: u8 = 0xFF;
                for (families_properties, 0..) |properties, i| {
                    var current_transfer_score: u8 = 0;
                    const family: u32 = @intCast(i);

                    if (families[1] == null and try instance.get_physical_device_surface_support(physical_device, family, surface)) families[1] = family;
                    if (families[0] == null and Vulkan.bit(properties.queueFlags, Vulkan.QueueGraphicsBit)) {
                        families[0] = family;
                        current_transfer_score += 1;
                    }

                    if (families[2] == null and Vulkan.bit(properties.queueFlags, Vulkan.QueueComputeBit)) {
                        families[2] = family;
                        current_transfer_score += 1;
                    }

                    if (families[3] == null and Vulkan.bit(properties.queueFlags, Vulkan.QueueTransferBit) and current_transfer_score <= min_transfer_score) {
                        families[3] = family;
                        min_transfer_score = current_transfer_score;
                    }
                }

                return .{
                    .graphics = .{
                        .handler = null,
                        .family = families[0] orelse return error.NoGraphics,
                    },
                    .present = .{
                        .handler = null,
                        .family = families[1] orelse return error.NoPresent,
                    },
                    .compute = .{
                        .handler = null,
                        .family = families[2] orelse return error.NoCompute,
                    },
                    .transfer = .{
                        .handler = null,
                        .family = families[3] orelse return error.NoTransfer,
                    }
                };
            }

            fn uniques(queues: []const u32) !std.ArrayList(u32) {
                var uniques_array = std.ArrayList(u32).initCapacity(SNAP_ALLOCATOR, 1) catch {
                    configuration.logger.log(.Error, "Out of memory", .{});
                    return error.OutOfMemory;
                };

                const first = [_]u32 {queues[0]};
                uniques_array.appendSlice(&first) catch {
                    configuration.logger.log(.Error, "Out of memory", .{});
                    return error.OutOfMemory;
                };

                var size: u32 = 0;

                for (queues) |family| {
                    for (0..size + 1) |i| {
                        if (family == uniques_array.items[i]) break;
                    } else {
                        uniques_array.append(family) catch {
                            configuration.logger.log(.Error, "Failed to add member to uniques queue family index list", .{});
                            return error.OutOfMemory;
                        };
                        size += 1;
                    }
                }

                return uniques_array;
            }

            fn fill(self: *QueueAllocator, device: *Vulkan.Device) void {
                self.graphics.handler = device.get_device_queue(self.graphics.family);
                self.present.handler = device.get_device_queue(self.present.family);
                self.compute.handler = device.get_device_queue(self.compute.family);
                self.transfer.handler = device.get_device_queue(self.transfer.family);
            }

            const Queue = struct {
                handler: ?Vulkan.Queue,
                family: u32,
            };
        };

        fn new(
            instance: *Vulkan.Instance,
            surface: Vulkan.Surface,
        ) !Device {
            const physical_device = blk: {
                const physical_devices = instance.enumerate_physical_devices() catch {
                    configuration.logger.log(.Error, "Failed to list physical devices", .{});
                    return error.Failed;
                };

                var points: u32 = 1;
                var p_device: ?Vulkan.PhysicalDevice = null;

                for (physical_devices) |physical_device| {
                    const rating: u32 = rate: {
                        const extensions_properties = instance.enumerate_device_extension_properties(physical_device) catch {
                            configuration.logger.log(.Error, "Failed to enumerate extensions properties", .{});
                            break :rate 0;
                        };

                        const has_extension = ext: for (REQUIRED_DEVICE_EXTENSIONS) |extension| {
                            for (extensions_properties) |propertie| {
                                if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&propertie.extensionName, 0))) break :ext true;
                            }
                        } else {
                            break :ext false;
                        };

                        if (!has_extension) break :rate 0;

                        if (!((instance.get_physical_device_surface_formats(physical_device, surface) catch break :rate 0).len > 0)) break :rate 0;
                        if (!((instance.get_physical_device_surface_present_modes(physical_device, surface) catch break :rate 0).len > 0)) break :rate 0;

                        _ = QueueAllocator.new(instance, physical_device, surface) catch break :rate 0;

                        var sum: u8 = 1;

                        const physical_device_props = instance.get_physical_device_properties(physical_device);
                        const physical_device_feats = instance.get_physical_device_features(physical_device);

                        if (!Vulkan.boolean(physical_device_feats.geometryShader)) break :rate 0;
                        if (!Vulkan.boolean(physical_device_feats.samplerAnisotropy)) break :rate 0;

                        sum += switch (physical_device_props.deviceType) {
                            @intFromEnum(Vulkan.Device.Type.DiscreteGpu) => 4,
                            @intFromEnum(Vulkan.Device.Type.IntegratedGpu) => 3,
                            @intFromEnum(Vulkan.Device.Type.VirtualGpu) => 2,
                            @intFromEnum(Vulkan.Device.Type.Other) => 1,
                            else => 0,
                        };

                        break :rate sum;
                    };

                    if (rating >= points) {
                        points = rating;
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

            var queue_allocator = try QueueAllocator.new(instance, physical_device, surface);

            var logical_device = blk: {
                const priority: [1]f32 = .{1};
                const families = QueueAllocator.uniques(&.{
                    queue_allocator.graphics.family,
                    queue_allocator.present.family,
                    queue_allocator.compute.family,
                    queue_allocator.transfer.family,
                }) catch {
                    configuration.logger.log(.Error, "Could not get uniques queue family index for the selecter physical device", .{});
                    return error.FamliyIndex;
                };

                var queue_create_infos: []Vulkan.DeviceQueueCreateInfo = SNAP_ALLOCATOR.alloc(Vulkan.DeviceQueueCreateInfo, families.items.len) catch {
                    configuration.logger.log(.Error, "Out of memory", .{});
                    return error.OutOfMemory;
                };

                for (families.items, 0..) |family, i| {
                    queue_create_infos[i] = .{
                        .queueFamilyIndex = family,
                        .queueCount = 1,
                        .pQueuePriorities = &priority,
                    };
                }

                const device_config = Vulkan.Device.Config {
                    .queues = queue_create_infos,
                    .features = instance.get_physical_device_features(physical_device),
                    .extensions = &REQUIRED_DEVICE_EXTENSIONS,
                };

                break :blk Vulkan.Device.new(instance, physical_device, device_config, SNAP_ALLOCATOR) catch |e| {
                    configuration.logger.log(.Error, "Failed to create logical device handler", .{});
                    return e;
                };
            };

            queue_allocator.fill(&logical_device);

            const physical_device_properties = instance.get_physical_device_properties(physical_device);
            const physical_device_properties_memory = instance.get_physical_device_memory_properties(physical_device);
            const physical_device_features = instance.get_physical_device_features(physical_device);

            configuration.logger.log(.Info, "Selecting GPU: {s}", .{std.mem.sliceTo(&physical_device_properties.deviceName, 0)});

            return .{
                .queue_allocator = queue_allocator,
                .physical_device = physical_device,
                .physical_device_properties = physical_device_properties,
                .physical_device_properties_memory = physical_device_properties_memory,
                .physical_device_features = physical_device_features,
                .handler = logical_device,
            };
        }

        fn destroy(self: *Device) void {
            self.handler.destroy();
        }
    };

    pub fn new() !Backend {
        defer {
            _ = SNAP_ARENA.reset(.free_all);
        }

        try Glfw.init();

        var instance = Instance.new() catch {
            configuration.logger.log(.Error, "Failed to create instance", .{});
            return error.InstanceCreate;
        };

        const window = Window.new(instance.handler, configuration.default_width, configuration.default_height) catch {
            configuration.logger.log(.Error, "Failed to create window", .{});
            return error.WindowCreate;
        };

        var device = Device.new(&instance.handler, window.surface) catch {
            configuration.logger.log(.Error, "Failed to create device", .{});
            return error.DeviceCreate;
        };

        const swapchain = Swapchain.new(&device, &instance, window) catch {
            configuration.logger.log(.Error, "Failed to create swapchain", .{});
            return error.SwapchainCreate;

        };
        _ = swapchain;

        return .{
            .instance = instance,
            .window = window,
            .device = device,
        };
    }

    pub fn shutdown(self: *Backend) void {
        self.device.destroy();
        self.window.destroy(&self.instance.handler);
        self.instance.destroy();

        Glfw.shutdown();
    }
};
