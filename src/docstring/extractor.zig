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
        const end_tags = [_][]const u8{ "param", "tparam", "return", "returns", "retval", "deprecated", "note", "warning", "see", "sa", "since", "author", "version", "example", "pre", "post", "effects", "requires", "complexity", "remarks", "sync", "threadsafety", "invariant", "ensures", "ingroup", "defgroup", "exclude", "synopsis", "group", "unique_name", "module", "entity", "file", "output_section", "copydoc", "todo", "bug", "test", "snippet", "attention", "important", "date", "copyright", "mermaid", "code", "endcode" };

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

    // Placeholder characters for escaped sequences
    // Using Unicode private use area characters that won't appear in normal text
    const ESCAPED_AT: u8 = 0x01; // Placeholder for @@
    const ESCAPED_BACKSLASH: u8 = 0x02; // Placeholder for \\

    /// Processes escaped characters in docstring text
    /// Replaces @@ with placeholder and \\ with placeholder
    /// These are restored after parsing by restoreEscapedChars
    fn processEscapedChars(self: *Self, raw: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        var i: usize = 0;

        while (i < raw.len) {
            if (i + 1 < raw.len) {
                // Check for @@ (escaped @)
                if (raw[i] == '@' and raw[i + 1] == '@') {
                    try result.append(self.allocator, ESCAPED_AT);
                    i += 2;
                    continue;
                }
                // Check for \\ (escaped \)
                if (raw[i] == '\\' and raw[i + 1] == '\\') {
                    try result.append(self.allocator, ESCAPED_BACKSLASH);
                    i += 2;
                    continue;
                }
            }
            try result.append(self.allocator, raw[i]);
            i += 1;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Restores escaped characters from placeholders to their literal values
    /// Called after parsing to convert placeholders back to @ and \
    fn restoreEscapedChars(self: *Self, text: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;

        for (text) |c| {
            if (c == ESCAPED_AT) {
                try result.append(self.allocator, '@');
            } else if (c == ESCAPED_BACKSLASH) {
                try result.append(self.allocator, '\\');
            } else {
                try result.append(self.allocator, c);
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Checks if text contains any escaped character placeholders
    fn hasEscapedPlaceholders(text: []const u8) bool {
        for (text) |c| {
            if (c == ESCAPED_AT or c == ESCAPED_BACKSLASH) {
                return true;
            }
        }
        return false;
    }

    /// Joins continuation lines in docstring text
    /// A continuation line is one that:
    /// 1. Doesn't start with @ or \ (not a new tag)
    /// 2. Follows a line that started with a tag
    /// 3. Is not empty
    /// Continuation lines are joined to the previous tag line with a space
    fn joinContinuationLines(self: *Self, raw: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        var in_tag = false;
        var in_block = false; // Track if we're in @code/@mermaid block

        var lines = std.mem.splitScalar(u8, raw, '\n');
        var first_line = true;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // Track block state
            if (startsWithCommand(trimmed, "code") or startsWithCommand(trimmed, "mermaid")) {
                in_block = true;
            } else if (startsWithCommand(trimmed, "endcode") or startsWithCommand(trimmed, "endmermaid")) {
                in_block = false;
            }

            // Don't join lines inside code/mermaid blocks
            if (in_block) {
                if (!first_line) {
                    try result.append(self.allocator, '\n');
                }
                try result.appendSlice(self.allocator, line);
                first_line = false;
                continue;
            }

            // Check if this line starts with a tag
            const is_tag_line = trimmed.len > 0 and (trimmed[0] == '@' or trimmed[0] == '\\');

            if (is_tag_line) {
                // New tag - start fresh
                if (!first_line) {
                    try result.append(self.allocator, '\n');
                }
                try result.appendSlice(self.allocator, line);
                in_tag = true;
            } else if (in_tag and trimmed.len > 0) {
                // Continuation line - join with space instead of newline
                try result.append(self.allocator, ' ');
                try result.appendSlice(self.allocator, trimmed);
            } else {
                // Empty line or non-continuation - preserve as-is
                if (!first_line) {
                    try result.append(self.allocator, '\n');
                }
                try result.appendSlice(self.allocator, line);
                // Empty line ends continuation
                if (trimmed.len == 0) {
                    in_tag = false;
                }
            }

            first_line = false;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Parses Doxygen-style docstrings
    fn parseDoxygen(self: *Self, raw: []const u8) !types.DocString {
        var doc = types.DocString{ .raw = raw };

        // Pre-process: First handle escaped characters (@@ and \\)
        const escaped_processed = try self.processEscapedChars(raw);

        // Pre-process raw text to join continuation lines
        // A continuation line is one that doesn't start with @ or \ and follows a tag line
        // Note: We don't free processed_raw because parsed content references slices from it
        const processed_raw = try self.joinContinuationLines(escaped_processed);
        // Store the processed raw in the doc so it stays alive
        doc.raw = processed_raw;

        // Extract brief and details from processed text (after escape handling)
        doc.brief = self.extractBrief(processed_raw);
        doc.details = self.extractDetails(processed_raw);

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
        var tests: std.ArrayList(types.TestRef) = .empty;
        var snippets: std.ArrayList(types.SnippetRef) = .empty;
        var attention: std.ArrayList([]const u8) = .empty;
        var important: std.ArrayList([]const u8) = .empty;
        var dates: std.ArrayList(types.DateInfo) = .empty;
        var mermaid_diagrams: std.ArrayList(types.MermaidDiagram) = .empty;
        var refs: std.ArrayList(types.RefLink) = .empty;

        // State for multi-line @mermaid/@endmermaid blocks
        var in_mermaid_block = false;
        var mermaid_content: std.ArrayList(u8) = .empty;
        var mermaid_caption: ?[]const u8 = null;

        // State for multi-line @code/@endcode blocks
        var code_blocks: std.ArrayList(types.CodeBlock) = .empty;
        var in_code_block = false;
        var code_content: std.ArrayList(u8) = .empty;
        var code_language: ?[]const u8 = null;
        var code_lineno: bool = false;

        var lines = std.mem.splitScalar(u8, processed_raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // Handle @mermaid or \mermaid [optional caption]
            if (startsWithCommand(trimmed, "mermaid")) {
                in_mermaid_block = true;
                mermaid_content = .empty;
                // Check for caption after @mermaid (e.g., "@mermaid State Diagram")
                const prefix_len: usize = if (trimmed[0] == '@') 8 else 9;
                if (prefix_len <= trimmed.len) {
                    const caption_text = std.mem.trim(u8, trimmed[prefix_len..], " \t");
                    mermaid_caption = if (caption_text.len > 0) caption_text else null;
                } else {
                    mermaid_caption = null;
                }
                continue;
            }

            // Handle @endmermaid or \endmermaid
            if (startsWithCommand(trimmed, "endmermaid")) {
                if (in_mermaid_block) {
                    const content = try mermaid_content.toOwnedSlice(self.allocator);
                    try mermaid_diagrams.append(self.allocator, types.MermaidDiagram{
                        .content = content,
                        .caption = mermaid_caption,
                    });
                    in_mermaid_block = false;
                    mermaid_caption = null;
                }
                continue;
            }

            // If inside mermaid block, collect content
            if (in_mermaid_block) {
                if (mermaid_content.items.len > 0) {
                    try mermaid_content.append(self.allocator, '\n');
                }
                try mermaid_content.appendSlice(self.allocator, trimmed);
                continue;
            }

            // Handle @code or \code with optional {.lang} or {.lang,lineno}
            if (startsWithCommand(trimmed, "code")) {
                // Make sure it's not @copydoc or similar
                // Both @code and \code are 5 characters (prefix + "code")
                const after_code = trimmed[5..];
                // It must be end-of-string, or followed by { or whitespace
                if (after_code.len == 0 or after_code[0] == '{' or after_code[0] == ' ' or after_code[0] == '\t') {
                    in_code_block = true;
                    code_content = .empty;
                    code_language = null;
                    code_lineno = false;

                    // Parse options: @code{.cpp} or @code{.cpp,lineno}
                    if (after_code.len > 0 and after_code[0] == '{') {
                        // Find closing brace
                        if (std.mem.indexOf(u8, after_code, "}")) |end| {
                            const options = after_code[1..end];
                            // Parse options
                            var opts = std.mem.splitScalar(u8, options, ',');
                            while (opts.next()) |opt| {
                                const trimmed_opt = std.mem.trim(u8, opt, " \t");
                                if (std.mem.startsWith(u8, trimmed_opt, ".")) {
                                    code_language = trimmed_opt[1..];
                                } else if (std.mem.eql(u8, trimmed_opt, "lineno") or std.mem.eql(u8, trimmed_opt, "linenos")) {
                                    code_lineno = true;
                                }
                            }
                        }
                    }
                    continue;
                }
            }

            // Handle @endcode or \endcode
            if (startsWithCommand(trimmed, "endcode")) {
                if (in_code_block) {
                    const content = try code_content.toOwnedSlice(self.allocator);
                    try code_blocks.append(self.allocator, types.CodeBlock{
                        .content = content,
                        .language = code_language,
                        .show_line_numbers = code_lineno,
                    });
                    in_code_block = false;
                    code_language = null;
                    code_lineno = false;
                }
                continue;
            }

            // If inside code block, collect content
            if (in_code_block) {
                if (code_content.items.len > 0) {
                    try code_content.append(self.allocator, '\n');
                }
                try code_content.appendSlice(self.allocator, trimmed);
                continue;
            }

            // @param or \param <name> <description>
            if (startsWithCommand(trimmed, "param ")) {
                const rest = trimmed[7..];
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |param_name| {
                    if (param_name.len > 0) {
                        const desc_start = 7 + param_name.len + 1;
                        const description = if (desc_start < trimmed.len)
                            trimmed[desc_start..]
                        else
                            ""; // Empty description
                        try params.append(self.allocator, types.ParamDoc{
                            .name = param_name,
                            .description = description,
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
            // @return / @returns / \return / \returns (with or without description)
            else if (startsWithCommand(trimmed, "return ") or startsWithCommand(trimmed, "returns ")) {
                const prefix_len: usize = if (startsWithCommand(trimmed, "returns ")) 9 else 8;
                doc.returns = trimmed[prefix_len..];
            } else if (std.mem.eql(u8, trimmed, "@return") or std.mem.eql(u8, trimmed, "\\return") or
                std.mem.eql(u8, trimmed, "@returns") or std.mem.eql(u8, trimmed, "\\returns"))
            {
                // @return with no description
                doc.returns = "";
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
            // @test or \test - test reference: @test test_name [file_path]
            else if (startsWithCommand(trimmed, "test ")) {
                const rest = std.mem.trim(u8, trimmed[6..], " \t");
                if (rest.len > 0) {
                    // Split into test name and optional file path
                    var parts = std.mem.splitScalar(u8, rest, ' ');
                    if (parts.next()) |test_name| {
                        const file_path = parts.next();
                        try tests.append(self.allocator, types.TestRef{
                            .name = test_name,
                            .file = file_path,
                        });
                    }
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
            // @attention or \attention
            else if (startsWithCommand(trimmed, "attention ")) {
                try attention.append(self.allocator, trimmed[11..]);
            }
            // @important or \important
            else if (startsWithCommand(trimmed, "important ")) {
                try important.append(self.allocator, trimmed[11..]);
            }
            // @date or \date - format: @date 2024-01-15 [description]
            else if (startsWithCommand(trimmed, "date ")) {
                const rest = trimmed[6..];
                // Split into date and optional description
                // Date is first word, rest is description
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |date_str| {
                    const desc_start = 6 + date_str.len + 1;
                    const description = if (desc_start < trimmed.len)
                        std.mem.trim(u8, trimmed[desc_start..], " \t()")
                    else
                        null;
                    try dates.append(self.allocator, types.DateInfo{
                        .date = date_str,
                        .description = if (description != null and description.?.len > 0) description else null,
                    });
                }
            }
            // @copyright or \copyright
            else if (startsWithCommand(trimmed, "copyright ")) {
                doc.copyright = trimmed[11..];
            }
            // @ref or \ref - cross-reference: @ref target or @ref target "display text"
            else if (startsWithCommand(trimmed, "ref ")) {
                const rest = std.mem.trim(u8, trimmed[5..], " \t");
                if (rest.len > 0) {
                    // Parse: @ref target or @ref target "display text"
                    // Check for quoted display text
                    if (std.mem.indexOf(u8, rest, "\"")) |quote_start| {
                        // Find closing quote
                        if (std.mem.indexOfPos(u8, rest, quote_start + 1, "\"")) |quote_end| {
                            const target = std.mem.trim(u8, rest[0..quote_start], " \t");
                            const display_text = rest[quote_start + 1 .. quote_end];
                            try refs.append(self.allocator, types.RefLink{
                                .target = target,
                                .display_text = display_text,
                            });
                        } else {
                            // Unclosed quote, treat entire rest as target
                            try refs.append(self.allocator, types.RefLink{
                                .target = rest,
                            });
                        }
                    } else {
                        // No display text, just target
                        try refs.append(self.allocator, types.RefLink{
                            .target = rest,
                        });
                    }
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
        if (tests.items.len > 0) {
            doc.tests = try tests.toOwnedSlice(self.allocator);
        }
        if (snippets.items.len > 0) {
            doc.snippets = try snippets.toOwnedSlice(self.allocator);
        }
        if (attention.items.len > 0) {
            doc.attention = try attention.toOwnedSlice(self.allocator);
        }
        if (important.items.len > 0) {
            doc.important = try important.toOwnedSlice(self.allocator);
        }
        if (dates.items.len > 0) {
            doc.dates = try dates.toOwnedSlice(self.allocator);
        }
        if (mermaid_diagrams.items.len > 0) {
            doc.mermaid_diagrams = try mermaid_diagrams.toOwnedSlice(self.allocator);
        }
        if (code_blocks.items.len > 0) {
            doc.code_blocks = try code_blocks.toOwnedSlice(self.allocator);
        }

        // Extract inline @ref tags from all text fields
        // Helper to extract refs from a single text field
        const extractRefsFromText = struct {
            fn call(extractor: *Self, text: []const u8, ref_list: *std.ArrayList(types.RefLink)) !void {
                if (containsRef(text)) {
                    const inline_refs = try extractor.extractInlineRefs(text);
                    for (inline_refs) |ref| {
                        try ref_list.append(extractor.allocator, ref);
                    }
                    extractor.allocator.free(inline_refs);
                }
            }
        }.call;

        // Extract from brief and details
        if (doc.brief) |brief| {
            try extractRefsFromText(self, brief, &refs);
        }
        if (doc.details) |details| {
            try extractRefsFromText(self, details, &refs);
        }

        // Extract from notes
        for (doc.notes) |note| {
            try extractRefsFromText(self, note, &refs);
        }

        // Extract from warnings
        for (doc.warnings) |warning| {
            try extractRefsFromText(self, warning, &refs);
        }

        // Extract from param descriptions
        for (doc.params) |param| {
            try extractRefsFromText(self, param.description, &refs);
        }

        // Extract from return description
        if (doc.returns) |returns| {
            try extractRefsFromText(self, returns, &refs);
        }

        // Extract from preconditions
        for (doc.preconditions) |pre| {
            try extractRefsFromText(self, pre, &refs);
        }

        // Extract from postconditions
        for (doc.postconditions) |post| {
            try extractRefsFromText(self, post, &refs);
        }

        // Extract from remarks
        for (doc.remarks) |remark| {
            try extractRefsFromText(self, remark, &refs);
        }

        // Extract from see_also
        for (doc.see_also) |see| {
            try extractRefsFromText(self, see, &refs);
        }

        // Extract from attention
        for (doc.attention) |att| {
            try extractRefsFromText(self, att, &refs);
        }

        // Extract from important
        for (doc.important) |imp| {
            try extractRefsFromText(self, imp, &refs);
        }

        // Extract from deprecated
        if (doc.deprecated) |deprecated| {
            try extractRefsFromText(self, deprecated, &refs);
        }

        // Extract from tparam descriptions
        for (doc.tparams) |tparam| {
            try extractRefsFromText(self, tparam.description, &refs);
        }

        // Extract from exception descriptions
        for (doc.exceptions) |exc| {
            try extractRefsFromText(self, exc.description, &refs);
        }

        if (refs.items.len > 0) {
            doc.refs = try refs.toOwnedSlice(self.allocator);
        }

        // Restore escaped characters in text fields
        // Brief and details may contain placeholders that need to be converted back
        if (doc.brief) |brief| {
            if (hasEscapedPlaceholders(brief)) {
                doc.brief = try self.restoreEscapedChars(brief);
            }
        }
        if (doc.details) |details| {
            if (hasEscapedPlaceholders(details)) {
                doc.details = try self.restoreEscapedChars(details);
            }
        }

        // Restore escaped characters in param descriptions
        // We need to create new ParamDoc entries with restored descriptions
        if (doc.params.len > 0) {
            var restored_params: std.ArrayList(types.ParamDoc) = .empty;
            for (doc.params) |param| {
                const restored_desc = if (hasEscapedPlaceholders(param.description))
                    try self.restoreEscapedChars(param.description)
                else
                    param.description;
                try restored_params.append(self.allocator, types.ParamDoc{
                    .name = param.name,
                    .description = restored_desc,
                });
            }
            doc.params = try restored_params.toOwnedSlice(self.allocator);
        }

        // Restore escaped characters in return description
        if (doc.returns) |returns| {
            if (hasEscapedPlaceholders(returns)) {
                doc.returns = try self.restoreEscapedChars(returns);
            }
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

    /// Checks if a docstring contains @page or @mainpage command
    pub fn containsPageCommand(_: *Self, text: []const u8) bool {
        // Look for @page or @mainpage (or \page, \mainpage)
        if (std.mem.indexOf(u8, text, "@page") != null or
            std.mem.indexOf(u8, text, "\\page") != null or
            std.mem.indexOf(u8, text, "@mainpage") != null or
            std.mem.indexOf(u8, text, "\\mainpage") != null)
        {
            return true;
        }
        return false;
    }

    /// Checks if a docstring contains @defgroup or @addtogroup command
    pub fn containsGroupCommand(_: *Self, text: []const u8) bool {
        // Look for @defgroup or @addtogroup (or \ prefix)
        if (std.mem.indexOf(u8, text, "@defgroup") != null or
            std.mem.indexOf(u8, text, "\\defgroup") != null or
            std.mem.indexOf(u8, text, "@addtogroup") != null or
            std.mem.indexOf(u8, text, "\\addtogroup") != null)
        {
            return true;
        }
        return false;
    }

    /// Parses a @defgroup or @addtogroup docstring into a Group struct
    /// Format: @defgroup group_id Group Title
    ///         Optional brief description on following lines
    /// Or:     @addtogroup group_id
    pub fn parseGroup(self: *Self, text: []const u8) ?types.Group {
        var lines = std.mem.splitScalar(u8, text, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r*");

            // Look for @defgroup group_id Title
            if (startsWithCommand(trimmed, "defgroup ")) {
                const rest = std.mem.trim(u8, trimmed[10..], " \t");
                // Parse: group_id Title
                var parts = std.mem.splitScalar(u8, rest, ' ');
                if (parts.next()) |group_id| {
                    // Rest is the title
                    const title_start = 10 + group_id.len + 1;
                    const title = if (title_start < trimmed.len)
                        std.mem.trim(u8, trimmed[title_start..], " \t")
                    else
                        group_id; // Use ID as title if no title provided

                    // Look for brief description on following lines
                    var brief: ?[]const u8 = null;
                    if (lines.next()) |next_line| {
                        const next_trimmed = std.mem.trim(u8, next_line, " \t\r*");
                        // If next line doesn't start with @ or \, it's the brief
                        if (next_trimmed.len > 0 and next_trimmed[0] != '@' and next_trimmed[0] != '\\') {
                            brief = next_trimmed;
                        }
                    }

                    return types.Group{
                        .id = group_id,
                        .name = title,
                        .brief = brief,
                    };
                }
            }
            // Look for @addtogroup group_id (just references existing group)
            else if (startsWithCommand(trimmed, "addtogroup ")) {
                const group_id = std.mem.trim(u8, trimmed[12..], " \t");
                if (group_id.len > 0) {
                    return types.Group{
                        .id = group_id,
                        .name = group_id, // Use ID as name for addtogroup
                        .brief = null,
                    };
                }
            }
        }

        _ = self;
        return null;
    }

    /// Checks if text contains @ref or \ref tags for cross-references
    pub fn containsRef(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "@ref ") != null or
            std.mem.indexOf(u8, text, "\\ref ") != null;
    }

    /// Extracts all @ref tags from text (for inline references in brief/details)
    /// Returns a list of RefLink structs found in the text
    pub fn extractInlineRefs(self: *Self, text: []const u8) ![]types.RefLink {
        var refs_list: std.ArrayList(types.RefLink) = .empty;

        var pos: usize = 0;
        while (pos < text.len) {
            // Look for @ref or \ref
            const at_ref = std.mem.indexOfPos(u8, text, pos, "@ref ");
            const backslash_ref = std.mem.indexOfPos(u8, text, pos, "\\ref ");

            const ref_pos = blk: {
                if (at_ref != null and backslash_ref != null) {
                    break :blk @min(at_ref.?, backslash_ref.?);
                } else if (at_ref != null) {
                    break :blk at_ref.?;
                } else if (backslash_ref != null) {
                    break :blk backslash_ref.?;
                } else {
                    break;
                }
            };

            // Skip past "@ref " or "\ref "
            pos = ref_pos + 5;

            // Extract target and optional display text
            const rest = text[pos..];

            // Check for quoted display text
            if (std.mem.indexOf(u8, rest, "\"")) |quote_start| {
                // Find closing quote
                if (std.mem.indexOfPos(u8, rest, quote_start + 1, "\"")) |quote_end| {
                    const target = std.mem.trim(u8, rest[0..quote_start], " \t");
                    const display_text = rest[quote_start + 1 .. quote_end];
                    try refs_list.append(self.allocator, types.RefLink{
                        .target = target,
                        .display_text = display_text,
                    });
                    pos += quote_end + 1;
                    continue;
                }
            }

            // No display text - extract target until whitespace or certain punctuation
            // Allow () for function references like "Class::method()"
            var target_end: usize = 0;
            var paren_depth: usize = 0;
            for (rest, 0..) |c, i| {
                if (c == '(') {
                    paren_depth += 1;
                } else if (c == ')') {
                    if (paren_depth > 0) {
                        paren_depth -= 1;
                        // If we just closed all parens, include the ) and stop
                        if (paren_depth == 0) {
                            target_end = i + 1;
                            break;
                        }
                    } else {
                        // Unmatched ), stop here
                        target_end = i;
                        break;
                    }
                } else if (paren_depth == 0 and (c == ' ' or c == '\t' or c == '\n' or c == ',' or c == '.' or c == ']' or c == ';')) {
                    target_end = i;
                    break;
                }
            }

            if (target_end == 0) {
                target_end = rest.len;
            }

            const target = std.mem.trim(u8, rest[0..target_end], " \t");
            if (target.len > 0) {
                try refs_list.append(self.allocator, types.RefLink{
                    .target = target,
                });
            }

            pos += target_end;
        }

        return try refs_list.toOwnedSlice(self.allocator);
    }

    /// Parses a @page or @mainpage docstring into a Page struct
    /// Format: @page page_id Page Title
    ///         Content follows...
    /// Or:     @mainpage Page Title
    ///         Content follows...
    pub fn parsePage(self: *Self, text: []const u8) !?types.Page {
        var lines = std.mem.splitScalar(u8, text, '\n');
        var is_mainpage = false;
        var page_id: ?[]const u8 = null;
        var title: ?[]const u8 = null;
        var content_lines: std.ArrayList([]const u8) = .empty;
        defer content_lines.deinit(self.allocator);

        var found_page_command = false;

        while (lines.next()) |line| {
            var trimmed = std.mem.trim(u8, line, " \t\r");

            // Strip leading asterisks from multi-line comments
            if (std.mem.startsWith(u8, trimmed, "* ")) {
                trimmed = trimmed[2..];
            } else if (std.mem.startsWith(u8, trimmed, "*")) {
                trimmed = std.mem.trimLeft(u8, trimmed[1..], " ");
            }

            if (!found_page_command) {
                // Look for @mainpage first (no page_id, just title)
                if (startsWithCommand(trimmed, "mainpage")) {
                    is_mainpage = true;
                    found_page_command = true;
                    page_id = "mainpage";

                    // Rest of line after @mainpage is the title
                    const after_cmd = std.mem.trimLeft(u8, trimmed[commandPrefixLen("mainpage")..], " \t");
                    if (after_cmd.len > 0) {
                        title = after_cmd;
                    }
                    continue;
                }

                // Look for @page page_id Title
                if (startsWithCommand(trimmed, "page")) {
                    found_page_command = true;

                    // Parse: @page page_id Title text
                    const after_cmd = std.mem.trimLeft(u8, trimmed[commandPrefixLen("page")..], " \t");

                    // Split into page_id and title
                    if (std.mem.indexOfScalar(u8, after_cmd, ' ')) |space_idx| {
                        page_id = after_cmd[0..space_idx];
                        title = std.mem.trimLeft(u8, after_cmd[space_idx + 1 ..], " \t");
                        if (title.?.len == 0) title = null;
                    } else {
                        // Only page_id, no title
                        page_id = after_cmd;
                    }
                    continue;
                }

                // Skip lines before finding the page command
                continue;
            }

            // After finding page command, collect content lines
            // Skip empty lines at the very beginning of content
            if (content_lines.items.len == 0 and trimmed.len == 0) {
                continue;
            }

            try content_lines.append(self.allocator, trimmed);
        }

        if (!found_page_command or page_id == null) {
            return null;
        }

        // Join content lines
        var content_buf: std.ArrayList(u8) = .empty;
        defer content_buf.deinit(self.allocator);

        for (content_lines.items, 0..) |content_line, idx| {
            try content_buf.appendSlice(self.allocator, content_line);
            if (idx < content_lines.items.len - 1) {
                try content_buf.append(self.allocator, '\n');
            }
        }

        // Trim trailing empty lines from content
        const content = std.mem.trimRight(u8, content_buf.items, " \t\n\r");

        // Allocate content string
        const content_copy = try self.allocator.dupe(u8, content);

        return types.Page{
            .id = page_id.?,
            .title = title orelse page_id.?,
            .content = content_copy,
            .is_mainpage = is_mainpage,
        };
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
        \\* @brief Old function.
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
        \\* @param x Some parameter
    );
    defer std.testing.allocator.free(doc.params);
    defer std.testing.allocator.free(doc.raw);

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
        \\* @brief Does something.
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
        \\* @brief Dangerous function.
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
        \\* @brief Gets a value.
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
        \\* @brief New feature.
        \\* @since 2.0.0
    );

    try std.testing.expectEqualStrings("New feature.", doc.brief.?);
    try std.testing.expectEqualStrings("2.0.0", doc.since.?);
}

test "parse author tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Core function.
        \\* @author John Doe
    );

    try std.testing.expectEqualStrings("Core function.", doc.brief.?);
    try std.testing.expectEqualStrings("John Doe", doc.author.?);
}

test "parse version tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Library info.
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
        \\* @brief Validates input.
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
        \\* @brief Accesses element.
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
        \\* @brief Processes data.
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
        \\* @brief A container class.
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
        \\* @brief Opens a file.
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
        \\* @brief Sorts the array.
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
        \\* @brief Processes the data.
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
        \\* \brief Function description.
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
        \\* @brief Example function.
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
        \\* \brief Example function.
        \\* \snippet examples/test.cpp my_example
    );
    defer std.testing.allocator.free(doc.snippets);

    try std.testing.expectEqual(@as(usize, 1), doc.snippets.len);
    try std.testing.expectEqualStrings("examples/test.cpp", doc.snippets[0].file);
    try std.testing.expectEqualStrings("my_example", doc.snippets[0].anchor);
}

test "parse attention tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Initializes the system.
        \\* @attention This function is NOT thread-safe!
        \\* @attention Memory must be manually freed after use
    );
    defer std.testing.allocator.free(doc.attention);

    try std.testing.expectEqualStrings("Initializes the system.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.attention.len);
    try std.testing.expectEqualStrings("This function is NOT thread-safe!", doc.attention[0]);
    try std.testing.expectEqualStrings("Memory must be manually freed after use", doc.attention[1]);
}

test "parse important tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Initializes the system.
        \\* @important Must be called before any other API function
        \\* @important Do not call from interrupt context
    );
    defer std.testing.allocator.free(doc.important);

    try std.testing.expectEqualStrings("Initializes the system.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.important.len);
    try std.testing.expectEqualStrings("Must be called before any other API function", doc.important[0]);
    try std.testing.expectEqualStrings("Do not call from interrupt context", doc.important[1]);
}

test "parse attention and important with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief Function description.
        \\* \attention First attention item
        \\* \important First important item
    );
    defer {
        std.testing.allocator.free(doc.attention);
        std.testing.allocator.free(doc.important);
    }

    try std.testing.expectEqual(@as(usize, 1), doc.attention.len);
    try std.testing.expectEqualStrings("First attention item", doc.attention[0]);
    try std.testing.expectEqual(@as(usize, 1), doc.important.len);
    try std.testing.expectEqualStrings("First important item", doc.important[0]);
}

test "parse date tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief A function with date.
        \\* @date 2024-01-15
    );
    defer std.testing.allocator.free(doc.dates);

    try std.testing.expectEqualStrings("A function with date.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.dates.len);
    try std.testing.expectEqualStrings("2024-01-15", doc.dates[0].date);
    try std.testing.expect(doc.dates[0].description == null);
}

test "parse date tag with description" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief A function with dates.
        \\* @date 2023-06-20 created
        \\* @date 2024-01-10 updated for 3D support
    );
    defer std.testing.allocator.free(doc.dates);

    try std.testing.expectEqual(@as(usize, 2), doc.dates.len);
    try std.testing.expectEqualStrings("2023-06-20", doc.dates[0].date);
    try std.testing.expectEqualStrings("created", doc.dates[0].description.?);
    try std.testing.expectEqualStrings("2024-01-10", doc.dates[1].date);
    try std.testing.expectEqualStrings("updated for 3D support", doc.dates[1].description.?);
}

test "parse copyright tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief A function with copyright.
        \\* @copyright 2024 MyCompany, MIT License
    );

    try std.testing.expectEqualStrings("A function with copyright.", doc.brief.?);
    try std.testing.expectEqualStrings("2024 MyCompany, MIT License", doc.copyright.?);
}

test "parse date and copyright with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief File description.
        \\* \date 2024-01-15
        \\* \copyright 2024 Company Inc.
    );
    defer std.testing.allocator.free(doc.dates);

    try std.testing.expectEqual(@as(usize, 1), doc.dates.len);
    try std.testing.expectEqualStrings("2024-01-15", doc.dates[0].date);
    try std.testing.expectEqualStrings("2024 Company Inc.", doc.copyright.?);
}

test "parse mermaid block" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Connection class.
        \\* @mermaid
        \\* stateDiagram-v2
        \\*     [*] --> Disconnected
        \\*     Disconnected --> Connected
        \\* @endmermaid
    );
    defer std.testing.allocator.free(doc.mermaid_diagrams);

    try std.testing.expectEqualStrings("Connection class.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 1), doc.mermaid_diagrams.len);
    try std.testing.expect(doc.mermaid_diagrams[0].caption == null);
    try std.testing.expect(std.mem.indexOf(u8, doc.mermaid_diagrams[0].content, "stateDiagram-v2") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.mermaid_diagrams[0].content, "[*] --> Disconnected") != null);
}

test "parse mermaid block with caption" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Connection class.
        \\* @mermaid State Diagram
        \\* stateDiagram-v2
        \\*     [*] --> Idle
        \\* @endmermaid
    );
    defer std.testing.allocator.free(doc.mermaid_diagrams);

    try std.testing.expectEqual(@as(usize, 1), doc.mermaid_diagrams.len);
    try std.testing.expectEqualStrings("State Diagram", doc.mermaid_diagrams[0].caption.?);
    try std.testing.expect(std.mem.indexOf(u8, doc.mermaid_diagrams[0].content, "stateDiagram-v2") != null);
}

test "parse multiple mermaid blocks" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Data processor.
        \\* @mermaid Flow
        \\* flowchart LR
        \\*     A --> B
        \\* @endmermaid
        \\* @mermaid State
        \\* stateDiagram-v2
        \\*     [*] --> Active
        \\* @endmermaid
    );
    defer std.testing.allocator.free(doc.mermaid_diagrams);

    try std.testing.expectEqual(@as(usize, 2), doc.mermaid_diagrams.len);
    try std.testing.expectEqualStrings("Flow", doc.mermaid_diagrams[0].caption.?);
    try std.testing.expectEqualStrings("State", doc.mermaid_diagrams[1].caption.?);
}

test "parse mermaid with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief Flow chart.
        \\* \mermaid
        \\* flowchart TD
        \\*     Start --> End
        \\* \endmermaid
    );
    defer std.testing.allocator.free(doc.mermaid_diagrams);

    try std.testing.expectEqual(@as(usize, 1), doc.mermaid_diagrams.len);
    try std.testing.expect(std.mem.indexOf(u8, doc.mermaid_diagrams[0].content, "flowchart TD") != null);
}

test "containsPageCommand" {
    var extractor = DocstringExtractor.init(std.testing.allocator);

    try std.testing.expect(extractor.containsPageCommand("@page examples Example Page"));
    try std.testing.expect(extractor.containsPageCommand("\\page examples Example Page"));
    try std.testing.expect(extractor.containsPageCommand("@mainpage My Project"));
    try std.testing.expect(extractor.containsPageCommand("\\mainpage My Project"));
    try std.testing.expect(!extractor.containsPageCommand("@param x A parameter"));
    try std.testing.expect(!extractor.containsPageCommand("Just some text"));
}

test "parsePage with @page" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const page = try extractor.parsePage(
        \\* @page examples Example Code
        \\* 
        \\* ## Usage
        \\* 
        \\* Here's how to use it.
    );
    defer if (page) |p| std.testing.allocator.free(p.content);

    try std.testing.expect(page != null);
    try std.testing.expectEqualStrings("examples", page.?.id);
    try std.testing.expectEqualStrings("Example Code", page.?.title);
    try std.testing.expect(!page.?.is_mainpage);
    try std.testing.expect(std.mem.indexOf(u8, page.?.content, "## Usage") != null);
}

test "parsePage with @mainpage" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const page = try extractor.parsePage(
        \\* @mainpage Project Documentation
        \\* 
        \\* Welcome to the project!
    );
    defer if (page) |p| std.testing.allocator.free(p.content);

    try std.testing.expect(page != null);
    try std.testing.expectEqualStrings("mainpage", page.?.id);
    try std.testing.expectEqualStrings("Project Documentation", page.?.title);
    try std.testing.expect(page.?.is_mainpage);
    try std.testing.expect(std.mem.indexOf(u8, page.?.content, "Welcome to the project!") != null);
}

test "parse test tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Calculates factorial.
        \\* @test test_factorial_basic
        \\* @test test_factorial_zero
    );
    defer std.testing.allocator.free(doc.tests);

    try std.testing.expectEqualStrings("Calculates factorial.", doc.brief.?);
    try std.testing.expectEqual(@as(usize, 2), doc.tests.len);
    try std.testing.expectEqualStrings("test_factorial_basic", doc.tests[0].name);
    try std.testing.expect(doc.tests[0].file == null);
    try std.testing.expectEqualStrings("test_factorial_zero", doc.tests[1].name);
    try std.testing.expect(doc.tests[1].file == null);
}

test "parse test tag with file" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Calculates factorial.
        \\* @test test_factorial_negative test/test_math.cpp
    );
    defer std.testing.allocator.free(doc.tests);

    try std.testing.expectEqual(@as(usize, 1), doc.tests.len);
    try std.testing.expectEqualStrings("test_factorial_negative", doc.tests[0].name);
    try std.testing.expectEqualStrings("test/test_math.cpp", doc.tests[0].file.?);
}

test "parse test with backslash prefix" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief Function description.
        \\* \test test_my_function
        \\* \test test_edge_case test/edge.cpp
    );
    defer std.testing.allocator.free(doc.tests);

    try std.testing.expectEqual(@as(usize, 2), doc.tests.len);
    try std.testing.expectEqualStrings("test_my_function", doc.tests[0].name);
    try std.testing.expect(doc.tests[0].file == null);
    try std.testing.expectEqualStrings("test_edge_case", doc.tests[1].name);
    try std.testing.expectEqualStrings("test/edge.cpp", doc.tests[1].file.?);
}

test "multi-line param continuation" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* @param buffer The buffer to write to. This buffer must be
        \\*               at least 256 bytes in size.
        \\* @param size The size
    );
    defer std.testing.allocator.free(doc.params);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 2), doc.params.len);
    try std.testing.expectEqualStrings("buffer", doc.params[0].name);
    // The continuation should be joined with a space
    try std.testing.expect(std.mem.indexOf(u8, doc.params[0].description, "at least 256 bytes") != null);
}

test "multi-line return continuation" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* @return The number of bytes written, or -1 on error. If the
        \\*         buffer is too small, returns 0.
    );
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expect(doc.returns != null);
    // The continuation should be joined
    try std.testing.expect(std.mem.indexOf(u8, doc.returns.?, "buffer is too small") != null);
}

test "continuation ends at new tag" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* @param x First param with
        \\*          continuation.
        \\* @param y Second param
    );
    defer std.testing.allocator.free(doc.params);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 2), doc.params.len);
    try std.testing.expectEqualStrings("x", doc.params[0].name);
    try std.testing.expect(std.mem.indexOf(u8, doc.params[0].description, "continuation") != null);
    try std.testing.expectEqualStrings("y", doc.params[1].name);
}

test "code block not joined" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Brief description.
        \\* @code
        \\* int x = 5;
        \\* int y = 10;
        \\* @endcode
    );
    defer std.testing.allocator.free(doc.code_blocks);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 1), doc.code_blocks.len);
    // Code block lines should be preserved with newlines, not joined
    try std.testing.expect(std.mem.indexOf(u8, doc.code_blocks[0].content, "\n") != null);
}

// =============================================================================
// Escaped Character Tests
// =============================================================================

test "escaped @@ produces literal @" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Contact: user@@domain.com
    );
    defer std.testing.allocator.free(doc.raw);

    // Brief should contain literal @ not @@
    try std.testing.expect(doc.brief != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.brief.?, "user@domain.com") != null);
    // Should NOT contain @@
    try std.testing.expect(std.mem.indexOf(u8, doc.brief.?, "@@") == null);
}

test "escaped \\\\ produces literal \\" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* \brief Path: C:\\Users\\name
    );
    defer std.testing.allocator.free(doc.raw);

    // Brief should contain single backslashes
    try std.testing.expect(doc.brief != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.brief.?, "C:\\Users\\name") != null);
}

test "escaped @@ in @brief" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Email is user@@example.com
    );
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expect(doc.brief != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.brief.?, "user@example.com") != null);
}

test "mixed escaped and real tags" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Send email to user@@domain.com
        \\* @param email The email address
    );
    defer std.testing.allocator.free(doc.raw);
    defer std.testing.allocator.free(doc.params);

    // Brief should have literal @
    try std.testing.expect(doc.brief != null);
    try std.testing.expect(std.mem.indexOf(u8, doc.brief.?, "user@domain.com") != null);
    // Param should be parsed correctly
    try std.testing.expectEqual(@as(usize, 1), doc.params.len);
    try std.testing.expectEqualStrings("email", doc.params[0].name);
}

// =============================================================================
// @ref Extraction Tests
// =============================================================================

test "extract @ref from warning" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Brief description.
        \\* @warning Using @ref DangerousAPI may crash!
    );
    defer std.testing.allocator.free(doc.warnings);
    defer std.testing.allocator.free(doc.refs);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 1), doc.warnings.len);
    try std.testing.expectEqual(@as(usize, 1), doc.refs.len);
    try std.testing.expectEqualStrings("DangerousAPI", doc.refs[0].target);
}

test "extract @ref from param description" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* @param callback See @ref CallbackType for details
    );
    defer std.testing.allocator.free(doc.params);
    defer std.testing.allocator.free(doc.refs);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 1), doc.params.len);
    try std.testing.expectEqual(@as(usize, 1), doc.refs.len);
    try std.testing.expectEqualStrings("CallbackType", doc.refs[0].target);
}

test "extract @ref from note" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* @brief Brief description.
        \\* @note See @ref OtherClass for more info
    );
    defer std.testing.allocator.free(doc.notes);
    defer std.testing.allocator.free(doc.refs);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expectEqual(@as(usize, 1), doc.notes.len);
    try std.testing.expectEqual(@as(usize, 1), doc.refs.len);
    try std.testing.expectEqualStrings("OtherClass", doc.refs[0].target);
}

test "extract @ref from return description" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* Brief description.
        \\* @return A @ref Result object
    );
    defer std.testing.allocator.free(doc.refs);
    defer std.testing.allocator.free(doc.raw);

    try std.testing.expect(doc.returns != null);
    try std.testing.expectEqual(@as(usize, 1), doc.refs.len);
    try std.testing.expectEqualStrings("Result", doc.refs[0].target);
}

test "extract multiple @ref from different tags" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const doc = try extractor.parse(
        \\* See @ref MainClass for overview.
        \\* @param x Uses @ref TypeA
        \\* @warning May throw @ref Exception
        \\* @return A @ref Result
    );
    defer std.testing.allocator.free(doc.params);
    defer std.testing.allocator.free(doc.warnings);
    defer std.testing.allocator.free(doc.refs);
    defer std.testing.allocator.free(doc.raw);

    // Should have refs from brief, param, warning, and return
    try std.testing.expectEqual(@as(usize, 4), doc.refs.len);
}

// =============================================================================
// @defgroup and @addtogroup Tests
// =============================================================================

test "containsGroupCommand" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    try std.testing.expect(extractor.containsGroupCommand("@defgroup math_utils Math Utilities"));
    try std.testing.expect(extractor.containsGroupCommand("\\defgroup math_utils Math Utilities"));
    try std.testing.expect(extractor.containsGroupCommand("@addtogroup math_utils"));
    try std.testing.expect(extractor.containsGroupCommand("\\addtogroup math_utils"));
    try std.testing.expect(!extractor.containsGroupCommand("@param x A parameter"));
    try std.testing.expect(!extractor.containsGroupCommand("Just some text"));
}

test "parseGroup with @defgroup" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const group = extractor.parseGroup("@defgroup math_utils Math Utilities");

    try std.testing.expect(group != null);
    try std.testing.expectEqualStrings("math_utils", group.?.id);
    try std.testing.expectEqualStrings("Math Utilities", group.?.name);
}

test "parseGroup with @defgroup and brief" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const group = extractor.parseGroup(
        \\@defgroup io_utils I/O Utilities
        \\Functions for input/output operations
    );

    try std.testing.expect(group != null);
    try std.testing.expectEqualStrings("io_utils", group.?.id);
    try std.testing.expectEqualStrings("I/O Utilities", group.?.name);
    try std.testing.expect(group.?.brief != null);
    try std.testing.expect(std.mem.indexOf(u8, group.?.brief.?, "input/output") != null);
}

test "parseGroup with @addtogroup" {
    var extractor = DocstringExtractor.init(std.testing.allocator);
    const group = extractor.parseGroup("@addtogroup math_utils");

    try std.testing.expect(group != null);
    try std.testing.expectEqualStrings("math_utils", group.?.id);
    // For addtogroup, name defaults to id
    try std.testing.expectEqualStrings("math_utils", group.?.name);
}
