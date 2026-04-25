const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "git-stage-lines",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run git-stage-lines");
    run_step.dependOn(&run_cmd.step);

    const unit_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/cli/ranges.test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests_mod.addImport("cli", b.createModule(.{
        .root_source_file = b.path("src/cli/root.zig"),
        .target = target,
        .optimize = optimize,
    }));

    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run Zig tests");
    test_step.dependOn(&run_unit_tests.step);
}
