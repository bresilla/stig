const std = @import("std");
const types = @import("../model/types.zig");
const IncludeProcessor = @import("includes.zig").IncludeProcessor;

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
    base_path: []const u8 = "",

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    /// Sets the base path for resolving include directives
    pub fn setBasePath(self: *Self, path: []const u8) void {
        self.base_path = path;
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
    /// Note: If include directives are processed, the returned DocString.raw
    /// will be newly allocated and should be freed by the caller when done.
    pub fn parse(self: *Self, raw: []const u8) !types.DocString {
        // Process include directives first
        var include_processor = IncludeProcessor.init(self.allocator, self.base_path);
        const processed = try include_processor.process(raw);
        // Note: We do NOT free 'processed' here - it becomes owned by DocString.raw
        // The caller is responsible for freeing DocString.raw if it was allocated
        // (i.e., if processed.ptr != raw.ptr)

        const format = self.detectFormat(processed);

        return switch (format) {
            .doxygen => try self.parseDoxygen(processed),
            .markdown => try self.parseMarkdown(processed),
            else => types.DocString{ .raw = processed, .brief = self.extractBrief(processed) },
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

    /// Extracts the details section (text between brief and parameter/return tags)
    /// Handles both @brief style and plain text briefs
    fn extractDetails(self: *Self, raw: []const u8) ?[]const u8 {
        _ = self;

        var lines = std.mem.splitScalar(u8, raw, '\n');
        var found_brief = false;
        var details_start: ?usize = null;
        var details_end: usize = 0;
        var current_pos: usize = 0;

        // Tags that end the details section
        const end_tags = [_][]const u8{ "@param", "@return", "@returns", "@deprecated", "@note", "@warning", "@see", "@sa", "@since", "@author", "@version", "@example" };

        while (lines.next()) |line| {
            const line_start = current_pos;
            current_pos += line.len + 1; // +1 for newline

            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // Skip empty lines at the start or between brief and details
            if (trimmed.len == 0) {
                if (found_brief and details_start != null) {
                    // Empty line in details section - include it
                    details_end = current_pos;
                }
                continue;
            }

            // Check if this is a @brief tag (part of brief, not details)
            if (std.mem.startsWith(u8, trimmed, "@brief ")) {
                found_brief = true;
                continue;
            }

            // Check if this is an end tag (param, return, etc.)
            var is_end_tag = false;
            for (end_tags) |tag| {
                if (std.mem.startsWith(u8, trimmed, tag)) {
                    is_end_tag = true;
                    break;
                }
            }

            if (is_end_tag) {
                // Stop collecting details
                break;
            }

            if (!found_brief) {
                // This is the brief line (plain text, not @brief) - skip it
                found_brief = true;
                continue;
            }

            // This is a details line
            if (details_start == null) {
                details_start = line_start;
            }
            details_end = current_pos;
        }

        if (details_start) |start| {
            // Clamp details_end to raw.len to avoid out-of-bounds
            const safe_end = @min(details_end, raw.len);
            if (safe_end > start) {
                const details = std.mem.trim(u8, raw[start..safe_end], " \t\n\r*");
                if (details.len > 0) {
                    return details;
                }
            }
        }

        return null;
    }

    /// Parses Doxygen-style docstrings
    fn parseDoxygen(self: *Self, raw: []const u8) !types.DocString {
        var doc = types.DocString{ .raw = raw };

        // Extract brief
        doc.brief = self.extractBrief(raw);

        // Extract details (text between brief and first @ tag, excluding brief line)
        doc.details = self.extractDetails(raw);

        // Parse all Doxygen tags
        var params: std.ArrayList(types.ParamDoc) = .empty;
        var notes: std.ArrayList([]const u8) = .empty;
        var warnings: std.ArrayList([]const u8) = .empty;
        var see_also: std.ArrayList([]const u8) = .empty;
        var examples: std.ArrayList([]const u8) = .empty;

        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // @param <name> <description>
            if (std.mem.startsWith(u8, trimmed, "@param ")) {
                const rest = trimmed[7..];
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |param_name| {
                    const desc_start = 7 + param_name.len + 1;
                    if (desc_start < trimmed.len) {
                        try params.append(self.allocator, types.ParamDoc{
                            .name = param_name,
                            .description = trimmed[desc_start..],
                        });
                    }
                }
            }
            // @return / @returns
            else if (std.mem.startsWith(u8, trimmed, "@return ") or
                std.mem.startsWith(u8, trimmed, "@returns "))
            {
                const prefix_len: usize = if (std.mem.startsWith(u8, trimmed, "@returns ")) 9 else 8;
                doc.returns = trimmed[prefix_len..];
            }
            // @deprecated
            else if (std.mem.startsWith(u8, trimmed, "@deprecated ")) {
                doc.deprecated = trimmed[12..];
            } else if (std.mem.eql(u8, trimmed, "@deprecated")) {
                doc.deprecated = "This is deprecated.";
            }
            // @note
            else if (std.mem.startsWith(u8, trimmed, "@note ")) {
                try notes.append(self.allocator, trimmed[6..]);
            }
            // @warning
            else if (std.mem.startsWith(u8, trimmed, "@warning ")) {
                try warnings.append(self.allocator, trimmed[9..]);
            }
            // @see / @sa (see also)
            else if (std.mem.startsWith(u8, trimmed, "@see ")) {
                try see_also.append(self.allocator, trimmed[5..]);
            } else if (std.mem.startsWith(u8, trimmed, "@sa ")) {
                try see_also.append(self.allocator, trimmed[4..]);
            }
            // @example
            else if (std.mem.startsWith(u8, trimmed, "@example ")) {
                try examples.append(self.allocator, trimmed[9..]);
            }
            // @since
            else if (std.mem.startsWith(u8, trimmed, "@since ")) {
                doc.since = trimmed[7..];
            }
            // @author
            else if (std.mem.startsWith(u8, trimmed, "@author ")) {
                doc.author = trimmed[8..];
            }
            // @version
            else if (std.mem.startsWith(u8, trimmed, "@version ")) {
                doc.version = trimmed[9..];
            }
        }

        // Convert ArrayLists to slices
        if (params.items.len > 0) {
            doc.params = try params.toOwnedSlice(self.allocator);
        }
        if (notes.items.len > 0) {
            doc.notes = try notes.toOwnedSlice(self.allocator);
        }
        if (warnings.items.len > 0) {
            doc.warnings = try warnings.toOwnedSlice(self.allocator);
        }
        if (see_also.items.len > 0) {
            doc.see_also = try see_also.toOwnedSlice(self.allocator);
        }
        if (examples.items.len > 0) {
            doc.examples = try examples.toOwnedSlice(self.allocator);
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

test "detect doxygen format" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expectEqual(DocFormat.doxygen, extractor.detectFormat("@param x value"));
    try std.testing.expectEqual(DocFormat.doxygen, extractor.detectFormat("@return result"));
    try std.testing.expectEqual(DocFormat.doxygen, extractor.detectFormat("@brief Description"));
}

test "detect markdown format" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expectEqual(DocFormat.markdown, extractor.detectFormat("## Parameters"));
    try std.testing.expectEqual(DocFormat.markdown, extractor.detectFormat("### Returns"));
}

test "detect unknown format" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expectEqual(DocFormat.unknown, extractor.detectFormat("Just a plain comment"));
    try std.testing.expectEqual(DocFormat.unknown, extractor.detectFormat("No special markers here"));
}

test "strip block comment delimiters" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expectEqualStrings("Description", extractor.stripDelimiters("/** Description */"));
    try std.testing.expectEqualStrings("Description", extractor.stripDelimiters("/* Description */"));
}

test "strip triple-slash delimiters" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expectEqualStrings("Description", extractor.stripDelimiters("/// Description"));
    try std.testing.expectEqualStrings("Description", extractor.stripDelimiters("// Description"));
}

test "parse deprecated tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Old function.
        \\* @deprecated Use new_function() instead.
    );

    try std.testing.expectEqualStrings("Old function.", doc.brief.?);
    try std.testing.expectEqualStrings("Use new_function() instead.", doc.deprecated.?);
}

test "parse returns tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Gets the value.
        \\* @returns The current value
    );

    try std.testing.expectEqualStrings("Gets the value.", doc.brief.?);
    try std.testing.expectEqualStrings("The current value", doc.returns.?);
}

test "parse empty docstring" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse("");

    try std.testing.expect(doc.brief == null);
    try std.testing.expectEqual(@as(usize, 0), doc.params.len);
}

test "extract brief with @brief tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief This is the brief description.
        \\* More details follow.
    );

    try std.testing.expectEqualStrings("This is the brief description.", doc.brief.?);
}

test "skip doxygen tags in brief extraction" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @param x Some parameter
        \\* @return Some value
    );

    // Brief should be null since all lines are tags
    try std.testing.expect(doc.brief == null);
}

test "parse note tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Does something.
        \\* @note This is important.
        \\* @note Another note.
    );
    defer std.testing.allocator.free(doc.notes);

    try std.testing.expectEqualStrings("Does something.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.notes.len);
    try std.testing.expectEqualStrings("This is important.", doc.notes[0]);
    try std.testing.expectEqualStrings("Another note.", doc.notes[1]);
}

test "parse warning tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Dangerous function.
        \\* @warning May cause data loss.
    );
    defer std.testing.allocator.free(doc.warnings);

    try std.testing.expectEqualStrings("Dangerous function.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.warnings.len);
    try std.testing.expectEqualStrings("May cause data loss.", doc.warnings[0]);
}

test "parse see also tags" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Gets a value.
        \\* @see set_value
        \\* @sa other_function
    );
    defer std.testing.allocator.free(doc.see_also);

    try std.testing.expectEqual(@as(usize, 2), doc.see_also.len);
    try std.testing.expectEqualStrings("set_value", doc.see_also[0]);
    try std.testing.expectEqualStrings("other_function", doc.see_also[1]);
}

test "parse since tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* New feature.
        \\* @since 2.0.0
    );

    try std.testing.expectEqualStrings("New feature.", doc.brief.?);
    try std.testing.expectEqualStrings("2.0.0", doc.since.?);
}

test "parse author tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Core function.
        \\* @author John Doe
    );

    try std.testing.expectEqualStrings("Core function.", doc.brief.?);
    try std.testing.expectEqualStrings("John Doe", doc.author.?);
}

test "parse version tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Library info.
        \\* @version 1.2.3
    );

    try std.testing.expectEqualStrings("Library info.", doc.brief.?);
    try std.testing.expectEqualStrings("1.2.3", doc.version.?);
}

test "parse all doxygen tags together" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Comprehensive function.
        \\* @param x Input value
        \\* @return Computed result
        \\* @note Handle with care.
        \\* @warning May throw.
        \\* @see related_func
        \\* @since 1.0.0
        \\* @author Jane Smith
        \\* @deprecated Use new_func instead.
    );
    defer {
        std.testing.allocator.free(doc.params);
        std.testing.allocator.free(doc.notes);
        std.testing.allocator.free(doc.warnings);
        std.testing.allocator.free(doc.see_also);
    }

    try std.testing.expectEqualStrings("Comprehensive function.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.params.len);
    try std.testing.expectEqualStrings("Computed result", doc.returns.?);
    try std.testing.expectEqual(@as(usize, 1), doc.notes.len);
    try std.testing.expectEqual(@as(usize, 1), doc.warnings.len);
    try std.testing.expectEqual(@as(usize, 1), doc.see_also.len);
    try std.testing.expectEqualStrings("1.0.0", doc.since.?);
    try std.testing.expectEqualStrings("Jane Smith", doc.author.?);
    try std.testing.expectEqualStrings("Use new_func instead.", doc.deprecated.?);
}

test "extract details section" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\*
        \\* This is the details section.
        \\* It can span multiple lines.
        \\*
        \\* @param x Input value
    );
    defer std.testing.allocator.free(doc.params);

    try std.testing.expectEqualStrings("Brief description.", doc.brief.?);
    try std.testing.expect(doc.details != null);
    // Details should contain the multi-line content
    try std.testing.expect(std.mem.indexOf(u8, doc.details.?, "This is the details section") != null);
}

test "extract details with code block" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\*
        \\* Example:
        \\* ```c
        \\* int x = 42;
        \\* ```
        \\*
        \\* @param x Input value
    );
    defer std.testing.allocator.free(doc.params);

    try std.testing.expectEqualStrings("Brief description.", doc.brief.?);
    try std.testing.expect(doc.details != null);
    // Details should contain the code block
    try std.testing.expect(std.mem.indexOf(u8, doc.details.?, "```c") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.details.?, "int x = 42") != null);
}
