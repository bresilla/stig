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
            else => types.DocString{ .raw = raw, .brief = self.extractBrief(raw) },
        };
    }

    /// Extracts the brief description (first meaningful line)
    fn extractBrief(self: *Self, raw: []const u8) ?[]const u8 {
        _ = self;

        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            // Skip empty lines and lines that are just asterisks
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, trimmed, "*")) continue;

            // Strip leading asterisk if present (from multi-line comments)
            var content = trimmed;
            if (std.mem.startsWith(u8, content, "* ")) {
                content = content[2..];
            } else if (std.mem.startsWith(u8, content, "*")) {
                content = content[1..];
                content = std.mem.trimLeft(u8, content, " ");
            }

            // Skip @brief tag if present, return the rest
            if (std.mem.startsWith(u8, content, "@brief ")) {
                return content[7..];
            }

            // Skip lines that start with @ (other Doxygen tags)
            if (content.len > 0 and content[0] == '@') continue;

            if (content.len > 0) {
                return content;
            }
        }
        return null;
    }

    /// Parses Doxygen-style docstrings
    fn parseDoxygen(self: *Self, raw: []const u8) !types.DocString {
        var doc = types.DocString{ .raw = raw };

        // Extract brief
        doc.brief = self.extractBrief(raw);

        // Parse @param tags
        var params: std.ArrayList(types.ParamDoc) = .empty;
        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");
            if (std.mem.startsWith(u8, trimmed, "@param ")) {
                const rest = trimmed[7..];
                // Find parameter name (first word)
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |param_name| {
                    // Rest is description
                    const desc_start = 7 + param_name.len + 1;
                    if (desc_start < trimmed.len) {
                        try params.append(self.allocator, types.ParamDoc{
                            .name = param_name,
                            .description = trimmed[desc_start..],
                        });
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "@return ") or
                std.mem.startsWith(u8, trimmed, "@returns "))
            {
                const prefix_len: usize = if (std.mem.startsWith(u8, trimmed, "@returns ")) 9 else 8;
                doc.returns = trimmed[prefix_len..];
            } else if (std.mem.startsWith(u8, trimmed, "@deprecated ")) {
                doc.deprecated = trimmed[12..];
            }
        }

        if (params.items.len > 0) {
            doc.params = try params.toOwnedSlice(self.allocator);
        }

        return doc;
    }

    /// Parses Markdown-native docstrings
    fn parseMarkdown(self: *Self, raw: []const u8) !types.DocString {
        var doc = types.DocString{ .raw = raw };

        // Extract brief (first non-header line)
        doc.brief = self.extractBrief(raw);

        return doc;
    }

    /// Strips comment delimiters from raw comment text
    pub fn stripDelimiters(self: *Self, raw: []const u8) []const u8 {
        _ = self;

        var result = raw;

        // Strip /** and */
        if (std.mem.startsWith(u8, result, "/**")) {
            result = result[3..];
        } else if (std.mem.startsWith(u8, result, "///")) {
            result = result[3..];
            // Also strip leading space after ///
            if (result.len > 0 and result[0] == ' ') {
                result = result[1..];
            }
        } else if (std.mem.startsWith(u8, result, "//")) {
            result = result[2..];
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

// Tests
test "extract brief from simple comment" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse("Simple description");
    try std.testing.expectEqualStrings("Simple description", doc.brief.?);
}

test "extract brief from multi-line comment" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* More details here.
    );
    try std.testing.expectEqualStrings("Brief description.", doc.brief.?);
}

test "parse doxygen params" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Adds two numbers.
        \\* @param a First number
        \\* @param b Second number
        \\* @return Sum of a and b
    );
    defer std.testing.allocator.free(doc.params);

    try std.testing.expectEqualStrings("Adds two numbers.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.params.len);
    try std.testing.expectEqualStrings("a", doc.params[0].name);
    try std.testing.expectEqualStrings("Sum of a and b", doc.returns.?);
}
