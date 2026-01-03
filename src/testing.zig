const std = @import("std");
const config_mod = @import("config.zig");
const toml = @import("toml");

/// Test output format
pub const TestOutputFormat = enum {
    console,
    json,
    junit,
};

/// Test configuration from stig.toml [test] section
pub const TestConfig = struct {
    /// Directory containing test files
    dir: []const u8 = "test",
    /// Compiler to use
    compiler: []const u8 = "g++",
    /// Compiler flags
    flags: []const []const u8 = &[_][]const u8{ "-std=c++17", "-Wall", "-Wextra" },
    /// Include paths
    include_paths: []const []const u8 = &[_][]const u8{},
    /// Libraries to link
    libraries: []const []const u8 = &[_][]const u8{},
    /// Test file pattern
    pattern: []const u8 = "test_*.cpp",
    /// Output format
    format: TestOutputFormat = .console,
};

/// Test runner - discovers, compiles, and runs tests
pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    config: TestConfig,
    output_format: TestOutputFormat,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: TestConfig, output_format: TestOutputFormat) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .output_format = output_format,
        };
    }

    /// Runs tests from the configured test directory
    pub fn run(self: *Self) !u8 {
        // Discover test files
        var test_files = try self.discoverTestFiles();
        defer {
            for (test_files.items) |f| {
                self.allocator.free(f);
            }
            test_files.deinit(self.allocator);
        }

        if (test_files.items.len == 0) {
            std.debug.print("No test files found matching pattern '{s}' in '{s}'\n", .{
                self.config.pattern,
                self.config.dir,
            });
            return 1;
        }

        std.debug.print("Found {d} test file(s)\n", .{test_files.items.len});

        // Compile tests
        const binary_path = try self.compileTests(test_files.items);
        defer self.allocator.free(binary_path);

        // Run the test binary
        return try self.runBinary(binary_path);
    }

    /// Runs a pre-compiled test binary
    pub fn runBinary(self: *Self, binary_path: []const u8) !u8 {
        std.debug.print("Running: {s}\n\n", .{binary_path});

        var child = std.process.Child.init(&[_][]const u8{binary_path}, self.allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();
        const term = try child.wait();

        return switch (term) {
            .Exited => |code| code,
            else => 1,
        };
    }

    /// Discovers test files matching the pattern
    fn discoverTestFiles(self: *Self) !std.ArrayList([]const u8) {
        var files: std.ArrayList([]const u8) = .empty;

        var dir = std.fs.cwd().openDir(self.config.dir, .{ .iterate = true }) catch |err| {
            std.debug.print("Error: Cannot open test directory '{s}': {}\n", .{ self.config.dir, err });
            return files;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check if file matches pattern
            if (self.matchPattern(entry.name)) {
                const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
                    self.config.dir,
                    entry.name,
                });
                try files.append(self.allocator, full_path);
            }
        }

        return files;
    }

    /// Simple glob pattern matching for test file discovery
    fn matchPattern(self: *Self, name: []const u8) bool {
        const pattern = self.config.pattern;

        // Handle simple patterns like "test_*.cpp"
        if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
            const prefix = pattern[0..star_pos];
            const suffix = pattern[star_pos + 1 ..];

            // Check prefix
            if (!std.mem.startsWith(u8, name, prefix)) {
                return false;
            }

            // Check suffix
            if (!std.mem.endsWith(u8, name, suffix)) {
                return false;
            }

            return true;
        }

        // Exact match
        return std.mem.eql(u8, name, pattern);
    }

    /// Compiles test files into a single binary
    fn compileTests(self: *Self, test_files: []const []const u8) ![]const u8 {
        // Build compiler command
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(self.allocator);

        // Compiler
        try args.append(self.allocator, self.config.compiler);

        // Flags
        for (self.config.flags) |flag| {
            try args.append(self.allocator, flag);
        }

        // Include paths
        for (self.config.include_paths) |inc| {
            const inc_flag = try std.fmt.allocPrint(self.allocator, "-I{s}", .{inc});
            try args.append(self.allocator, inc_flag);
        }

        // Include test directory for stig_test.h
        const test_inc = try std.fmt.allocPrint(self.allocator, "-I{s}", .{self.config.dir});
        try args.append(self.allocator, test_inc);

        // Test files
        for (test_files) |file| {
            try args.append(self.allocator, file);
        }

        // Main file
        const main_file = try std.fmt.allocPrint(self.allocator, "{s}/main.cpp", .{self.config.dir});
        try args.append(self.allocator, main_file);

        // Output binary
        const output_path = try std.fmt.allocPrint(self.allocator, "/tmp/stig_test_{d}", .{
            std.time.timestamp(),
        });
        try args.append(self.allocator, "-o");
        try args.append(self.allocator, output_path);

        // Libraries
        for (self.config.libraries) |lib| {
            const lib_flag = try std.fmt.allocPrint(self.allocator, "-l{s}", .{lib});
            try args.append(self.allocator, lib_flag);
        }

        // Print compile command
        std.debug.print("Compiling: ", .{});
        for (args.items) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print("\n\n", .{});

        // Run compiler
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();
        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("\nCompilation failed with exit code {d}\n", .{code});
                    return error.CompilationFailed;
                }
            },
            else => {
                std.debug.print("\nCompilation terminated abnormally\n", .{});
                return error.CompilationFailed;
            },
        }

        return output_path;
    }
};

/// Runs the test command
pub fn runTest(
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    config_file: ?[]const u8,
    output_format: TestOutputFormat,
) !u8 {
    // Load config
    var config = TestConfig{};

    const config_path = config_file orelse "stig.toml";
    if (loadTestConfig(allocator, config_path)) |loaded| {
        config = loaded;
    } else |_| {
        // Use defaults if no config
    }

    // Override format from CLI
    config.format = output_format;

    // If specific files provided, check if it's a binary or source files
    if (input_files.len > 0) {
        const first_file = input_files[0];

        // Check if it's an executable (no .cpp extension)
        if (!std.mem.endsWith(u8, first_file, ".cpp") and
            !std.mem.endsWith(u8, first_file, ".cc") and
            !std.mem.endsWith(u8, first_file, ".cxx"))
        {
            // Assume it's a pre-compiled binary
            var runner = TestRunner.init(allocator, config, output_format);
            return try runner.runBinary(first_file);
        }

        // Otherwise, compile and run the specified source files
        var runner = TestRunner.init(allocator, config, output_format);
        const binary_path = try runner.compileTests(input_files);
        defer allocator.free(binary_path);
        return try runner.runBinary(binary_path);
    }

    // Run from config
    var runner = TestRunner.init(allocator, config, output_format);
    return try runner.run();
}

/// TOML structure for [test] section
const TomlTestConfig = struct {
    @"test": ?TestSection = null,

    const TestSection = struct {
        dir: ?[]const u8 = null,
        compiler: ?[]const u8 = null,
        flags: ?[]const []const u8 = null,
        include_paths: ?[]const []const u8 = null,
        libraries: ?[]const []const u8 = null,
        pattern: ?[]const u8 = null,
    };
};

/// Loads test configuration from stig.toml
/// Note: The returned config contains slices that point to static strings or
/// strings owned by the caller. The caller should not free these.
fn loadTestConfig(allocator: std.mem.Allocator, path: []const u8) !TestConfig {
    // Read file content
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return error.ConfigNotFound;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    // Don't free content - it's needed for the string slices

    // Parse TOML
    var parser = toml.Parser(TomlTestConfig).init(allocator);
    // Don't deinit parser - it owns the parsed data

    const parsed = parser.parseString(content) catch {
        allocator.free(content);
        return TestConfig{};
    };
    // Don't deinit parsed - the slices point into it

    const tc = parsed.value;

    // Build config from parsed values
    var config = TestConfig{};

    if (tc.@"test") |t| {
        if (t.dir) |d| config.dir = d;
        if (t.compiler) |c| config.compiler = c;
        if (t.flags) |f| config.flags = f;
        if (t.include_paths) |i| config.include_paths = i;
        if (t.libraries) |l| config.libraries = l;
        if (t.pattern) |p| config.pattern = p;
    }

    return config;
}
