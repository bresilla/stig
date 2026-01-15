const std = @import("std");

/// JSON-RPC message types
pub const MessageType = enum {
    request,
    response,
    notification,
};

/// JSON-RPC Request/Notification
pub const Message = struct {
    id: ?JsonId = null,
    method: ?[]const u8 = null,
    params: ?std.json.Value = null,

    pub fn isNotification(self: Message) bool {
        return self.id == null and self.method != null;
    }

    pub fn isRequest(self: Message) bool {
        return self.id != null and self.method != null;
    }
};

/// JSON-RPC ID can be string, number, or null
pub const JsonId = union(enum) {
    string: []const u8,
    number: i64,

    pub fn format(self: JsonId, writer: anytype) !void {
        switch (self) {
            .string => |s| {
                try writer.writeByte('"');
                try writer.writeAll(s);
                try writer.writeByte('"');
            },
            .number => |n| {
                try writer.print("{d}", .{n});
            },
        }
    }
};

/// JSON-RPC Error codes
pub const ErrorCode = enum(i32) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
    server_not_initialized = -32002,
    unknown_error_code = -32001,
    request_cancelled = -32800,
};

/// JSON-RPC Transport - handles reading/writing LSP messages over stdio
pub const Transport = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    read_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
            .read_buffer = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.read_buffer.deinit(self.allocator);
    }

    /// Reads a single LSP message from stdin
    /// Returns the parsed JSON value and the raw content
    pub fn readMessage(self: *Self) !?Message {
        // Read headers until empty line
        var content_length: ?usize = null;

        while (true) {
            const line = self.readLine() catch |err| {
                if (err == error.EndOfStream) return null;
                return err;
            };
            defer self.allocator.free(line);

            if (line.len == 0) {
                // Empty line - end of headers
                break;
            }

            // Parse Content-Length header
            if (std.mem.startsWith(u8, line, "Content-Length: ")) {
                const len_str = line["Content-Length: ".len..];
                content_length = std.fmt.parseInt(usize, len_str, 10) catch |err| {
                    std.debug.print("LSP: Invalid Content-Length '{s}': {}\n", .{ len_str, err });
                    continue;
                };
            }
        }

        const len = content_length orelse return error.MissingContentLength;

        // Validate message size to prevent DoS
        const max_message_size: usize = 100 * 1024 * 1024; // 100MB limit
        if (len > max_message_size) {
            std.debug.print("LSP: Message too large ({d} bytes, max {d})\n", .{ len, max_message_size });
            return error.MessageTooLarge;
        }

        // Read content
        self.read_buffer.clearRetainingCapacity();
        try self.read_buffer.resize(self.allocator, len);

        const bytes_read = try self.stdin.readAll(self.read_buffer.items);
        if (bytes_read != len) {
            return error.IncompleteMessage;
        }

        // Parse JSON
        return try self.parseMessage(self.read_buffer.items);
    }

    /// Parse a JSON-RPC message
    fn parseMessage(self: *Self, content: []const u8) !Message {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch |err| {
            std.debug.print("LSP: JSON parse error: {}\n", .{err});
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) {
            return error.InvalidJson;
        }

        var msg = Message{};

        // Parse id (can be string, number, or absent)
        if (root.object.get("id")) |id_val| {
            switch (id_val) {
                .string => |s| msg.id = .{ .string = try self.allocator.dupe(u8, s) },
                .integer => |n| msg.id = .{ .number = n },
                else => {},
            }
        }

        // Parse method
        if (root.object.get("method")) |method_val| {
            if (method_val == .string) {
                msg.method = try self.allocator.dupe(u8, method_val.string);
            }
        }

        // Parse params (keep as raw JSON value)
        if (root.object.get("params")) |params_val| {
            // Deep copy the params value
            msg.params = try self.deepCopyValue(params_val);
        }

        return msg;
    }

    /// Deep copy a JSON value
    fn deepCopyValue(self: *Self, value: std.json.Value) !std.json.Value {
        return switch (value) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = try self.allocator.dupe(u8, s) },
            .array => |arr| blk: {
                var new_arr = std.json.Array.initCapacity(self.allocator, arr.items.len) catch return error.OutOfMemory;
                for (arr.items) |item| {
                    new_arr.appendAssumeCapacity(try self.deepCopyValue(item));
                }
                break :blk .{ .array = new_arr };
            },
            .object => |obj| blk: {
                var new_obj = std.json.ObjectMap.init(self.allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const val = try self.deepCopyValue(entry.value_ptr.*);
                    try new_obj.put(key, val);
                }
                break :blk .{ .object = new_obj };
            },
            .number_string => |s| .{ .number_string = try self.allocator.dupe(u8, s) },
        };
    }

    /// Read a line from stdin (until \r\n)
    fn readLine(self: *Self) ![]const u8 {
        var line: std.ArrayList(u8) = .empty;
        errdefer line.deinit(self.allocator);

        while (true) {
            var byte: [1]u8 = undefined;
            const n = try self.stdin.read(&byte);
            if (n == 0) return error.EndOfStream;

            if (byte[0] == '\r') {
                // Expect \n next
                _ = try self.stdin.read(&byte);
                break;
            } else if (byte[0] == '\n') {
                break;
            } else {
                try line.append(self.allocator, byte[0]);
            }
        }

        return line.toOwnedSlice(self.allocator);
    }

    /// Send a JSON-RPC response
    pub fn sendResponse(self: *Self, id: JsonId, result: []const u8) !void {
        var response: std.ArrayList(u8) = .empty;
        defer response.deinit(self.allocator);

        try response.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":");

        // Write id
        switch (id) {
            .string => |s| {
                try response.append(self.allocator, '"');
                try response.appendSlice(self.allocator, s);
                try response.append(self.allocator, '"');
            },
            .number => |n| {
                var buf: [20]u8 = undefined;
                const num_str = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
                try response.appendSlice(self.allocator, num_str);
            },
        }

        try response.appendSlice(self.allocator, ",\"result\":");
        try response.appendSlice(self.allocator, result);
        try response.appendSlice(self.allocator, "}");

        try self.writeMessage(response.items);
    }

    /// Send a JSON-RPC error response
    pub fn sendError(self: *Self, id: ?JsonId, code: ErrorCode, message: []const u8) !void {
        var response: std.ArrayList(u8) = .empty;
        defer response.deinit(self.allocator);

        try response.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":");

        if (id) |i| {
            switch (i) {
                .string => |s| {
                    try response.append(self.allocator, '"');
                    try response.appendSlice(self.allocator, s);
                    try response.append(self.allocator, '"');
                },
                .number => |n| {
                    var buf: [20]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
                    try response.appendSlice(self.allocator, num_str);
                },
            }
        } else {
            try response.appendSlice(self.allocator, "null");
        }

        try response.appendSlice(self.allocator, ",\"error\":{\"code\":");

        var code_buf: [12]u8 = undefined;
        const code_str = std.fmt.bufPrint(&code_buf, "{d}", .{@intFromEnum(code)}) catch unreachable;
        try response.appendSlice(self.allocator, code_str);

        try response.appendSlice(self.allocator, ",\"message\":\"");
        try response.appendSlice(self.allocator, message);
        try response.appendSlice(self.allocator, "\"}}");

        try self.writeMessage(response.items);
    }

    /// Send a JSON-RPC notification
    pub fn sendNotification(self: *Self, method: []const u8, params: []const u8) !void {
        var notification: std.ArrayList(u8) = .empty;
        defer notification.deinit(self.allocator);

        try notification.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"");
        try notification.appendSlice(self.allocator, method);
        try notification.appendSlice(self.allocator, "\",\"params\":");
        try notification.appendSlice(self.allocator, params);
        try notification.appendSlice(self.allocator, "}");

        try self.writeMessage(notification.items);
    }

    /// Write a message with Content-Length header
    fn writeMessage(self: *Self, content: []const u8) !void {
        var header_buf: [50]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{content.len}) catch unreachable;

        _ = try self.stdout.write(header);
        _ = try self.stdout.write(content);
    }

    /// Free a message's allocated memory
    pub fn freeMessage(self: *Self, msg: *Message) void {
        if (msg.id) |id| {
            switch (id) {
                .string => |s| self.allocator.free(s),
                .number => {},
            }
        }
        if (msg.method) |m| {
            self.allocator.free(m);
        }
        if (msg.params) |*p| {
            freeJsonValue(self.allocator, p);
        }
    }
};

/// Free a JSON value recursively
fn freeJsonValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .string => |s| allocator.free(s),
        .array => |*arr| {
            for (arr.items) |*item| {
                freeJsonValue(allocator, item);
            }
            arr.deinit();
        },
        .object => |*obj| {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeJsonValue(allocator, entry.value_ptr);
            }
            obj.deinit();
        },
        .number_string => |s| allocator.free(s),
        else => {},
    }
}

// Tests
test "parse content length" {
    // Basic parsing test
    const header = "Content-Length: 123";
    const prefix = "Content-Length: ";
    if (std.mem.startsWith(u8, header, prefix)) {
        const len_str = header[prefix.len..];
        const len = try std.fmt.parseInt(usize, len_str, 10);
        try std.testing.expectEqual(@as(usize, 123), len);
    }
}
