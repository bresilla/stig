const std = @import("std");
const types = @import("../model/types.zig");

/// Docstring format detection
pub const DocFormat = enum {
    /// Doxygen-style: /** @param x ... */
    doxygen,
    /// Triple-slash: /// Description
    triple_slash,
    /// Markdown-native: /** ## Parameters ... */
    markdown,
    /// Unknown or plain comment
    unknown,
};

/// Extracts and parses docstrings from comment text
pub const DocstringExtractor = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    /// Detects the docstring format from raw comment text
    pub fn detectFormat(self: *Self, raw: []const u8) DocFormat {
        _ = self;

        // Check for Doxygen tags
        if (std.mem.indexOf(u8, raw, "@param") != null or
            std.mem.indexOf(u8, raw, "@return") != null or
            std.mem.indexOf(u8, raw, "@brief") != null)
        {
            return .doxygen;
        }

        // Check for markdown headers
        if (std.mem.indexOf(u8, raw, "## ") != null or
            std.mem.indexOf(u8, raw, "### ") != null)
        {
            return .markdown;
        }

        // Check for triple-slash style (already stripped of ///)
        // This is typically detected at extraction time
        return .unknown;
    }

    /// Parses a raw docstring into structured form
    pub fn parse(self: *Self, raw: []const u8) !types.DocString {
        const format = self.detectFormat(raw);

        return switch (format) {
            .doxygen => try self.parseDoxygen(raw),
            .markdown => try self.parseMarkdown(raw),
            else => types.DocString{ .raw = raw, .brief = raw },
        };
    }

    /// Parses Doxygen-style docstrings
    fn parseDoxygen(self: *Self, raw: []const u8) !types.DocString {
        _ = self;

        var doc = types.DocString{ .raw = raw };

        // TODO: Implement full Doxygen parsing
        // For now, just extract brief (first line)
        if (std.mem.indexOf(u8, raw, "\n")) |newline| {
            doc.brief = raw[0..newline];
        } else {
            doc.brief = raw;
        }

        return doc;
    }

    /// Parses Markdown-native docstrings
    fn parseMarkdown(self: *Self, raw: []const u8) !types.DocString {
        _ = self;

        var doc = types.DocString{ .raw = raw };

        // TODO: Implement full Markdown parsing
        // For now, just extract brief (first line)
        if (std.mem.indexOf(u8, raw, "\n")) |newline| {
            doc.brief = raw[0..newline];
        } else {
            doc.brief = raw;
        }

        return doc;
    }

    /// Strips comment delimiters from raw comment text
    pub fn stripDelimiters(self: *Self, raw: []const u8) []const u8 {
        _ = self;

        var result = raw;

        // Strip /** and */
        if (std.mem.startsWith(u8, result, "/**")) {
            result = result[3..];
        } else if (std.mem.startsWith(u8, result, "/*")) {
            result = result[2..];
        }

        if (std.mem.endsWith(u8, result, "*/")) {
            result = result[0 .. result.len - 2];
        }

        // Trim whitespace
        result = std.mem.trim(u8, result, " \t\n\r");

        return result;
    }
};
