const std = @import("std");
const builtin = @import("builtin");
const types = @import("model/types.zig");
const CParser = @import("parser/c.zig").CParser;
const CppParser = @import("parser/cpp.zig").CppParser;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const Cache = @import("cache.zig").Cache;
const FileWatcher = @import("filewatcher.zig").FileWatcher;
const Config = @import("config.zig").Config;

/// File watcher for automatic regeneration with incremental updates
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    output_dir: []const u8,
    book_title: []const u8,
    serve_mode: bool,
    mdbook_process: ?std.process.Child = null,
    debounce_ns: u64 = 100 * std.time.ns_per_ms, // 100ms debounce
    cache: Cache,
    /// Cached modules from previous parse (for incremental updates)
    cached_modules: std.StringHashMap(types.Module),
    /// Native file watcher (inotify on Linux, polling fallback)
    file_watcher: FileWatcher,
    /// Patterns to ignore (glob patterns)
    ignore_patterns: []const []const u8,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        input_files: []const []const u8,
        output_dir: []const u8,
        book_title: []const u8,
        serve_mode: bool,
    ) Self {
        return initWithConfig(allocator, input_files, output_dir, book_title, serve_mode, .{});
    }

    pub fn initWithConfig(
        allocator: std.mem.Allocator,
        input_files: []const []const u8,
        output_dir: []const u8,
        book_title: []const u8,
        serve_mode: bool,
        watch_config: Config.WatchOptions,
    ) Self {
        // Cache directory inside output dir - allocate properly
        const cache_dir = std.fs.path.join(allocator, &.{ output_dir, ".stig-cache" }) catch output_dir;

        return Self{
            .allocator = allocator,
            .input_files = input_files,
            .output_dir = output_dir,
            .book_title = book_title,
            .serve_mode = serve_mode,
            .debounce_ns = @as(u64, watch_config.debounce_ms) * std.time.ns_per_ms,
            .cache = Cache.init(allocator, cache_dir),
            .cached_modules = std.StringHashMap(types.Module).init(allocator),
            .file_watcher = FileWatcher.init(allocator),
            .ignore_patterns = watch_config.ignore_patterns,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopMdbook();
        self.file_watcher.deinit();
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
        const backend_name = if (builtin.os.tag == .linux) "inotify" else "polling";
        std.debug.print("🔍 Stinger Watch Mode (using {s})\n", .{backend_name});
        std.debug.print("   Watching {d} file(s)\n", .{self.input_files.len});
        std.debug.print("   Output: {s}\n\n", .{self.output_dir});

        // Full regeneration on startup
        try self.regenerate(null);

        // Start mdbook serve if requested
        if (self.serve_mode) {
            try self.startMdbook();
        }

        // Add all files to the native watcher
        for (self.input_files) |file| {
            self.file_watcher.addWatch(file) catch |err| {
                std.debug.print("   ⚠️  Cannot watch {s}: {}\n", .{ file, err });
            };
        }

        std.debug.print("👀 Watching for changes... (Ctrl+C to stop)\n\n", .{});

        // Watch loop using native file watcher
        var last_change: i64 = 0;
        while (true) {
            // Wait for file changes (with 1 second timeout to allow Ctrl+C)
            const events = self.file_watcher.waitForChanges(1000) catch null;

            if (events) |evts| {
                var events_list = evts;
                defer events_list.deinit(self.allocator);

                if (events_list.items.len > 0) {
                    // Filter out ignored files
                    var changed_files: std.ArrayList([]const u8) = .empty;
                    defer changed_files.deinit(self.allocator);

                    for (events_list.items) |event| {
                        if (!shouldIgnore(event.path, self.ignore_patterns)) {
                            try changed_files.append(self.allocator, event.path);
                        }
                    }

                    // Only proceed if there are non-ignored changes
                    if (changed_files.items.len > 0) {
                        const now = std.time.milliTimestamp();
                        // Debounce: only regenerate if enough time has passed
                        if (now - last_change > @as(i64, @intCast(self.debounce_ns / std.time.ns_per_ms))) {
                            last_change = now;
                            self.clearScreen();
                            std.debug.print("🔄 Change detected in {d} file(s):\n", .{changed_files.items.len});

                            for (changed_files.items) |path| {
                                std.debug.print("   - {s}\n", .{path});
                            }
                            std.debug.print("\n", .{});

                            // Incremental regeneration - only re-parse changed files
                            self.regenerate(changed_files.items) catch |err| {
                                std.debug.print("❌ Error regenerating: {}\n", .{err});
                            };
                            std.debug.print("\n👀 Watching for changes... (Ctrl+C to stop)\n\n", .{});
                        }
                    }
                }
            }
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
            // Skip implementation files - only check headers for documentation
            if (!isHeaderFile(input_file)) {
                std.debug.print("   ⏭️  Skipping implementation file: {s}\n", .{input_file});
                continue;
            }

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

    /// Clears the terminal screen
    fn clearScreen(self: *Self) void {
        _ = self;
        // ANSI escape codes to clear screen and move cursor to top
        std.debug.print("\x1b[2J\x1b[H", .{});
    }
};

/// Check if a file is a C/C++ header file that should be documented
/// Following standardese and doxygen conventions, only header files should
/// contain documentation comments. Implementation files (.cpp, .cc, .cxx) are excluded.
fn isHeaderFile(filename: []const u8) bool {
    // C headers
    if (std.mem.endsWith(u8, filename, ".h")) return true;

    // C++ headers
    const cpp_header_extensions = [_][]const u8{ ".hpp", ".hxx", ".hh", ".H" };
    for (cpp_header_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
}

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

/// Matches a path against a glob pattern
/// Supports: * (any chars except /), ** (any chars including /), ? (single char)
fn matchGlob(pattern: []const u8, path: []const u8) bool {
    var pi: usize = 0; // pattern index
    var si: usize = 0; // string (path) index
    var star_pi: ?usize = null; // position after last * in pattern
    var star_si: usize = 0; // position in string when we hit last *

    while (si < path.len) {
        if (pi < pattern.len) {
            // Check for **
            if (pi + 1 < pattern.len and pattern[pi] == '*' and pattern[pi + 1] == '*') {
                // ** matches any sequence including /
                pi += 2;
                // Skip trailing / after **
                if (pi < pattern.len and pattern[pi] == '/') {
                    pi += 1;
                }
                // If ** is at end, match everything
                if (pi >= pattern.len) {
                    return true;
                }
                // Try to match rest of pattern at each position
                while (si <= path.len) {
                    if (matchGlob(pattern[pi..], path[si..])) {
                        return true;
                    }
                    if (si < path.len) {
                        si += 1;
                    } else {
                        break;
                    }
                }
                return false;
            }

            // Check for single *
            if (pattern[pi] == '*') {
                star_pi = pi + 1;
                star_si = si;
                pi += 1;
                continue;
            }

            // Check for ?
            if (pattern[pi] == '?') {
                if (path[si] != '/') {
                    pi += 1;
                    si += 1;
                    continue;
                }
            }

            // Exact character match
            if (pattern[pi] == path[si]) {
                pi += 1;
                si += 1;
                continue;
            }
        }

        // No match - backtrack to last * if possible
        if (star_pi) |spi| {
            // * doesn't match /
            if (path[star_si] == '/') {
                return false;
            }
            pi = spi;
            star_si += 1;
            si = star_si;
            continue;
        }

        return false;
    }

    // Consume trailing *s in pattern
    while (pi < pattern.len and pattern[pi] == '*') {
        pi += 1;
    }

    return pi >= pattern.len;
}

/// Check if a path should be ignored based on ignore patterns
fn shouldIgnore(path: []const u8, ignore_patterns: []const []const u8) bool {
    for (ignore_patterns) |pattern| {
        if (matchGlob(pattern, path)) {
            return true;
        }
        // Also check if any path component matches (for patterns like ".git")
        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |component| {
            if (matchGlob(pattern, component)) {
                return true;
            }
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

test "glob matching - exact" {
    try std.testing.expect(matchGlob("foo.h", "foo.h"));
    try std.testing.expect(!matchGlob("foo.h", "bar.h"));
    try std.testing.expect(!matchGlob("foo.h", "foo.hpp"));
}

test "glob matching - single star" {
    try std.testing.expect(matchGlob("*.h", "foo.h"));
    try std.testing.expect(matchGlob("*.h", "bar.h"));
    try std.testing.expect(!matchGlob("*.h", "foo.hpp"));
    try std.testing.expect(matchGlob("foo.*", "foo.h"));
    try std.testing.expect(matchGlob("foo.*", "foo.cpp"));
    // * doesn't match /
    try std.testing.expect(!matchGlob("*.h", "src/foo.h"));
}

test "glob matching - double star" {
    try std.testing.expect(matchGlob("**/*.h", "foo.h"));
    try std.testing.expect(matchGlob("**/*.h", "src/foo.h"));
    try std.testing.expect(matchGlob("**/*.h", "src/sub/foo.h"));
    try std.testing.expect(matchGlob(".git/**", ".git/config"));
    try std.testing.expect(matchGlob(".git/**", ".git/objects/pack/foo"));
}

test "glob matching - question mark" {
    try std.testing.expect(matchGlob("foo?.h", "foo1.h"));
    try std.testing.expect(matchGlob("foo?.h", "foox.h"));
    try std.testing.expect(!matchGlob("foo?.h", "foo.h"));
    try std.testing.expect(!matchGlob("foo?.h", "foo12.h"));
}

test "shouldIgnore - default patterns" {
    const patterns = &[_][]const u8{ ".git/**", ".git", "node_modules/**", "build/**", "*.o" };

    // Should ignore
    try std.testing.expect(shouldIgnore(".git/config", patterns));
    try std.testing.expect(shouldIgnore(".git/objects/pack/foo", patterns));
    try std.testing.expect(shouldIgnore("node_modules/lodash/index.js", patterns));
    try std.testing.expect(shouldIgnore("build/output.txt", patterns));
    try std.testing.expect(shouldIgnore("main.o", patterns));

    // Should not ignore
    try std.testing.expect(!shouldIgnore("src/main.cpp", patterns));
    try std.testing.expect(!shouldIgnore("include/header.h", patterns));
}
