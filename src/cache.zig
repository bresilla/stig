const std = @import("std");
const types = @import("model/types.zig");
const cli = @import("cli.zig");

/// Cache for incremental documentation generation
/// Tracks file hashes to detect changes and avoid re-parsing unchanged files
pub const Cache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    manifest: Manifest,
    dirty: bool = false,
    /// Dependency graph: maps file -> list of files it includes
    /// Used to determine which files need rebuilding when a dependency changes
    dependencies: std.StringHashMap([]const []const u8),
    /// Reverse dependency graph: maps file -> list of files that include it
    /// Used to find all files affected when a file changes
    reverse_deps: std.StringHashMap(std.ArrayList([]const u8)),

    const Self = @This();

    /// Manifest tracking file states
    pub const Manifest = struct {
        version: u32 = 2, // Bumped version for dependency tracking
        entries: std.StringHashMap(FileEntry),

        pub fn init(allocator: std.mem.Allocator) Manifest {
            return .{
                .entries = std.StringHashMap(FileEntry).init(allocator),
            };
        }

        pub fn deinit(self: *Manifest) void {
            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                self.entries.allocator.free(entry.key_ptr.*);
            }
            self.entries.deinit();
        }
    };

    /// Entry for a single file in the cache
    pub const FileEntry = struct {
        /// Content hash (SHA256)
        hash: [64]u8,
        /// Last modification time (nanoseconds since epoch)
        mtime: i128,
        /// Size in bytes
        size: u64,
    };

    /// Result of checking if a file has changed
    pub const ChangeStatus = enum {
        unchanged,
        modified,
        new_file,
        deleted,
    };

    /// Initialize cache with a directory path
    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) Self {
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .manifest = Manifest.init(allocator),
            .dependencies = std.StringHashMap([]const []const u8).init(allocator),
            .reverse_deps = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        // Free dependency arrays
        var dep_iter = self.dependencies.iterator();
        while (dep_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.dependencies.deinit();

        // Free reverse dependency lists
        var rev_iter = self.reverse_deps.iterator();
        while (rev_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.reverse_deps.deinit();

        self.manifest.deinit();
    }

    /// Load manifest from disk
    pub fn load(self: *Self) !void {
        const manifest_path = try std.fs.path.join(self.allocator, &.{ self.cache_dir, "manifest.json" });
        defer self.allocator.free(manifest_path);

        const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No cache yet - start fresh
                return;
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        // Parse JSON manifest
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return;

        // Check version - accept version 1 or 2
        if (root.object.get("version")) |v| {
            if (v != .integer or (v.integer != 1 and v.integer != 2)) {
                // Incompatible version - start fresh
                return;
            }
        }

        // Load entries
        if (root.object.get("entries")) |entries_val| {
            if (entries_val != .object) return;

            var iter = entries_val.object.iterator();
            while (iter.next()) |kv| {
                const entry_obj = kv.value_ptr.*;
                if (entry_obj != .object) continue;

                var entry: FileEntry = undefined;

                // Parse hash
                if (entry_obj.object.get("hash")) |h| {
                    if (h == .string and h.string.len == 64) {
                        @memcpy(&entry.hash, h.string[0..64]);
                    } else continue;
                } else continue;

                // Parse mtime
                if (entry_obj.object.get("mtime")) |m| {
                    if (m == .integer) {
                        entry.mtime = m.integer;
                    } else continue;
                } else continue;

                // Parse size
                if (entry_obj.object.get("size")) |s| {
                    if (s == .integer) {
                        entry.size = @intCast(s.integer);
                    } else continue;
                } else continue;

                // Store entry with duplicated key
                const key = try self.allocator.dupe(u8, kv.key_ptr.*);
                try self.manifest.entries.put(key, entry);
            }
        }

        // Load dependencies (version 2+)
        if (root.object.get("dependencies")) |deps_val| {
            if (deps_val != .object) return;

            var iter = deps_val.object.iterator();
            while (iter.next()) |kv| {
                const deps_array = kv.value_ptr.*;
                if (deps_array != .array) continue;

                // Parse dependency list
                var deps = try self.allocator.alloc([]const u8, deps_array.array.items.len);
                var valid = true;
                for (deps_array.array.items, 0..) |item, i| {
                    if (item != .string) {
                        valid = false;
                        break;
                    }
                    deps[i] = try self.allocator.dupe(u8, item.string);
                }

                if (!valid) {
                    // Clean up partial allocation
                    for (deps) |d| {
                        if (d.len > 0) self.allocator.free(d);
                    }
                    self.allocator.free(deps);
                    continue;
                }

                const key = try self.allocator.dupe(u8, kv.key_ptr.*);
                try self.dependencies.put(key, deps);

                // Rebuild reverse dependency map
                for (deps) |dep| {
                    const rev_result = try self.reverse_deps.getOrPut(dep);
                    if (!rev_result.found_existing) {
                        rev_result.key_ptr.* = try self.allocator.dupe(u8, dep);
                        rev_result.value_ptr.* = .{};
                    }
                    try rev_result.value_ptr.append(self.allocator, try self.allocator.dupe(u8, kv.key_ptr.*));
                }
            }
        }
    }

    /// Save manifest to disk
    pub fn save(self: *Self) !void {
        if (!self.dirty) return;

        // Ensure cache directory exists
        std.fs.cwd().makePath(self.cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const manifest_path = try std.fs.path.join(self.allocator, &.{ self.cache_dir, "manifest.json" });
        defer self.allocator.free(manifest_path);

        const file = try std.fs.cwd().createFile(manifest_path, .{});
        defer file.close();

        // Build JSON content in memory
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "{\n  \"version\": 2,\n  \"stig_version\": \"");
        try content.appendSlice(self.allocator, cli.VERSION);
        try content.appendSlice(self.allocator, "\",\n  \"entries\": {\n");

        var first = true;
        var iter = self.manifest.entries.iterator();
        while (iter.next()) |entry| {
            if (!first) {
                try content.appendSlice(self.allocator, ",\n");
            }
            first = false;

            // Format entry
            var line_buf: [512]u8 = undefined;
            const line1 = std.fmt.bufPrint(&line_buf, "    \"{s}\": {{\n", .{entry.key_ptr.*}) catch continue;
            try content.appendSlice(self.allocator, line1);

            const line2 = std.fmt.bufPrint(&line_buf, "      \"hash\": \"{s}\",\n", .{entry.value_ptr.hash}) catch continue;
            try content.appendSlice(self.allocator, line2);

            const line3 = std.fmt.bufPrint(&line_buf, "      \"mtime\": {d},\n", .{entry.value_ptr.mtime}) catch continue;
            try content.appendSlice(self.allocator, line3);

            const line4 = std.fmt.bufPrint(&line_buf, "      \"size\": {d}\n", .{entry.value_ptr.size}) catch continue;
            try content.appendSlice(self.allocator, line4);

            try content.appendSlice(self.allocator, "    }");
        }

        try content.appendSlice(self.allocator, "\n  },\n  \"dependencies\": {\n");

        // Save dependencies
        first = true;
        var dep_iter = self.dependencies.iterator();
        while (dep_iter.next()) |entry| {
            if (!first) {
                try content.appendSlice(self.allocator, ",\n");
            }
            first = false;

            var line_buf: [1024]u8 = undefined;
            const line1 = std.fmt.bufPrint(&line_buf, "    \"{s}\": [", .{entry.key_ptr.*}) catch continue;
            try content.appendSlice(self.allocator, line1);

            var first_dep = true;
            for (entry.value_ptr.*) |dep| {
                if (!first_dep) {
                    try content.appendSlice(self.allocator, ", ");
                }
                first_dep = false;
                const dep_str = std.fmt.bufPrint(&line_buf, "\"{s}\"", .{dep}) catch continue;
                try content.appendSlice(self.allocator, dep_str);
            }
            try content.appendSlice(self.allocator, "]");
        }

        try content.appendSlice(self.allocator, "\n  }\n}\n");

        // Write to file
        try file.writeAll(content.items);

        self.dirty = false;
    }

    /// Check if a file has changed since last cache update
    pub fn checkFile(self: *Self, path: []const u8) !ChangeStatus {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            if (err == error.FileNotFound) {
                if (self.manifest.entries.contains(path)) {
                    return .deleted;
                }
                return .new_file;
            }
            return err;
        };

        if (self.manifest.entries.get(path)) |entry| {
            // Quick check: mtime and size
            if (entry.mtime == stat.mtime and entry.size == stat.size) {
                return .unchanged;
            }

            // Full check: compute hash
            const current_hash = try self.computeFileHash(path);
            if (std.mem.eql(u8, &entry.hash, &current_hash)) {
                // Content unchanged, update mtime
                var updated_entry = entry;
                updated_entry.mtime = stat.mtime;
                try self.updateEntry(path, updated_entry);
                return .unchanged;
            }

            return .modified;
        }

        return .new_file;
    }

    /// Update cache entry for a file
    pub fn updateFile(self: *Self, path: []const u8) !void {
        const stat = try std.fs.cwd().statFile(path);
        const hash = try self.computeFileHash(path);

        const entry = FileEntry{
            .hash = hash,
            .mtime = stat.mtime,
            .size = stat.size,
        };

        try self.updateEntry(path, entry);
    }

    /// Remove a file from the cache
    pub fn removeFile(self: *Self, path: []const u8) void {
        if (self.manifest.entries.fetchRemove(path)) |kv| {
            self.allocator.free(kv.key);
            self.dirty = true;
        }
    }

    /// Set the include dependencies for a file
    /// This should be called after parsing a file to record what it includes
    pub fn setDependencies(self: *Self, file_path: []const u8, includes: []const []const u8) !void {
        // Remove old dependencies from reverse map
        if (self.dependencies.get(file_path)) |old_deps| {
            for (old_deps) |dep| {
                if (self.reverse_deps.getPtr(dep)) |rev_list| {
                    // Remove file_path from the reverse dependency list
                    var i: usize = 0;
                    while (i < rev_list.items.len) {
                        if (std.mem.eql(u8, rev_list.items[i], file_path)) {
                            _ = rev_list.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }
        }

        // Store new dependencies
        const key = try self.allocator.dupe(u8, file_path);
        var deps = try self.allocator.alloc([]const u8, includes.len);
        for (includes, 0..) |inc, i| {
            deps[i] = try self.allocator.dupe(u8, inc);
        }

        // Remove old entry if exists
        if (self.dependencies.fetchRemove(file_path)) |old| {
            self.allocator.free(old.key);
            for (old.value) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(old.value);
        }

        try self.dependencies.put(key, deps);

        // Update reverse dependency map
        for (deps) |dep| {
            const rev_result = try self.reverse_deps.getOrPut(dep);
            if (!rev_result.found_existing) {
                rev_result.key_ptr.* = try self.allocator.dupe(u8, dep);
                rev_result.value_ptr.* = .{};
            }
            // Check if already in list
            var found = false;
            for (rev_result.value_ptr.items) |item| {
                if (std.mem.eql(u8, item, file_path)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try rev_result.value_ptr.append(self.allocator, try self.allocator.dupe(u8, file_path));
            }
        }

        self.dirty = true;
    }

    /// Get all files that depend on the given file (directly or transitively)
    /// Returns files that need to be rebuilt when the given file changes
    pub fn getDependents(self: *Self, file_path: []const u8) !std.ArrayList([]const u8) {
        var result: std.ArrayList([]const u8) = .empty;
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        try self.collectDependentsRecursive(file_path, &result, &visited);

        return result;
    }

    /// Recursively collect all files that depend on the given file
    fn collectDependentsRecursive(
        self: *Self,
        file_path: []const u8,
        result: *std.ArrayList([]const u8),
        visited: *std.StringHashMap(void),
    ) !void {
        if (visited.contains(file_path)) return;
        try visited.put(file_path, {});

        if (self.reverse_deps.get(file_path)) |dependents| {
            for (dependents.items) |dependent| {
                try result.append(self.allocator, dependent);
                // Recursively get files that depend on this dependent
                try self.collectDependentsRecursive(dependent, result, visited);
            }
        }
    }

    /// Check if a file or any of its dependencies have changed
    pub fn checkFileWithDeps(self: *Self, path: []const u8) !ChangeStatus {
        // First check the file itself
        const file_status = try self.checkFile(path);
        if (file_status != .unchanged) {
            return file_status;
        }

        // Check if any dependencies have changed
        if (self.dependencies.get(path)) |deps| {
            for (deps) |dep| {
                const dep_status = try self.checkFile(dep);
                if (dep_status == .modified or dep_status == .deleted) {
                    return .modified; // Dependency changed, so this file needs rebuild
                }
            }
        }

        return .unchanged;
    }

    /// Get list of files that have changed
    pub fn getChangedFiles(self: *Self, files: []const []const u8) !std.ArrayList([]const u8) {
        var changed: std.ArrayList([]const u8) = .empty;

        for (files) |file| {
            const status = try self.checkFile(file);
            if (status != .unchanged) {
                try changed.append(self.allocator, file);
            }
        }

        return changed;
    }

    /// Compute SHA256 hash of file contents
    fn computeFileHash(self: *Self, path: []const u8) ![64]u8 {
        _ = self;

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        var buf: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try file.read(&buf);
            if (bytes_read == 0) break;
            hasher.update(buf[0..bytes_read]);
        }

        const digest = hasher.finalResult();

        // Convert to hex string
        var hex: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (digest, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        return hex;
    }

    /// Compute SHA256 hash of content bytes
    pub fn computeContentHash(content: []const u8) [64]u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(content);
        const digest = hasher.finalResult();

        // Convert to hex string
        var hex: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (digest, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        return hex;
    }

    /// Update or insert an entry
    fn updateEntry(self: *Self, path: []const u8, entry: FileEntry) !void {
        const result = try self.manifest.entries.getOrPut(path);
        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, path);
        }
        result.value_ptr.* = entry;
        self.dirty = true;
    }
};

/// Incremental cache for mdbook generation
/// Stores cache in .stig-cache directory within output directory
pub const IncrementalCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    output_dir: []const u8,
    cache: Cache,
    cache_dir_owned: []const u8,
    /// Files rebuilt in the current session (used for dependency tracking)
    rebuilt_this_session: std.StringHashMap(void),

    const Self = @This();

    /// Initialize incremental cache for an output directory
    pub fn init(allocator: std.mem.Allocator, output_dir: []const u8) !Self {
        // Create cache directory path: output_dir/.stig-cache
        const cache_dir = try std.fs.path.join(allocator, &.{ output_dir, ".stig-cache" });

        return Self{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .output_dir = output_dir,
            .cache = Cache.init(allocator, cache_dir),
            .cache_dir_owned = cache_dir,
            .rebuilt_this_session = std.StringHashMap(void).init(allocator),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        // Free keys in rebuilt_this_session
        var iter = self.rebuilt_this_session.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.rebuilt_this_session.deinit();
        self.cache.deinit();
        self.allocator.free(self.cache_dir_owned);
    }

    /// Load cache manifest from disk
    pub fn load(self: *Self) !void {
        try self.cache.load();
    }

    /// Save cache manifest to disk
    pub fn save(self: *Self) !void {
        try self.cache.save();
    }

    /// Check if a file needs rebuilding
    /// Returns true if file is new, modified, or output is missing
    pub fn needsRebuild(self: *Self, file_path: []const u8, content: []const u8) !bool {
        // First check if the cached entry exists
        if (self.cache.manifest.entries.get(file_path)) |entry| {
            // Compare content hash
            const current_hash = Cache.computeContentHash(content);
            if (std.mem.eql(u8, &entry.hash, &current_hash)) {
                // Hash matches - check if output files exist
                // For now, we assume output exists if hash matches
                // In the future, we could track output files explicitly
                return false;
            }
            return true;
        }

        // New file - needs rebuild
        return true;
    }

    /// Update cache entry for a file after successful generation
    pub fn updateEntry(self: *Self, file_path: []const u8, content: []const u8) !void {
        const hash = Cache.computeContentHash(content);

        // Get file stats for mtime
        const stat = std.fs.cwd().statFile(file_path) catch |err| {
            if (err == error.FileNotFound) {
                // File was deleted - remove from cache
                self.cache.removeFile(file_path);
                return;
            }
            return err;
        };

        const entry = Cache.FileEntry{
            .hash = hash,
            .mtime = stat.mtime,
            .size = stat.size,
        };

        try self.cache.updateEntry(file_path, entry);

        // Track that this file was rebuilt in this session
        // Use absolute path for consistent matching with dependencies
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs_path = std.fs.cwd().realpath(file_path, &path_buf) catch file_path;
        const key = try self.allocator.dupe(u8, abs_path);
        try self.rebuilt_this_session.put(key, {});
    }

    /// Mark cache as dirty (needs saving)
    pub fn markDirty(self: *Self) void {
        self.cache.dirty = true;
    }

    /// Set the include dependencies for a file
    /// Resolves relative include paths to absolute paths based on the file's directory
    pub fn setDependencies(self: *Self, file_path: []const u8, includes: []const types.IncludeInfo) !void {
        // Filter to only local includes (not system includes) and resolve paths
        var resolved_paths: std.ArrayList([]const u8) = .{};
        defer {
            for (resolved_paths.items) |p| {
                self.allocator.free(p);
            }
            resolved_paths.deinit(self.allocator);
        }

        const file_dir = std.fs.path.dirname(file_path) orelse ".";

        for (includes) |inc| {
            // Skip system includes - they're not part of the project
            if (inc.is_system) continue;

            // Resolve relative path to absolute
            const resolved = std.fs.path.join(self.allocator, &.{ file_dir, inc.path }) catch continue;
            defer self.allocator.free(resolved);

            // Normalize the path
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const normalized = std.fs.cwd().realpath(resolved, &path_buf) catch {
                // File doesn't exist - skip it
                continue;
            };

            try resolved_paths.append(self.allocator, try self.allocator.dupe(u8, normalized));
        }

        // Pass to underlying cache
        try self.cache.setDependencies(file_path, resolved_paths.items);
    }

    /// Check if a file needs rebuilding, considering dependencies
    /// Returns true if file is new, modified, dependencies changed, or output is missing
    pub fn needsRebuildWithDeps(self: *Self, file_path: []const u8, content: []const u8) !bool {
        // First check if the file itself needs rebuild
        if (try self.needsRebuild(file_path, content)) {
            return true;
        }

        // Check if any dependencies have changed (from previous sessions)
        const status = try self.cache.checkFileWithDeps(file_path);
        if (status != .unchanged) {
            return true;
        }

        // Check if any dependencies were rebuilt in this session
        // This handles the case where a dependency was processed earlier in this run
        if (self.cache.dependencies.get(file_path)) |deps| {
            for (deps) |dep| {
                if (self.rebuilt_this_session.contains(dep)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Get all files that depend on the given file (directly or transitively)
    /// Useful for determining what needs rebuilding when a file changes
    pub fn getDependents(self: *Self, file_path: []const u8) !std.ArrayList([]const u8) {
        return self.cache.getDependents(file_path);
    }

    /// Pre-scan files to determine which need rebuilding, considering dependencies
    /// Returns a set of file paths that need to be rebuilt
    /// This should be called before processing files to handle dependency chains correctly
    pub fn getFilesToRebuild(self: *Self, files: []const []const u8, file_contents: []const []const u8) !std.StringHashMap(void) {
        var needs_rebuild = std.StringHashMap(void).init(self.allocator);

        // First pass: identify directly changed files
        for (files, file_contents) |file_path, content| {
            const needs = self.needsRebuild(file_path, content) catch true;
            if (needs) {
                try needs_rebuild.put(file_path, {});
            }
        }

        // Second pass: add dependents of changed files (iterate until no new files added)
        var added_new = true;
        while (added_new) {
            added_new = false;

            // Collect current set of files to rebuild
            var current_files: std.ArrayList([]const u8) = .{};
            defer current_files.deinit(self.allocator);

            var iter = needs_rebuild.iterator();
            while (iter.next()) |entry| {
                try current_files.append(self.allocator, entry.key_ptr.*);
            }

            for (current_files.items) |changed_file| {
                // Get absolute path for dependency lookup
                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const abs_path = std.fs.cwd().realpath(changed_file, &path_buf) catch continue;

                var dependents = self.cache.getDependents(abs_path) catch continue;
                defer dependents.deinit(self.allocator);

                for (dependents.items) |dependent| {
                    // The dependent is stored as a relative path (from setDependencies)
                    // Check if it's in our input files and not already marked for rebuild
                    for (files) |file_path| {
                        if (std.mem.eql(u8, file_path, dependent)) {
                            if (!needs_rebuild.contains(file_path)) {
                                try needs_rebuild.put(file_path, {});
                                added_new = true;
                            }
                            break;
                        }
                    }
                }
            }
        }

        return needs_rebuild;
    }
};

// Tests
test "cache - init and deinit" {
    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();
}

test "cache - compute file hash" {
    // Create a temp file
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("Hello, World!");
    file.close();

    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();

    // Get the full path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    const hash = try cache.computeFileHash(path);

    // SHA256 of "Hello, World!" should be consistent
    try std.testing.expect(hash.len == 64);
}

test "cache - check new file" {
    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();

    const status = try cache.checkFile("/nonexistent/file.h");
    try std.testing.expectEqual(Cache.ChangeStatus.new_file, status);
}

test "cache - compute content hash" {
    const hash1 = Cache.computeContentHash("Hello, World!");
    const hash2 = Cache.computeContentHash("Hello, World!");
    const hash3 = Cache.computeContentHash("Different content");

    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash3));
}

test "incremental cache - init and deinit" {
    var incr_cache = try IncrementalCache.init(std.testing.allocator, "/tmp/test_docs");
    defer incr_cache.deinit();

    try std.testing.expectEqualStrings("/tmp/test_docs/.stig-cache", incr_cache.cache_dir);
}

test "incremental cache - needs rebuild for new file" {
    var incr_cache = try IncrementalCache.init(std.testing.allocator, "/tmp/test_docs");
    defer incr_cache.deinit();

    const needs = try incr_cache.needsRebuild("new_file.h", "content");
    try std.testing.expect(needs);
}

test "cache - set and get dependencies" {
    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();

    // Set dependencies: a.hpp depends on b.hpp and c.hpp
    const deps = &[_][]const u8{ "b.hpp", "c.hpp" };
    try cache.setDependencies("a.hpp", deps);

    // Verify dependencies were stored
    const stored_deps = cache.dependencies.get("a.hpp");
    try std.testing.expect(stored_deps != null);
    try std.testing.expectEqual(@as(usize, 2), stored_deps.?.len);

    // Verify reverse dependencies
    const b_dependents = cache.reverse_deps.get("b.hpp");
    try std.testing.expect(b_dependents != null);
    try std.testing.expectEqual(@as(usize, 1), b_dependents.?.items.len);
    try std.testing.expectEqualStrings("a.hpp", b_dependents.?.items[0]);
}

test "cache - get dependents transitively" {
    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();

    // Set up dependency chain: a.hpp -> b.hpp -> c.hpp
    // (a includes b, b includes c)
    try cache.setDependencies("a.hpp", &[_][]const u8{"b.hpp"});
    try cache.setDependencies("b.hpp", &[_][]const u8{"c.hpp"});

    // Get all files that depend on c.hpp (should be b.hpp and a.hpp)
    var dependents = try cache.getDependents("c.hpp");
    defer dependents.deinit(std.testing.allocator);

    // Should have 2 dependents: b.hpp (directly) and a.hpp (transitively)
    try std.testing.expectEqual(@as(usize, 2), dependents.items.len);
}

test "cache - update dependencies replaces old ones" {
    var cache = Cache.init(std.testing.allocator, ".stig-cache");
    defer cache.deinit();

    // Initial dependencies
    try cache.setDependencies("a.hpp", &[_][]const u8{ "b.hpp", "c.hpp" });

    // Update with new dependencies
    try cache.setDependencies("a.hpp", &[_][]const u8{"d.hpp"});

    // Verify old dependencies are gone
    const stored_deps = cache.dependencies.get("a.hpp");
    try std.testing.expect(stored_deps != null);
    try std.testing.expectEqual(@as(usize, 1), stored_deps.?.len);
    try std.testing.expectEqualStrings("d.hpp", stored_deps.?[0]);

    // Verify old reverse deps are cleaned up
    const b_dependents = cache.reverse_deps.get("b.hpp");
    if (b_dependents) |deps| {
        try std.testing.expectEqual(@as(usize, 0), deps.items.len);
    }
}
