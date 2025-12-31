const std = @import("std");
const types = @import("model/types.zig");
const CParser = @import("parser/c.zig").CParser;
const CppParser = @import("parser/cpp.zig").CppParser;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;

/// File watcher for automatic regeneration
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    output_dir: []const u8,
    book_title: []const u8,
    serve_mode: bool,
    mdbook_process: ?std.process.Child = null,
    last_mod_times: std.StringHashMap(i128),
    debounce_ns: u64 = 100 * std.time.ns_per_ms, // 100ms debounce

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        input_files: []const []const u8,
        output_dir: []const u8,
        book_title: []const u8,
        serve_mode: bool,
    ) Self {
        return Self{
            .allocator = allocator,
            .input_files = input_files,
            .output_dir = output_dir,
            .book_title = book_title,
            .serve_mode = serve_mode,
            .last_mod_times = std.StringHashMap(i128).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopMdbook();
        self.last_mod_times.deinit();
    }

    /// Starts watching files and regenerating on changes
    pub fn run(self: *Self) !void {
        // Initial generation
        self.clearScreen();
        std.debug.print("🔍 Stinger Watch Mode\n", .{});
        std.debug.print("   Watching {d} file(s)\n", .{self.input_files.len});
        std.debug.print("   Output: {s}\n\n", .{self.output_dir});

        try self.regenerate();

        // Start mdbook serve if requested
        if (self.serve_mode) {
            try self.startMdbook();
        }

        // Initialize modification times
        for (self.input_files) |file| {
            const mtime = self.getModTime(file);
            try self.last_mod_times.put(file, mtime);
        }

        std.debug.print("👀 Watching for changes... (Ctrl+C to stop)\n\n", .{});

        // Watch loop
        var last_change: i64 = 0;
        while (true) {
            var changed = false;
            var changed_file: ?[]const u8 = null;

            for (self.input_files) |file| {
                const current_mtime = self.getModTime(file);
                const last_mtime = self.last_mod_times.get(file) orelse 0;

                if (current_mtime > last_mtime) {
                    changed = true;
                    changed_file = file;
                    try self.last_mod_times.put(file, current_mtime);
                }
            }

            if (changed) {
                const now = std.time.milliTimestamp();
                // Debounce: only regenerate if enough time has passed
                if (now - last_change > @as(i64, @intCast(self.debounce_ns / std.time.ns_per_ms))) {
                    last_change = now;
                    self.clearScreen();
                    std.debug.print("🔄 Change detected: {s}\n", .{changed_file orelse "unknown"});
                    self.regenerate() catch |err| {
                        std.debug.print("❌ Error regenerating: {}\n", .{err});
                    };
                    std.debug.print("\n👀 Watching for changes... (Ctrl+C to stop)\n\n", .{});
                }
            }

            // Sleep for a bit before checking again
            std.Thread.sleep(200 * std.time.ns_per_ms);
        }
    }

    /// Regenerates documentation
    fn regenerate(self: *Self) !void {
        const start_time = std.time.milliTimestamp();

        // Initialize parsers
        var c_parser = try CParser.init(self.allocator);
        defer c_parser.deinit();

        var cpp_parser = try CppParser.init(self.allocator);
        defer cpp_parser.deinit();

        // Parse all files
        var modules: std.ArrayList(types.Module) = .empty;
        defer modules.deinit(self.allocator);

        var sources: std.ArrayList([]const u8) = .empty;
        defer {
            for (sources.items) |src| {
                self.allocator.free(src);
            }
            sources.deinit(self.allocator);
        }

        for (self.input_files) |input_file| {
            const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
                std.debug.print("   ⚠️  Cannot open {s}: {}\n", .{ input_file, err });
                continue;
            };
            defer file.close();

            const source = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
                std.debug.print("   ⚠️  Cannot read {s}: {}\n", .{ input_file, err });
                continue;
            };
            try sources.append(self.allocator, source);

            const is_cpp = isCppFile(input_file);
            const module = if (is_cpp)
                try cpp_parser.parse(source, input_file)
            else
                try c_parser.parse(source, input_file);

            try modules.append(self.allocator, module);
        }

        // Generate mdbook
        const mdbook_config = MdbookConfig{
            .title = self.book_title,
            .output_dir = self.output_dir,
            .generate_intro = true,
        };

        var mdbook_gen = MdbookGenerator.initWithConfig(self.allocator, mdbook_config);
        defer mdbook_gen.deinit();

        try mdbook_gen.generate(modules.items);

        const elapsed = std.time.milliTimestamp() - start_time;
        std.debug.print("✅ Generated in {d}ms\n", .{elapsed});
    }

    /// Starts mdbook serve subprocess
    fn startMdbook(self: *Self) !void {
        std.debug.print("🚀 Starting mdbook serve...\n", .{});

        var child = std.process.Child.init(
            &[_][]const u8{ "mdbook", "serve", self.output_dir, "--open" },
            self.allocator,
        );
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        self.mdbook_process = child;

        std.debug.print("   mdbook serve running at http://localhost:3000\n\n", .{});
    }

    /// Stops mdbook serve subprocess
    fn stopMdbook(self: *Self) void {
        if (self.mdbook_process) |*proc| {
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};
            self.mdbook_process = null;
        }
    }

    /// Gets file modification time
    fn getModTime(self: *Self, path: []const u8) i128 {
        _ = self;
        const file = std.fs.cwd().openFile(path, .{}) catch return 0;
        defer file.close();

        const stat = file.stat() catch return 0;
        return stat.mtime;
    }

    /// Clears the terminal screen
    fn clearScreen(self: *Self) void {
        _ = self;
        // ANSI escape codes to clear screen and move cursor to top
        std.debug.print("\x1b[2J\x1b[H", .{});
    }
};

/// Checks if a file is a C++ file based on extension
fn isCppFile(filename: []const u8) bool {
    const cpp_extensions = [_][]const u8{ ".cpp", ".cxx", ".cc", ".hpp", ".hxx", ".hh", ".C", ".H" };
    for (cpp_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
}

// Tests
test "watcher init" {
    var watcher = Watcher.init(
        std.testing.allocator,
        &[_][]const u8{"test.h"},
        "docs",
        "Test",
        false,
    );
    defer watcher.deinit();
}
