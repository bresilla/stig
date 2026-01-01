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

    /// Checks if a string starts with a command (either @ or \ prefix)
    fn startsWithCommand(text: []const u8, command: []const u8) bool {
        // Check for @command
        if (text.len >= 1 + command.len) {
            if (text[0] == '@' and std.mem.startsWith(u8, text[1..], command)) {
                return true;
            }
        }
        // Check for \command
        if (text.len >= 1 + command.len) {
            if (text[0] == '\\' and std.mem.startsWith(u8, text[1..], command)) {
                return true;
            }
        }
        return false;
    }

    /// Gets the length of the command prefix (@ or \) plus command name
    fn commandPrefixLen(command: []const u8) usize {
        return 1 + command.len; // @ or \ plus command name
    }

    /// Detects the docstring format from raw comment text
    pub fn detectFormat(self: *Self, raw: []const u8) DocFormat {
        _ = self;

        // Check for Doxygen tags (both @ and \ prefixes)
        if (std.mem.indexOf(u8, raw, "@param") != null or
            std.mem.indexOf(u8, raw, "\\param") != null or
            std.mem.indexOf(u8, raw, "@return") != null or
            std.mem.indexOf(u8, raw, "\\return") != null or
            std.mem.indexOf(u8, raw, "@brief") != null or
            std.mem.indexOf(u8, raw, "\\brief") != null)
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

            // Skip @brief or \brief tag if present, return the rest
            if (startsWithCommand(content, "brief ")) {
                return content[7..];
            }

            // Skip lines that start with @ or \ (other Doxygen tags)
            if (content.len > 0 and (content[0] == '@' or content[0] == '\\')) continue;

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

        // Tags that end the details section (without prefix - we check both @ and \)
        const end_tags = [_][]const u8{ "param", "tparam", "return", "returns", "retval", "deprecated", "note", "warning", "see", "sa", "since", "author", "version", "example", "pre", "post", "effects", "requires", "complexity", "remarks", "sync", "threadsafety", "invariant", "ensures", "ingroup", "defgroup", "exclude", "synopsis", "group", "unique_name", "module", "entity", "file", "output_section", "copydoc", "todo", "bug", "snippet" };

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

            // Check if this is a @brief or \brief tag (part of brief, not details)
            if (startsWithCommand(trimmed, "brief ")) {
                found_brief = true;
                continue;
            }

            // Check if this is an end tag (param, return, etc.) with @ or \ prefix
            var is_end_tag = false;
            for (end_tags) |tag| {
                if (startsWithCommand(trimmed, tag)) {
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
        var tparams: std.ArrayList(types.ParamDoc) = .empty;
        var retvals: std.ArrayList(types.RetvalDoc) = .empty;
        var exceptions: std.ArrayList(types.ExceptionDoc) = .empty;
        var notes: std.ArrayList([]const u8) = .empty;
        var warnings: std.ArrayList([]const u8) = .empty;
        var see_also: std.ArrayList([]const u8) = .empty;
        var examples: std.ArrayList([]const u8) = .empty;
        var preconditions: std.ArrayList([]const u8) = .empty;
        var postconditions: std.ArrayList([]const u8) = .empty;
        var remarks: std.ArrayList([]const u8) = .empty;
        var invariants: std.ArrayList([]const u8) = .empty;
        var todos: std.ArrayList(types.TodoItem) = .empty;
        var bugs: std.ArrayList(types.BugItem) = .empty;
        var snippets: std.ArrayList(types.SnippetRef) = .empty;

        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // @param or \param <name> <description>
            if (startsWithCommand(trimmed, "param ")) {
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
            // @tparam or \tparam <name> <description> (template parameter)
            else if (startsWithCommand(trimmed, "tparam ")) {
                const rest = trimmed[8..];
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |tparam_name| {
                    const desc_start = 8 + tparam_name.len + 1;
                    if (desc_start < trimmed.len) {
                        try tparams.append(self.allocator, types.ParamDoc{
                            .name = tparam_name,
                            .description = trimmed[desc_start..],
                        });
                    } else {
                        // @tparam with just name, no description
                        try tparams.append(self.allocator, types.ParamDoc{
                            .name = tparam_name,
                            .description = "",
                        });
                    }
                }
            }
            // @return / @returns / \return / \returns
            else if (startsWithCommand(trimmed, "return ") or startsWithCommand(trimmed, "returns ")) {
                const prefix_len: usize = if (startsWithCommand(trimmed, "returns ")) 9 else 8;
                doc.returns = trimmed[prefix_len..];
            }
            // @retval or \retval <value> <description>
            else if (startsWithCommand(trimmed, "retval ")) {
                const rest = trimmed[8..];
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |retval_value| {
                    const desc_start = 8 + retval_value.len + 1;
                    const description = if (desc_start < trimmed.len) trimmed[desc_start..] else "";
                    try retvals.append(self.allocator, types.RetvalDoc{
                        .value = retval_value,
                        .description = description,
                    });
                }
            }
            // @deprecated or \deprecated
            else if (startsWithCommand(trimmed, "deprecated ")) {
                doc.deprecated = trimmed[12..];
            } else if (std.mem.eql(u8, trimmed, "@deprecated") or std.mem.eql(u8, trimmed, "\\deprecated")) {
                doc.deprecated = "This is deprecated.";
            }
            // @note or \note
            else if (startsWithCommand(trimmed, "note ")) {
                try notes.append(self.allocator, trimmed[6..]);
            }
            // @warning or \warning
            else if (startsWithCommand(trimmed, "warning ")) {
                try warnings.append(self.allocator, trimmed[9..]);
            }
            // @see / @sa / \see / \sa (see also)
            else if (startsWithCommand(trimmed, "see ")) {
                try see_also.append(self.allocator, trimmed[5..]);
            } else if (startsWithCommand(trimmed, "sa ")) {
                try see_also.append(self.allocator, trimmed[4..]);
            }
            // @example or \example
            else if (startsWithCommand(trimmed, "example ")) {
                try examples.append(self.allocator, trimmed[9..]);
            }
            // @since or \since
            else if (startsWithCommand(trimmed, "since ")) {
                doc.since = trimmed[7..];
            }
            // @author or \author
            else if (startsWithCommand(trimmed, "author ")) {
                doc.author = trimmed[8..];
            }
            // @version or \version
            else if (startsWithCommand(trimmed, "version ")) {
                doc.version = trimmed[9..];
            }
            // @throw / @exception / \throw / \exception
            else if (startsWithCommand(trimmed, "throw ") or startsWithCommand(trimmed, "exception ")) {
                const prefix_len: usize = if (startsWithCommand(trimmed, "exception ")) 11 else 7;
                const rest = trimmed[prefix_len..];
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |exception_type| {
                    const desc_start = prefix_len + exception_type.len + 1;
                    const description = if (desc_start < trimmed.len) trimmed[desc_start..] else "";
                    try exceptions.append(self.allocator, types.ExceptionDoc{
                        .exception_type = exception_type,
                        .description = description,
                    });
                }
            }
            // @pre or \pre (precondition)
            else if (startsWithCommand(trimmed, "pre ")) {
                try preconditions.append(self.allocator, trimmed[5..]);
            }
            // @post or \post (postcondition)
            else if (startsWithCommand(trimmed, "post ")) {
                try postconditions.append(self.allocator, trimmed[6..]);
            }
            // @ensures (alias for @post)
            else if (startsWithCommand(trimmed, "ensures ")) {
                try postconditions.append(self.allocator, trimmed[9..]);
            }
            // @effects - C++ standard style
            else if (startsWithCommand(trimmed, "effects ")) {
                doc.effects = trimmed[9..];
            }
            // @requires - semantic preconditions (different from C++20 requires)
            else if (startsWithCommand(trimmed, "requires ")) {
                doc.requires = trimmed[10..];
            }
            // @complexity - time/space complexity
            else if (startsWithCommand(trimmed, "complexity ")) {
                doc.complexity = trimmed[12..];
            }
            // @remarks - additional remarks
            else if (startsWithCommand(trimmed, "remarks ")) {
                try remarks.append(self.allocator, trimmed[9..]);
            }
            // @sync or @threadsafety - thread safety
            else if (startsWithCommand(trimmed, "sync ")) {
                doc.sync = trimmed[6..];
            } else if (startsWithCommand(trimmed, "threadsafety ")) {
                doc.sync = trimmed[14..];
            }
            // @invariant - class invariants
            else if (startsWithCommand(trimmed, "invariant ")) {
                try invariants.append(self.allocator, trimmed[11..]);
            }
            // @ingroup - group membership
            else if (startsWithCommand(trimmed, "ingroup ")) {
                doc.ingroup = trimmed[9..];
            }
            // @exclude - exclusion from documentation
            else if (startsWithCommand(trimmed, "exclude")) {
                // Check for @exclude with argument or just @exclude
                const rest = if (trimmed[0] == '@') trimmed[8..] else trimmed[9..];
                const arg = std.mem.trim(u8, rest, " \t");
                if (arg.len == 0) {
                    doc.exclude = .full;
                } else if (std.mem.eql(u8, arg, "return") or std.mem.eql(u8, arg, "return_type")) {
                    doc.exclude = .return_type;
                } else if (std.mem.eql(u8, arg, "target")) {
                    doc.exclude = .target;
                } else {
                    // Unknown argument, treat as full exclude
                    doc.exclude = .full;
                }
            }
            // @synopsis - override the displayed synopsis
            else if (startsWithCommand(trimmed, "synopsis ")) {
                doc.synopsis_override = trimmed[10..];
            }
            // @group - group related entities together
            else if (startsWithCommand(trimmed, "group ")) {
                const content = std.mem.trim(u8, trimmed[7..], " \t");
                if (content.len > 0) {
                    // Parse: "name [Optional Heading]"
                    // First word is the group name, rest is optional heading
                    var name_end: usize = 0;
                    for (content, 0..) |c, i| {
                        if (c == ' ' or c == '\t') {
                            name_end = i;
                            break;
                        }
                    }
                    if (name_end == 0) {
                        // No space found, entire content is the name
                        doc.group = types.GroupInfo{
                            .name = content,
                            .heading = null,
                        };
                    } else {
                        // Name is before space, heading is after
                        const heading = std.mem.trim(u8, content[name_end..], " \t");
                        doc.group = types.GroupInfo{
                            .name = content[0..name_end],
                            .heading = if (heading.len > 0) heading else null,
                        };
                    }
                }
            }
            // @unique_name - override the link target name
            else if (startsWithCommand(trimmed, "unique_name ")) {
                const name = std.mem.trim(u8, trimmed[13..], " \t");
                if (name.len > 0) {
                    doc.unique_name_override = name;
                }
            }
            // @module - assign entity to a logical module
            else if (startsWithCommand(trimmed, "module ")) {
                const mod_name = std.mem.trim(u8, trimmed[8..], " \t");
                if (mod_name.len > 0) {
                    doc.module = mod_name;
                }
            }
            // @entity - remote documentation for another entity
            else if (startsWithCommand(trimmed, "entity ")) {
                const target = std.mem.trim(u8, trimmed[8..], " \t");
                if (target.len > 0) {
                    doc.entity_target = target;
                }
            }
            // @file - file-level documentation
            else if (startsWithCommand(trimmed, "file")) {
                doc.is_file_doc = true;
            }
            // @output_section - section header in synopsis
            else if (startsWithCommand(trimmed, "output_section ")) {
                const section = std.mem.trim(u8, trimmed[16..], " \t");
                if (section.len > 0) {
                    doc.output_section = section;
                }
            }
            // @copydoc - copy documentation from another entity
            else if (startsWithCommand(trimmed, "copydoc ")) {
                const target = std.mem.trim(u8, trimmed[9..], " \t");
                if (target.len > 0) {
                    doc.copydoc_target = target;
                }
            }
            // @todo or \todo - TODO item
            else if (startsWithCommand(trimmed, "todo ")) {
                const desc = std.mem.trim(u8, trimmed[6..], " \t");
                if (desc.len > 0) {
                    try todos.append(self.allocator, types.TodoItem{
                        .description = desc,
                    });
                }
            }
            // @bug or \bug - known bug
            else if (startsWithCommand(trimmed, "bug ")) {
                const desc = std.mem.trim(u8, trimmed[5..], " \t");
                if (desc.len > 0) {
                    try bugs.append(self.allocator, types.BugItem{
                        .description = desc,
                    });
                }
            }
            // @snippet or \snippet <file> <anchor> [language]
            else if (startsWithCommand(trimmed, "snippet ")) {
                const rest = std.mem.trim(u8, trimmed[9..], " \t");
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |file| {
                    const anchor = parts.next() orelse "";
                    const language = parts.next();
                    try snippets.append(self.allocator, types.SnippetRef{
                        .file = file,
                        .anchor = anchor,
                        .language = language,
                    });
                }
            }
        }

        // Convert ArrayLists to slices
        if (params.items.len > 0) {
            doc.params = try params.toOwnedSlice(self.allocator);
        }
        if (tparams.items.len > 0) {
            doc.tparams = try tparams.toOwnedSlice(self.allocator);
        }
        if (retvals.items.len > 0) {
            doc.retvals = try retvals.toOwnedSlice(self.allocator);
        }
        if (exceptions.items.len > 0) {
            doc.exceptions = try exceptions.toOwnedSlice(self.allocator);
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
        if (preconditions.items.len > 0) {
            doc.preconditions = try preconditions.toOwnedSlice(self.allocator);
        }
        if (postconditions.items.len > 0) {
            doc.postconditions = try postconditions.toOwnedSlice(self.allocator);
        }
        if (remarks.items.len > 0) {
            doc.remarks = try remarks.toOwnedSlice(self.allocator);
        }
        if (invariants.items.len > 0) {
            doc.invariants = try invariants.toOwnedSlice(self.allocator);
        }
        if (todos.items.len > 0) {
            doc.todos = try todos.toOwnedSlice(self.allocator);
        }
        if (bugs.items.len > 0) {
            doc.bugs = try bugs.toOwnedSlice(self.allocator);
        }
        if (snippets.items.len > 0) {
            doc.snippets = try snippets.toOwnedSlice(self.allocator);
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

test "parse throw tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Validates input.
        \\* @throw std::invalid_argument if input is negative
    );
    defer std.testing.allocator.free(doc.exceptions);

    try std.testing.expectEqualStrings("Validates input.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.exceptions.len);
    try std.testing.expectEqualStrings("std::invalid_argument", doc.exceptions[0].exception_type);
    try std.testing.expectEqualStrings("if input is negative", doc.exceptions[0].description);
}

test "parse exception tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Accesses element.
        \\* @exception std::out_of_range if index exceeds bounds
    );
    defer std.testing.allocator.free(doc.exceptions);

    try std.testing.expectEqualStrings("Accesses element.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.exceptions.len);
    try std.testing.expectEqualStrings("std::out_of_range", doc.exceptions[0].exception_type);
    try std.testing.expectEqualStrings("if index exceeds bounds", doc.exceptions[0].description);
}

test "parse multiple exception tags" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Processes data.
        \\* @throw std::invalid_argument if input is negative
        \\* @exception std::out_of_range if index exceeds bounds
    );
    defer std.testing.allocator.free(doc.exceptions);

    try std.testing.expectEqualStrings("Processes data.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.exceptions.len);
    try std.testing.expectEqualStrings("std::invalid_argument", doc.exceptions[0].exception_type);
    try std.testing.expectEqualStrings("std::out_of_range", doc.exceptions[1].exception_type);
}

test "parse tparam tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* A container class.
        \\* @tparam T The element type
        \\* @tparam Allocator The memory allocator
    );
    defer std.testing.allocator.free(doc.tparams);

    try std.testing.expectEqualStrings("A container class.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.tparams.len);
    try std.testing.expectEqualStrings("T", doc.tparams[0].name);
    try std.testing.expectEqualStrings("The element type", doc.tparams[0].description);
    try std.testing.expectEqualStrings("Allocator", doc.tparams[1].name);
    try std.testing.expectEqualStrings("The memory allocator", doc.tparams[1].description);
}

test "parse retval tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Opens a file.
        \\* @retval 0 Success
        \\* @retval -1 File not found
        \\* @retval -2 Permission denied
    );
    defer std.testing.allocator.free(doc.retvals);

    try std.testing.expectEqualStrings("Opens a file.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 3), doc.retvals.len);
    try std.testing.expectEqualStrings("0", doc.retvals[0].value);
    try std.testing.expectEqualStrings("Success", doc.retvals[0].description);
    try std.testing.expectEqualStrings("-1", doc.retvals[1].value);
    try std.testing.expectEqualStrings("File not found", doc.retvals[1].description);
    try std.testing.expectEqualStrings("-2", doc.retvals[2].value);
    try std.testing.expectEqualStrings("Permission denied", doc.retvals[2].description);
}

test "parse backslash command prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief Opens a file.
        \\* \param path The file path
        \\* \return File handle
        \\* \note Thread-safe
    );
    defer {
        std.testing.allocator.free(doc.params);
        std.testing.allocator.free(doc.notes);
    }

    try std.testing.expectEqualStrings("Opens a file.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.params.len);
    try std.testing.expectEqualStrings("path", doc.params[0].name);
    try std.testing.expectEqualStrings("The file path", doc.params[0].description);
    try std.testing.expectEqualStrings("File handle", doc.returns.?);
    try std.testing.expectEqual(@as(usize, 1), doc.notes.len);
    try std.testing.expectEqualStrings("Thread-safe", doc.notes[0]);
}

test "parse todo tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Sorts the array.
        \\* @todo Implement parallel sorting for large arrays
        \\* @todo Add support for custom comparators
    );
    defer std.testing.allocator.free(doc.todos);

    try std.testing.expectEqualStrings("Sorts the array.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.todos.len);
    try std.testing.expectEqualStrings("Implement parallel sorting for large arrays", doc.todos[0].description);
    try std.testing.expectEqualStrings("Add support for custom comparators", doc.todos[1].description);
}

test "parse bug tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Processes the data.
        \\* @bug Does not handle empty arrays correctly (issue #123)
        \\* @bug Memory leak when exceptions occur
    );
    defer std.testing.allocator.free(doc.bugs);

    try std.testing.expectEqualStrings("Processes the data.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.bugs.len);
    try std.testing.expectEqualStrings("Does not handle empty arrays correctly (issue #123)", doc.bugs[0].description);
    try std.testing.expectEqualStrings("Memory leak when exceptions occur", doc.bugs[1].description);
}

test "parse todo and bug with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Function description.
        \\* \todo First todo item
        \\* \bug First bug item
    );
    defer {
        std.testing.allocator.free(doc.todos);
        std.testing.allocator.free(doc.bugs);
    }

    try std.testing.expectEqual(@as(usize, 1), doc.todos.len);
    try std.testing.expectEqualStrings("First todo item", doc.todos[0].description);
    try std.testing.expectEqual(@as(usize, 1), doc.bugs.len);
    try std.testing.expectEqualStrings("First bug item", doc.bugs[0].description);
}

test "parse snippet tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Example function.
        \\* @snippet examples/test.cpp basic_example
        \\* @snippet examples/test.cpp advanced_example cpp
    );
    defer std.testing.allocator.free(doc.snippets);

    try std.testing.expectEqualStrings("Example function.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.snippets.len);
    try std.testing.expectEqualStrings("examples/test.cpp", doc.snippets[0].file);
    try std.testing.expectEqualStrings("basic_example", doc.snippets[0].anchor);
    try std.testing.expect(doc.snippets[0].language == null);
    try std.testing.expectEqualStrings("examples/test.cpp", doc.snippets[1].file);
    try std.testing.expectEqualStrings("advanced_example", doc.snippets[1].anchor);
    try std.testing.expectEqualStrings("cpp", doc.snippets[1].language.?);
}

test "parse snippet with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Example function.
        \\* \snippet examples/test.cpp my_example
    );
    defer std.testing.allocator.free(doc.snippets);

    try std.testing.expectEqual(@as(usize, 1), doc.snippets.len);
    try std.testing.expectEqualStrings("examples/test.cpp", doc.snippets[0].file);
    try std.testing.expectEqualStrings("my_example", doc.snippets[0].anchor);
}
