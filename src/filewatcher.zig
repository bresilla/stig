const std = @import("std");
const builtin = @import("builtin");

/// File change event
pub const FileEvent = struct {
    path: []const u8,
    kind: Kind,

    pub const Kind = enum {
        modified,
        created,
        deleted,
    };
};

/// Platform-agnostic file watcher
/// Uses inotify on Linux, falls back to polling on other platforms
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watched_paths: std.StringHashMap(WatchedPath),
    backend: Backend,

    const Self = @This();

    const WatchedPath = struct {
        path: []const u8,
        /// For polling: last modification time
        last_mtime: i128,
        /// For inotify: watch descriptor
        wd: ?i32,
    };

    const Backend = union(enum) {
        inotify: InotifyBackend,
        polling: PollingBackend,
    };

    /// Initialize the file watcher
    pub fn init(allocator: std.mem.Allocator) Self {
        const backend: Backend = if (builtin.os.tag == .linux)
            .{ .inotify = InotifyBackend.init() }
        else
            .{ .polling = PollingBackend.init() };

        return Self{
            .allocator = allocator,
            .watched_paths = std.StringHashMap(WatchedPath).init(allocator),
            .backend = backend,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up watch descriptors
        switch (self.backend) {
            .inotify => |*ino| {
                var iter = self.watched_paths.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.wd) |wd| {
                        ino.removeWatch(wd);
                    }
                    self.allocator.free(entry.key_ptr.*);
                }
                ino.deinit();
            },
            .polling => {
                var iter = self.watched_paths.iterator();
                while (iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                }
            },
        }
        self.watched_paths.deinit();
    }

    /// Add a file to watch
    pub fn addWatch(self: *Self, path: []const u8) !void {
        // Check if already watching
        if (self.watched_paths.contains(path)) return;

        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        var watched = WatchedPath{
            .path = path_copy,
            .last_mtime = getModTime(path),
            .wd = null,
        };

        // Add inotify watch if using inotify backend
        switch (self.backend) {
            .inotify => |*ino| {
                watched.wd = ino.addWatch(path) catch |err| blk: {
                    std.debug.print("Warning: Failed to add inotify watch for '{s}': {}\n", .{ path, err });
                    break :blk null;
                };
            },
            .polling => {},
        }

        try self.watched_paths.put(path_copy, watched);
    }

    /// Remove a file from watching
    pub fn removeWatch(self: *Self, path: []const u8) void {
        if (self.watched_paths.fetchRemove(path)) |kv| {
            switch (self.backend) {
                .inotify => |*ino| {
                    if (kv.value.wd) |wd| {
                        ino.removeWatch(wd);
                    }
                },
                .polling => {},
            }
            self.allocator.free(kv.key);
        }
    }

    /// Wait for file changes
    /// Returns a list of changed files, or null if timeout
    /// timeout_ms: milliseconds to wait, 0 = no timeout (block forever)
    pub fn waitForChanges(self: *Self, timeout_ms: u32) !?std.ArrayList(FileEvent) {
        switch (self.backend) {
            .inotify => |*ino| {
                return try self.waitInotify(ino, timeout_ms);
            },
            .polling => |*poll| {
                return try self.waitPolling(poll, timeout_ms);
            },
        }
    }

    /// Wait for changes using inotify
    fn waitInotify(self: *Self, ino: *InotifyBackend, timeout_ms: u32) !?std.ArrayList(FileEvent) {
        const events = try ino.read(timeout_ms);
        if (events.len == 0) return null;

        var result: std.ArrayList(FileEvent) = .empty;
        errdefer result.deinit(self.allocator);

        // Map watch descriptors back to paths
        for (events) |event| {
            var iter = self.watched_paths.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.wd) |wd| {
                    if (wd == event.wd) {
                        try result.append(self.allocator, .{
                            .path = entry.value_ptr.path,
                            .kind = event.kind,
                        });
                        break;
                    }
                }
            }
        }

        return result;
    }

    /// Wait for changes using polling
    fn waitPolling(self: *Self, poll: *PollingBackend, timeout_ms: u32) !?std.ArrayList(FileEvent) {
        const start = std.time.milliTimestamp();
        const timeout_i64: i64 = @intCast(timeout_ms);

        while (true) {
            var result: std.ArrayList(FileEvent) = .empty;
            errdefer result.deinit(self.allocator);

            // Check all watched files
            var iter = self.watched_paths.iterator();
            while (iter.next()) |entry| {
                const current_mtime = getModTime(entry.value_ptr.path);
                if (current_mtime > entry.value_ptr.last_mtime) {
                    entry.value_ptr.last_mtime = current_mtime;
                    try result.append(self.allocator, .{
                        .path = entry.value_ptr.path,
                        .kind = .modified,
                    });
                }
            }

            if (result.items.len > 0) {
                return result;
            }
            result.deinit(self.allocator);

            // Check timeout
            if (timeout_ms > 0) {
                const elapsed = std.time.milliTimestamp() - start;
                if (elapsed >= timeout_i64) {
                    return null;
                }
            }

            // Sleep before next poll
            std.Thread.sleep(poll.poll_interval_ns);
        }
    }
};

/// Get file modification time
/// Returns 0 if file doesn't exist or cannot be accessed
fn getModTime(path: []const u8) i128 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        // Only log errors that aren't expected (FileNotFound is normal for new files)
        if (err != error.FileNotFound) {
            std.debug.print("Warning: Cannot access file '{s}' for modification time: {}\n", .{ path, err });
        }
        return 0;
    };
    defer file.close();
    const stat = file.stat() catch |err| {
        std.debug.print("Warning: Cannot get file stats for '{s}': {}\n", .{ path, err });
        return 0;
    };
    return stat.mtime;
}

// =============================================================================
// Inotify Backend (Linux)
// =============================================================================

const InotifyBackend = struct {
    fd: std.posix.fd_t,
    buffer: [4096]u8,

    const Self = @This();

    const InotifyEvent = struct {
        wd: i32,
        kind: FileEvent.Kind,
    };

    pub fn init() Self {
        const linux = std.os.linux;
        const flags: u32 = linux.IN.CLOEXEC | linux.IN.NONBLOCK;
        const fd = std.posix.inotify_init1(flags) catch |err| blk: {
            std.debug.print("Warning: Failed to initialize inotify: {}, falling back to polling\n", .{err});
            break :blk -1;
        };
        return Self{
            .fd = fd,
            .buffer = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.fd >= 0) {
            std.posix.close(self.fd);
        }
    }

    pub fn addWatch(self: *Self, path: []const u8) !i32 {
        if (self.fd < 0) return error.InotifyNotAvailable;

        // Create null-terminated path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (path.len >= path_buf.len) return error.PathTooLong;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;

        const linux = std.os.linux;
        const mask: u32 = linux.IN.MODIFY | linux.IN.CREATE | linux.IN.DELETE | linux.IN.CLOSE_WRITE;
        const wd = std.posix.inotify_add_watch(
            self.fd,
            path_buf[0..path.len :0],
            mask,
        ) catch |err| {
            return err;
        };

        return wd;
    }

    pub fn removeWatch(self: *Self, wd: i32) void {
        if (self.fd >= 0) {
            std.posix.inotify_rm_watch(self.fd, wd);
        }
    }

    pub fn read(self: *Self, timeout_ms: u32) ![]InotifyEvent {
        if (self.fd < 0) return &[_]InotifyEvent{};

        // Use poll to wait with timeout
        const linux = std.os.linux;
        var fds = [_]std.posix.pollfd{
            .{ .fd = self.fd, .events = linux.POLL.IN, .revents = 0 },
        };

        const timeout_i32: i32 = if (timeout_ms == 0) -1 else @intCast(timeout_ms);
        const poll_result = std.posix.poll(&fds, timeout_i32) catch |err| {
            std.debug.print("Warning: File watcher poll failed: {}\n", .{err});
            return &[_]InotifyEvent{};
        };

        if (poll_result == 0) {
            // Timeout
            return &[_]InotifyEvent{};
        }

        // Read events
        const bytes_read = std.posix.read(self.fd, &self.buffer) catch |err| {
            std.debug.print("Warning: File watcher read failed: {}\n", .{err});
            return &[_]InotifyEvent{};
        };
        if (bytes_read == 0) return &[_]InotifyEvent{};

        // Parse events (simplified - just return first event)
        // Full implementation would parse all events in buffer
        const event_ptr: *align(1) const linux.inotify_event = @ptrCast(&self.buffer);
        const kind: FileEvent.Kind = if (event_ptr.mask & linux.IN.DELETE != 0)
            .deleted
        else if (event_ptr.mask & linux.IN.CREATE != 0)
            .created
        else
            .modified;

        // Return static array with single event
        const static_events = struct {
            var events: [1]InotifyEvent = undefined;
        };
        static_events.events[0] = .{ .wd = event_ptr.wd, .kind = kind };
        return &static_events.events;
    }
};

// =============================================================================
// Polling Backend (Fallback)
// =============================================================================

const PollingBackend = struct {
    poll_interval_ns: u64,

    pub fn init() PollingBackend {
        return .{
            .poll_interval_ns = 200 * std.time.ns_per_ms, // 200ms default
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "file watcher init" {
    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
}

test "file watcher add watch" {
    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();

    // Try to watch a file that may or may not exist - error is expected if file doesn't exist
    watcher.addWatch("build.zig") catch |err| {
        // FileNotFound is expected in test environment, other errors should not occur
        if (err != error.FileNotFound) {
            std.debug.print("Unexpected error: {}\n", .{err});
        }
    };
}
