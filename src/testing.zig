const std = @import("std");

/// Test output format
pub const TestOutputFormat = enum {
    console,
    json,
    junit,
};

/// Runs a pre-compiled test binary
pub fn runTest(
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    _: ?[]const u8, // config_file - unused now
    _: TestOutputFormat, // output_format - unused now
) !u8 {
    if (input_files.len == 0) {
        std.debug.print("Usage: stig test <binary> [binary...]\n", .{});
        std.debug.print("\nRun pre-compiled test binaries.\n", .{});
        std.debug.print("Use CMake with stig_add_tests() to compile tests.\n", .{});
        return 1;
    }

    var total_failed: u8 = 0;

    for (input_files) |binary_path| {
        std.debug.print("Running: {s}\n\n", .{binary_path});

        var child = std.process.Child.init(&[_][]const u8{binary_path}, allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();
        const term = try child.wait();

        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        if (exit_code != 0) {
            total_failed += 1;
        }

        if (input_files.len > 1) {
            std.debug.print("\n", .{});
        }
    }

    if (total_failed > 0 and input_files.len > 1) {
        std.debug.print("==========================================================\n", .{});
        std.debug.print("{d}/{d} test(s) failed\n", .{ total_failed, input_files.len });
        std.debug.print("==========================================================\n", .{});
    }

    return if (total_failed > 0) 1 else 0;
}
