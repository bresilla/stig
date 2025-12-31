const std = @import("std");

/// Processes include directives in docstrings
/// Supports mdbook-compatible syntax: {{#include path/to/file.c:anchor}}
pub const IncludeProcessor = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) Self {
        return Self{
            .allocator = allocator,
            .base_path = base_path,
        };
    }

    /// Processes a docstring, replacing {{#include ...}} directives with file contents
    pub fn process(self: *Self, text: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < text.len) {
            // Look for {{#include
            if (i + 11 <= text.len and std.mem.eql(u8, text[i .. i + 11], "{{#include ")) {
                const directive_start = i;
                i += 11;

                // Find the end }}
                const directive_end = std.mem.indexOf(u8, text[i..], "}}") orelse {
                    // No closing }}, copy as-is
                    try result.appendSlice(self.allocator, text[directive_start..]);
                    break;
                };

                const path_spec = std.mem.trim(u8, text[i .. i + directive_end], " \t");
                i += directive_end + 2;

                // Process the include
                const included = self.resolveInclude(path_spec) catch |err| {
                    // On error, insert a comment
                    try result.appendSlice(self.allocator, "<!-- Include error: ");
                    try result.appendSlice(self.allocator, @errorName(err));
                    try result.appendSlice(self.allocator, " -->");
                    continue;
                };
                defer self.allocator.free(included);

                try result.appendSlice(self.allocator, included);
            } else {
                try result.append(self.allocator, text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Resolves an include directive
    /// Format: path/to/file.c or path/to/file.c:anchor
    fn resolveInclude(self: *Self, path_spec: []const u8) ![]const u8 {
        // Parse path and optional anchor
        var path: []const u8 = path_spec;
        var anchor: ?[]const u8 = null;

        if (std.mem.lastIndexOf(u8, path_spec, ":")) |colon_idx| {
            // Check if this is a Windows path (e.g., C:\...)
            if (colon_idx > 1 or (colon_idx == 1 and path_spec.len > 2 and path_spec[2] != '\\')) {
                path = path_spec[0..colon_idx];
                anchor = path_spec[colon_idx + 1 ..];
            }
        }

        // Resolve path relative to base_path
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = if (self.base_path.len > 0 and !std.fs.path.isAbsolute(path))
            try std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ self.base_path, path })
        else
            path;

        // Read the file
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Extract anchor region if specified
        if (anchor) |anc| {
            return try self.extractAnchor(content, anc);
        }

        return try self.allocator.dupe(u8, content);
    }

    /// Extracts content between ANCHOR: name and ANCHOR_END: name markers
    fn extractAnchor(self: *Self, content: []const u8, anchor_name: []const u8) ![]const u8 {
        // Build anchor markers
        var start_marker_buf: [256]u8 = undefined;
        const start_marker = try std.fmt.bufPrint(&start_marker_buf, "ANCHOR: {s}", .{anchor_name});

        var end_marker_buf: [256]u8 = undefined;
        const end_marker = try std.fmt.bufPrint(&end_marker_buf, "ANCHOR_END: {s}", .{anchor_name});

        // Find start marker
        const start_idx = std.mem.indexOf(u8, content, start_marker) orelse {
            return error.AnchorNotFound;
        };

        // Find the end of the start marker line
        const start_line_end = std.mem.indexOfPos(u8, content, start_idx, "\n") orelse content.len;
        const content_start = start_line_end + 1;

        // Find end marker
        const end_idx = std.mem.indexOfPos(u8, content, content_start, end_marker) orelse {
            return error.AnchorEndNotFound;
        };

        // Find the start of the end marker line
        var end_line_start = end_idx;
        while (end_line_start > content_start and content[end_line_start - 1] != '\n') {
            end_line_start -= 1;
        }

        // Extract content between markers
        const extracted = content[content_start..end_line_start];

        // Trim trailing newline if present
        const trimmed = std.mem.trimRight(u8, extracted, "\n\r");

        return try self.allocator.dupe(u8, trimmed);
    }
};

// Tests
test "include processor - no includes" {
    var processor = IncludeProcessor.init(std.testing.allocator, "");
    const result = try processor.process("Hello world");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Hello world", result);
}

test "include processor - extract anchor" {
    var processor = IncludeProcessor.init(std.testing.allocator, "");

    const content =
        \\// Some code
        \\// ANCHOR: example
        \\int x = 42;
        \\printf("%d\n", x);
        \\// ANCHOR_END: example
        \\// More code
    ;

    const result = try processor.extractAnchor(content, "example");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("int x = 42;\nprintf(\"%d\\n\", x);", result);
}
