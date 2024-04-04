const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const core = builder.addModule("core", .{
        .root_source_file = .{ .path = "core/lib.zig" },
        .target = target
    });

    const exe = builder.addExecutable(.{
        .name = "engine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = builder.addTest(.{
        .root_source_file = .{ .path = "test/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    scan_wayland_xml(builder, "private-code", "bin/include/xdg-shell.c");
    scan_wayland_xml(builder, "client-header", "bin/include/xdg-shell.h");

    add_shader(builder, "vert");
    add_shader(builder, "frag");

    core.addCSourceFile(.{ .file = .{ .path = "zig-out/bin/include/xdg-shell.c" } });
    core.addIncludePath(.{ .path = "zig-out/bin/include" });
    core.addIncludePath(.{ .path = "outputs/out/include" });
    core.linkSystemLibrary("wayland-client", .{});

    exe.linkLibC();
    exe.root_module.addImport("core", core);

    builder.installArtifact(exe);

    const run_cmd = builder.addRunArtifact(exe);
    const run_step = builder.step("run", "Run the engine");

    run_cmd.step.dependOn(builder.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    unit_tests.linkLibC();
    unit_tests.root_module.addImport("core", core);

    const run_test = builder.addRunArtifact(unit_tests);
    const test_step = builder.step("test", "Run unit tests");

    test_step.dependOn(&run_test.step);
}

fn scan_wayland_xml(builder: *std.Build, flag: []const u8, output: []const u8) void {
    const scanner = builder.addSystemCommand(&.{"wayland-scanner"});

    scanner.addArgs(&.{ flag, "assets/xdg-shell.xml" });
    const out = scanner.addOutputFileArg(output);

    builder.getInstallStep().dependOn(&builder.addInstallFileWithDir(out, .prefix, output).step);
}

fn add_shader(builder: *std.Build, file: []const u8) void {
    const glslc = builder.addSystemCommand(&.{"glslc"});
    const output = builder.fmt("shader/{s}.shader", .{file});

    glslc.addArgs(&.{
        builder.fmt("assets/shader/shader.{s}", .{file}),
        "-o",
    });

    const out = glslc.addOutputFileArg(output);
    builder.getInstallStep().dependOn(&builder.addInstallFileWithDir(out, .prefix, output).step);
}
