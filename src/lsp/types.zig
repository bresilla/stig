const std = @import("std");

/// LSP Position - 0-based line and character
pub const Position = struct {
    line: u32,
    character: u32,

    pub fn jsonStringify(self: Position, writer: anytype) !void {
        try writer.print("{{\"line\":{d},\"character\":{d}}}", .{ self.line, self.character });
    }
};

/// LSP Range - start and end positions
pub const Range = struct {
    start: Position,
    end: Position,

    pub fn jsonStringify(self: Range, writer: anytype) !void {
        try writer.writeAll("{\"start\":");
        try self.start.jsonStringify(writer);
        try writer.writeAll(",\"end\":");
        try self.end.jsonStringify(writer);
        try writer.writeByte('}');
    }
};

/// LSP Diagnostic Severity
pub const DiagnosticSeverity = enum(u8) {
    @"error" = 1,
    warning = 2,
    information = 3,
    hint = 4,

    pub fn toInt(self: DiagnosticSeverity) u8 {
        return @intFromEnum(self);
    }
};

/// LSP Diagnostic
pub const Diagnostic = struct {
    range: Range,
    severity: ?DiagnosticSeverity = null,
    code: ?[]const u8 = null,
    source: ?[]const u8 = null,
    message: []const u8,

    pub fn jsonStringify(self: Diagnostic, writer: anytype) !void {
        try writer.writeAll("{\"range\":");
        try self.range.jsonStringify(writer);

        if (self.severity) |sev| {
            try writer.print(",\"severity\":{d}", .{sev.toInt()});
        }

        if (self.code) |code| {
            try writer.writeAll(",\"code\":\"");
            try writer.writeAll(code);
            try writer.writeByte('"');
        }

        if (self.source) |source| {
            try writer.writeAll(",\"source\":\"");
            try writer.writeAll(source);
            try writer.writeByte('"');
        }

        try writer.writeAll(",\"message\":\"");
        try writeJsonEscaped(writer, self.message);
        try writer.writeAll("\"}");
    }
};

/// LSP Text Document Identifier
pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

/// LSP Versioned Text Document Identifier
pub const VersionedTextDocumentIdentifier = struct {
    uri: []const u8,
    version: i64,
};

/// LSP Text Document Item (for didOpen)
pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i64,
    text: []const u8,
};

/// LSP Text Document Content Change Event
pub const TextDocumentContentChangeEvent = struct {
    text: []const u8,
};

/// LSP PublishDiagnosticsParams
pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    diagnostics: []const Diagnostic,

    pub fn jsonStringify(self: PublishDiagnosticsParams, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        errdefer buffer.deinit(allocator);

        try buffer.appendSlice(allocator, "{\"uri\":\"");
        try writeJsonEscapedToList(&buffer, allocator, self.uri);
        try buffer.appendSlice(allocator, "\",\"diagnostics\":[");

        for (self.diagnostics, 0..) |diag, i| {
            if (i > 0) try buffer.append(allocator, ',');
            try diag.jsonStringify(buffer.writer(allocator));
        }

        try buffer.appendSlice(allocator, "]}");
        return buffer.toOwnedSlice(allocator);
    }
};

/// LSP Server Capabilities
pub const ServerCapabilities = struct {
    textDocumentSync: TextDocumentSyncOptions,

    pub fn jsonStringify(self: ServerCapabilities, writer: anytype) !void {
        try writer.writeAll("{\"textDocumentSync\":");
        try self.textDocumentSync.jsonStringify(writer);
        try writer.writeAll("}");
    }
};

/// LSP Text Document Sync Options
pub const TextDocumentSyncOptions = struct {
    openClose: bool = true,
    change: TextDocumentSyncKind = .full,
    save: ?SaveOptions = null,

    pub fn jsonStringify(self: TextDocumentSyncOptions, writer: anytype) !void {
        try writer.writeAll("{\"openClose\":");
        try writer.writeAll(if (self.openClose) "true" else "false");
        try writer.print(",\"change\":{d}", .{@intFromEnum(self.change)});
        if (self.save) |save| {
            try writer.writeAll(",\"save\":");
            try save.jsonStringify(writer);
        }
        try writer.writeByte('}');
    }
};

/// LSP Text Document Sync Kind
pub const TextDocumentSyncKind = enum(u8) {
    none = 0,
    full = 1,
    incremental = 2,
};

/// LSP Save Options
pub const SaveOptions = struct {
    includeText: bool = false,

    pub fn jsonStringify(self: SaveOptions, writer: anytype) !void {
        try writer.writeAll("{\"includeText\":");
        try writer.writeAll(if (self.includeText) "true" else "false");
        try writer.writeAll("}");
    }
};

/// LSP Initialize Result
pub const InitializeResult = struct {
    capabilities: ServerCapabilities,

    pub fn jsonStringify(self: InitializeResult, writer: anytype) !void {
        try writer.writeAll("{\"capabilities\":");
        try self.capabilities.jsonStringify(writer);
        try writer.writeAll("}");
    }
};

/// Helper to write JSON-escaped string
fn writeJsonEscaped(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Helper to write JSON-escaped string to ArrayList
fn writeJsonEscapedToList(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try buffer.appendSlice(allocator, "\\\""),
            '\\' => try buffer.appendSlice(allocator, "\\\\"),
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const len = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                    try buffer.appendSlice(allocator, len);
                } else {
                    try buffer.append(allocator, c);
                }
            },
        }
    }
}

/// Convert file path to URI
pub fn pathToUri(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // Handle absolute vs relative paths
    if (std.fs.path.isAbsolute(path)) {
        return std.fmt.allocPrint(allocator, "file://{s}", .{path});
    } else {
        // Get absolute path
        const cwd = std.fs.cwd();
        const abs_path = try cwd.realpathAlloc(allocator, path);
        defer allocator.free(abs_path);
        return std.fmt.allocPrint(allocator, "file://{s}", .{abs_path});
    }
}

/// Convert URI to file path
pub fn uriToPath(allocator: std.mem.Allocator, uri: []const u8) ![]const u8 {
    const prefix = "file://";
    if (std.mem.startsWith(u8, uri, prefix)) {
        return try allocator.dupe(u8, uri[prefix.len..]);
    }
    return try allocator.dupe(u8, uri);
}

// Tests
test "position json" {
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const pos = Position{ .line = 10, .character = 5 };
    try pos.jsonStringify(writer);

    try std.testing.expectEqualStrings("{\"line\":10,\"character\":5}", fbs.getWritten());
}

test "diagnostic json" {
    var buffer: [500]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const diag = Diagnostic{
        .range = .{
            .start = .{ .line = 10, .character = 0 },
            .end = .{ .line = 10, .character = 20 },
        },
        .severity = .warning,
        .code = "W001",
        .source = "stig",
        .message = "no documentation",
    };
    try diag.jsonStringify(writer);

    const expected = "{\"range\":{\"start\":{\"line\":10,\"character\":0},\"end\":{\"line\":10,\"character\":20}},\"severity\":2,\"code\":\"W001\",\"source\":\"stig\",\"message\":\"no documentation\"}";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}
