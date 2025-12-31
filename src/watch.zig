const std = @import("std");
const types = @import("model/types.zig");
const CParser = @import("parser/c.zig").CParser;
const CppParser = @import("parser/cpp.zig").CppParser;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const Cache = @import("cache.zig").Cache;

/// File watcher for automatic regeneration with incremental updates
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    output_dir: []const u8,
    book_title: []const u8,
    serve_mode: bool,
    mdbook_process: ?std.process.Child = null,
    last_mod_times: std.StringHashMap(i128),
    debounce_ns: u64 = 100 * std.time.ns_per_ms, // 100ms debounce
    cache: Cache,
    /// Cached modules from previous parse (for incremental updates)
    cached_modules: std.StringHashMap(types.Module),

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        input_files: []const []const u8,
        output_dir: []const u8,
        book_title: []const u8,
        serve_mode: bool,
    ) Self {
        // Cache directory inside output dir - allocate properly
        const cache_dir = std.fs.path.join(allocator, &.{ output_dir, ".stinger-cache" }) catch output_dir;

        return Self{
            .allocator = allocator,
            .input_files = input_files,
            .output_dir = output_dir,
            .book_title = book_title,
            .serve_mode = serve_mode,
            .last_mod_times = std.StringHashMap(i128).init(allocator),
            .cache = Cache.init(allocator, cache_dir),
            .cached_modules = std.StringHashMap(types.Module).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopMdbook();
        self.last_mod_times.deinit();
        self.cache.save() catch {}; // Save cache on exit
        self.cache.deinit();
        self.cached_modules.deinit();
    }

    /// Starts watching files and regenerating on changes
    pub fn run(self: *Self) !void {
        // Load cache from disk
        self.cache.load() catch |err| {
            std.debug.print("   ⚠️  Could not load cache: {}\n", .{err});
        };

        // Initial generation
        self.clearScreen();
        std.debug.print("🔍 Stinger Watch Mode (with incremental updates)\n", .{});
        std.debug.print("   Watching {d} file(s)\n", .{self.input_files.len});
        std.debug.print("   Output: {s}\n\n", .{self.output_dir});

        // Full regeneration on startup
        try self.regenerate(null);

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
            var changed_files: std.ArrayList([]const u8) = .empty;
            defer changed_files.deinit(self.allocator);

            for (self.input_files) |file| {
                const current_mtime = self.getModTime(file);
                const last_mtime = self.last_mod_times.get(file) orelse 0;

                if (current_mtime > last_mtime) {
                    try changed_files.append(self.allocator, file);
                    try self.last_mod_times.put(file, current_mtime);
                }
            }

            if (changed_files.items.len > 0) {
                const now = std.time.milliTimestamp();
                // Debounce: only regenerate if enough time has passed
                if (now - last_change > @as(i64, @intCast(self.debounce_ns / std.time.ns_per_ms))) {
                    last_change = now;
                    self.clearScreen();
                    std.debug.print("🔄 Change detected in {d} file(s):\n", .{changed_files.items.len});
                    for (changed_files.items) |f| {
                        std.debug.print("   - {s}\n", .{f});
                    }
                    std.debug.print("\n", .{});

                    // Incremental regeneration - only re-parse changed files
                    self.regenerate(changed_files.items) catch |err| {
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
    /// If changed_files is null, regenerates all files (full rebuild)
    /// If changed_files is provided, only re-parses those files (incremental)
    fn regenerate(self: *Self, changed_files: ?[]const []const u8) !void {
        const start_time = std.time.milliTimestamp();

        // Initialize parsers
        var c_parser = try CParser.init(self.allocator);
        defer c_parser.deinit();

        var cpp_parser = try CppParser.init(self.allocator);
        defer cpp_parser.deinit();

        // Determine which files to parse
        const files_to_parse = changed_files orelse self.input_files;
        const is_incremental = changed_files != null;

        if (is_incremental) {
            std.debug.print("📦 Incremental update: re-parsing {d} file(s)\n", .{files_to_parse.len});
        } else {
            std.debug.print("📦 Full rebuild: parsing {d} file(s)\n", .{files_to_parse.len});
        }

        // Parse files that need updating
        var sources: std.ArrayList([]const u8) = .empty;
        defer {
            for (sources.items) |src| {
                self.allocator.free(src);
            }
            sources.deinit(self.allocator);
        }

        for (files_to_parse) |input_file| {
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

            // Set base path for include directives
            const base_path = std.fs.path.dirname(input_file) orelse ".";
            c_parser.setBasePath(base_path);
            cpp_parser.setBasePath(base_path);

            const is_cpp = isCppFile(input_file);
            const module = if (is_cpp)
                try cpp_parser.parse(source, input_file)
            else
                try c_parser.parse(source, input_file);

            // Update cached module
            try self.cached_modules.put(input_file, module);

            // Update file cache
            self.cache.updateFile(input_file) catch |err| {
                std.debug.print("   ⚠️  Cannot update cache for {s}: {}\n", .{ input_file, err });
            };
        }

        // Collect all modules (cached + newly parsed)
        var modules: std.ArrayList(types.Module) = .empty;
        defer modules.deinit(self.allocator);

        for (self.input_files) |input_file| {
            if (self.cached_modules.get(input_file)) |module| {
                try modules.append(self.allocator, module);
            }
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

        // Save cache
        self.cache.save() catch |err| {
            std.debug.print("   ⚠️  Cannot save cache: {}\n", .{err});
        };

        const elapsed = std.time.milliTimestamp() - start_time;
        if (is_incremental) {
            std.debug.print("✅ Incremental update in {d}ms\n", .{elapsed});
        } else {
            std.debug.print("✅ Full rebuild in {d}ms\n", .{elapsed});
        }
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
