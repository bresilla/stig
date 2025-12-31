const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Tree-sitter core dependency
    const tree_sitter_dep = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });

    // Tree-sitter C grammar dependency
    const tree_sitter_c_dep = b.dependency("tree_sitter_c", .{
        .target = target,
        .optimize = optimize,
        .@"build-shared" = false,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "stinger",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add tree-sitter module from zig-tree-sitter
    exe.root_module.addImport("tree-sitter", tree_sitter_dep.module("tree_sitter"));

    // Add tree-sitter-c module and link its library
    const ts_c_module = tree_sitter_c_dep.module("tree-sitter-c");
    ts_c_module.addImport("tree-sitter", tree_sitter_dep.module("tree_sitter"));
    exe.root_module.addImport("tree-sitter-c", ts_c_module);
    exe.linkLibrary(tree_sitter_c_dep.artifact("tree-sitter-c"));

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run stinger");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("tree-sitter", tree_sitter_dep.module("tree_sitter"));
    const test_ts_c_module = tree_sitter_c_dep.module("tree-sitter-c");
    test_ts_c_module.addImport("tree-sitter", tree_sitter_dep.module("tree_sitter"));
    unit_tests.root_module.addImport("tree-sitter-c", test_ts_c_module);
    unit_tests.linkLibrary(tree_sitter_c_dep.artifact("tree-sitter-c"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
