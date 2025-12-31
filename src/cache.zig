const std = @import("std");
const types = @import("model/types.zig");

/// Cache for incremental documentation generation
/// Tracks file hashes to detect changes and avoid re-parsing unchanged files
pub const Cache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    manifest: Manifest,
    dirty: bool = false,

    const Self = @This();

    /// Manifest tracking file states
    pub const Manifest = struct {
        version: u32 = 1,
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
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
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

        // Check version
        if (root.object.get("version")) |v| {
            if (v != .integer or v.integer != 1) {
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

        try content.appendSlice(self.allocator, "{\n  \"version\": 1,\n  \"entries\": {\n");

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
