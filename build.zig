const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall
    });
    const core = b.addModule("core", .{ .root_source_file = .{ .path = "core/lib.zig" } });
    const generator = b.addModule("generator", .{ .root_source_file = .{ .path = "generator/lib.zig" } });

    const exe = b.addExecutable(.{
        .name = "engine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "test/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    generator.addImport("core", core);

    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.root_module.addImport("core", core);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run vulkan application");

    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    unit_tests.root_module.addImport("core", core);
    unit_tests.root_module.addImport("generator", generator);

    const run_test = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_test.step);
}
