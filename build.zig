const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tui_dep = b.dependency("tui", .{
        .target = target,
        .optimize = optimize,
    });
    const tui_mod = tui_dep.module("tui");

    const avocado_mod = b.addModule("Avocado", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe_root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "Avocado", .module = avocado_mod },
            .{ .name = "tui", .module = tui_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "avocado",
        .root_module = exe_root,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the Avocado TUI");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = avocado_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe_root,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run Zig tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
