const _config = @import("../../util/configuration.zig");
const _platform = @import("../../platform/platform.zig");

const c = _platform.c;
const configuration = _config.Configuration;
const logger = configuration.logger;

pub const Result = error {
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

pub fn check(result: i32) Result!void {
    switch (result) {
            c.VK_SUCCESS => return,
            c.VK_NOT_READY => {
                logger.log(.Warn, "Vulkan result failed with: 'NotReady", .{});
                return Result.NotReady;
            },
            c.VK_TIMEOUT => {
                logger.log(.Warn, "Vulkan result failed with: 'Timeout", .{});
                return Result.Timeout;
            },
            c.VK_EVENT_SET => {
                logger.log(.Warn, "Vulkan result failed with: 'EventSet", .{});
                return Result.EventSet;
            },
            c.VK_EVENT_RESET => {
                logger.log(.Warn, "Vulkan result failed with: 'EventReset", .{});
                return Result.EventReset;
            },
            c.VK_INCOMPLETE => {
                logger.log(.Warn, "Vulkan result failed with: Incomplete", .{});
                return Result.Incomplete;
            },
            c.VK_ERROR_OUT_OF_HOST_MEMORY => {
                logger.log(.Warn, "Vulkan result failed with 'OutOfHostMemory", .{});
                return Result.OutOfHostMemory;
            },
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
                logger.log(.Warn, "Vulkan result failed with: 'OutOfDeviceMemory'", .{});
                return Result.OutOfDeviceMemory;
            },
            c.VK_ERROR_INITIALIZATION_FAILED => {
                logger.log(.Warn, "Vulkan result failed with: 'InitializationFailed'", .{});
                return Result.InitializationFailed;
            },
            c.VK_ERROR_DEVICE_LOST => {
                logger.log(.Warn, "Vulkan result failed with: 'DeviceLost'", .{});
                return Result.DeviceLost;
            },
            c.VK_ERROR_MEMORY_MAP_FAILED => {
                logger.log(.Warn, "Vulkan result failed with: 'MemoryMapFailed'", .{});
                return Result.MemoryMapFailed;
            },
            c.VK_ERROR_LAYER_NOT_PRESENT => {
                logger.log(.Warn, "Vulkan result failed with: 'LayerNotPresent'", .{});
                return Result.LayerNotPresent;
            },
            c.VK_ERROR_EXTENSION_NOT_PRESENT => {
                logger.log(.Warn, "Vulkan result failed with: 'ExtensionNotPresent'", .{});
                return Result.ExtensionNotPresent;
            },
            c.VK_ERROR_FEATURE_NOT_PRESENT => {
                logger.log(.Warn, "Vulkan result failed with: 'FeatureNotPresent'", .{});
                return Result.FeatureNotPresent;
            },
            c.VK_ERROR_INCOMPATIBLE_DRIVER => {
                logger.log(.Warn, "Vulkan result failed with: 'IncompatibleDriver'", .{});
                return Result.IncompatibleDriver;
            },
            c.VK_ERROR_TOO_MANY_OBJECTS => {
                logger.log(.Warn, "Vulkan result failed with: 'TooManyObjects'", .{});
                return Result.TooManyObjects;
            },
            c.VK_ERROR_FORMAT_NOT_SUPPORTED => {
                logger.log(.Warn, "Vulkan result failed with: 'FormatNotSupported'", .{});
                return Result.FormatNotSupported;
            },
            c.VK_ERROR_FRAGMENTED_POOL => {
                logger.log(.Warn, "Vulkan result failed with: 'FragmentedPool'", .{});
                return Result.FragmentedPool;
            },
            c.VK_ERROR_UNKNOWN => {
                logger.log(.Warn, "Vulkan result failed with: 'Unknown'", .{});
                return Result.Unknown;
            },
            c.VK_ERROR_INVALID_EXTERNAL_HANDLE => {
                logger.log(.Warn, "Vulkan result failed with: 'InvalidExternalHandle'", .{});
                return Result.InvalidExternalHandle;
            },
            c.VK_ERROR_FRAGMENTATION => {
                logger.log(.Warn, "Vulkan result failed with: 'Fragmentation'", .{});
                return Result.Fragmentation;
            },
            c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => {
                logger.log(.Warn, "Vulkan result failed with: 'InvalidOpaqueCaptureAddress'", .{});
                return Result.InvalidOpaqueCaptureAddress;
            },
            c.VK_PIPELINE_COMPILE_REQUIRED => {
                logger.log(.Warn, "Vulkan result failed with: 'PipelineCompileRequired'", .{});
                return Result.PipelineCompileRequired;
            },
            c.VK_ERROR_SURFACE_LOST_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'SurfaceLostKhr'", .{});
                return Result.SurfaceLostKhr;
            },
            c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'NativeWindowInUseKhr'", .{});
                return Result.NativeWindowInUseKhr;
            },
            c.VK_SUBOPTIMAL_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'SuboptimalKhr'", .{});
                return Result.SuboptimalKhr;
            },
            c.VK_ERROR_OUT_OF_DATE_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'OutOfDateKhr'", .{});
                return Result.OutOfDateKhr;
            },
            c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'IncompatibleDisplayKhr'", .{});
                return Result.IncompatibleDisplayKhr;
            },
            c.VK_ERROR_VALIDATION_FAILED_EXT => {
                logger.log(.Warn, "Vulkan result failed with: 'ValidationFailedExt'", .{});
                return Result.ValidationFailedExt;
            },
            c.VK_ERROR_INVALID_SHADER_NV => {
                logger.log(.Warn, "Vulkan result failed with: 'InvalidShaderNv'", .{});
                return Result.InvalidShaderNv;
            },
            c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'ImageUsageNotSupportedKhr'", .{});
                return Result.ImageUsageNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'VideoPictureLayoutNotSupportedKhr'", .{});
                return Result.VideoPictureLayoutNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'VideoProfileOperationNotSupportedKhr'", .{});
                return Result.VideoProfileOperationNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'VideoProfileFormatNotSupportedKhr'", .{});
                return Result.VideoProfileFormatNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'VideoProfileCodecNotSupportedKhr'", .{});
                return Result.VideoProfileCodecNotSupportedKhr;
            },
            c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'VideoStdVersionNotSupportedKhr'", .{});
                return Result.VideoStdVersionNotSupportedKhr;
            },
            c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => {
                logger.log(.Warn, "Vulkan result failed with: 'InvalidDrmFormatModifierPlaneLayoutExt'", .{});
                return Result.InvalidDrmFormatModifierPlaneLayoutExt;
            },
            c.VK_ERROR_NOT_PERMITTED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'NotPermittedKhr'", .{});
                return Result.NotPermittedKhr;
            },
            c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => {
                logger.log(.Warn, "Vulkan result failed with: 'FullScreenExclusiveModeLostExt'", .{});
                return Result.FullScreenExclusiveModeLostExt;
            },
            c.VK_THREAD_IDLE_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'ThreadIdleKhr'", .{});
                return Result.ThreadIdleKhr;
            },
            c.VK_THREAD_DONE_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'ThreadDoneKhr'", .{});
                return Result.ThreadDoneKhr;
            },
            c.VK_OPERATION_DEFERRED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'OperationDeferredKhr'", .{});
                return Result.OperationDeferredKhr;
            },
            c.VK_OPERATION_NOT_DEFERRED_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'OperationNotDeferredKhr'", .{});
                return Result.OperationNotDeferredKhr;
            },
            c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'InvalidVideoStdParametersKhr'", .{});
                return Result.InvalidVideoStdParametersKhr;
            },
            c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => {
                logger.log(.Warn, "Vulkan result failed with: 'CompressionExhaustedExt'", .{});
                return Result.CompressionExhaustedExt;
            },
            c.VK_ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => {
                logger.log(.Warn, "Vulkan result failed with: 'IncompatibleShaderBinaryExt'", .{});
                return Result.IncompatibleShaderBinaryExt;
            },
            c.VK_ERROR_OUT_OF_POOL_MEMORY_KHR => {
                logger.log(.Warn, "Vulkan result failed with: 'OutOfPoolMemoryKhr'", .{});
                return Result.OutOfPoolMemoryKhr;
            },

            else => {
                logger.log(.Warn, "Vulkan result failed with code: ({})", .{result});
                return Result.Else;
            }
    }
}
