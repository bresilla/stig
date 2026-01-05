const std = @import("std");
const types = @import("../model/types.zig");
const xref = @import("../xref.zig");
const config = @import("../config.zig");
const snippet_mod = @import("../snippet.zig");
const extractor_mod = @import("../docstring/extractor.zig");
const godbolt_mod = @import("../godbolt.zig");

/// Markdown output generator with optional cross-reference support
pub const MarkdownGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,
    /// Optional symbol table for cross-reference resolution
    symbol_table: ?*xref.SymbolTable = null,
    /// Current file being generated (for relative link calculation)
    current_file: []const u8 = "",
    /// Output format (affects link generation)
    output_format: xref.SymbolTable.OutputFormat = .markdown,
    /// Configuration for filtering and output options
    cfg: config.Config = .{},
    /// Optional snippet extractor for @snippet tags
    snippet_extractor: ?*snippet_mod.SnippetExtractor = null,
    /// All classes for inheritance diagram generation
    all_classes: ?[]const types.Class = null,
    /// All pages for @ref resolution
    all_pages: []const types.Page = &[_]types.Page{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Initialize with cross-reference support
    pub fn initWithXRef(
        allocator: std.mem.Allocator,
        symbol_table: *xref.SymbolTable,
        current_file: []const u8,
        output_format: xref.SymbolTable.OutputFormat,
    ) Self {
        return Self{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .current_file = current_file,
            .output_format = output_format,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Sets the symbol table for cross-reference resolution
    pub fn setSymbolTable(self: *Self, table: *xref.SymbolTable) void {
        self.symbol_table = table;
    }

    /// Sets the current file context for relative link generation
    pub fn setCurrentFile(self: *Self, file: []const u8) void {
        self.current_file = file;
    }

    /// Sets the output format
    pub fn setOutputFormat(self: *Self, format: xref.SymbolTable.OutputFormat) void {
        self.output_format = format;
    }

    /// Sets the configuration
    pub fn setConfig(self: *Self, cfg_: config.Config) void {
        self.cfg = cfg_;
    }

    /// Sets the snippet extractor for @snippet tag support
    pub fn setSnippetExtractor(self: *Self, extractor: *snippet_mod.SnippetExtractor) void {
        self.snippet_extractor = extractor;
    }

    /// Sets all classes for inheritance diagram generation
    pub fn setAllClasses(self: *Self, classes: []const types.Class) void {
        self.all_classes = classes;
    }

    /// Checks if an entity name should be excluded based on namespace blacklist
    fn isBlacklistedNamespace(self: *Self, name: []const u8) bool {
        for (self.cfg.blacklist_namespace) |blacklisted| {
            // Check if name contains the blacklisted namespace
            // e.g., "foo::detail::bar" should match "detail"
            if (std.mem.indexOf(u8, name, blacklisted)) |idx| {
                // Verify it's a proper namespace component (preceded by :: or start, followed by :: or end)
                const before_ok = idx == 0 or (idx >= 2 and std.mem.eql(u8, name[idx - 2 .. idx], "::"));
                const after_idx = idx + blacklisted.len;
                const after_ok = after_idx >= name.len or (after_idx + 2 <= name.len and std.mem.eql(u8, name[after_idx .. after_idx + 2], "::"));
                if (before_ok and after_ok) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Checks if an entity name matches any blacklist pattern (glob with * and ?)
    fn isBlacklistedPattern(self: *Self, name: []const u8) bool {
        for (self.cfg.blacklist_pattern) |pattern| {
            if (globMatch(pattern, name)) {
                return true;
            }
        }
        return false;
    }

    /// Simple glob matching with * (any chars) and ? (single char)
    fn globMatch(pattern: []const u8, text: []const u8) bool {
        var pi: usize = 0;
        var ti: usize = 0;
        var star_pi: ?usize = null;
        var star_ti: usize = 0;

        while (ti < text.len) {
            if (pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == text[ti])) {
                pi += 1;
                ti += 1;
            } else if (pi < pattern.len and pattern[pi] == '*') {
                star_pi = pi;
                star_ti = ti;
                pi += 1;
            } else if (star_pi) |sp| {
                pi = sp + 1;
                star_ti += 1;
                ti = star_ti;
            } else {
                return false;
            }
        }

        while (pi < pattern.len and pattern[pi] == '*') {
            pi += 1;
        }

        return pi == pattern.len;
    }

    /// Checks if an entity should be excluded based on all blacklist rules
    fn shouldExclude(self: *Self, name: []const u8, doc: ?types.DocString) bool {
        // Check @exclude tag
        if (doc) |d| {
            if (d.exclude == .full) return true;
        }
        // Check namespace blacklist
        if (self.isBlacklistedNamespace(name)) return true;
        // Check pattern blacklist
        if (self.isBlacklistedPattern(name)) return true;
        return false;
    }

    /// Generates markdown documentation for a module
    pub fn generate(self: *Self, module: types.Module) ![]const u8 {
        // Clear buffer for fresh generation
        self.buffer.clearRetainingCapacity();

        // Store pages for @ref resolution
        self.all_pages = module.pages;

        try self.writeHeader(module.name);

        // File-level documentation (@file)
        if (module.file_doc) |file_doc| {
            if (file_doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
            if (file_doc.details) |details| {
                try self.writeTextWithRefs(details, self.all_pages);
                try self.writeString("\n\n");
            }
            if (file_doc.author) |author| {
                try self.writeString("**Author:** ");
                try self.writeString(author);
                try self.writeString("\n\n");
            }
            if (file_doc.since) |since| {
                try self.writeString("**Since:** ");
                try self.writeString(since);
                try self.writeString("\n\n");
            }
            if (file_doc.version) |version| {
                try self.writeString("**Version:** ");
                try self.writeString(version);
                try self.writeString("\n\n");
            }
            if (file_doc.deprecated) |deprecated| {
                try self.writeString("> **Deprecated:** ");
                try self.writeString(deprecated);
                try self.writeString("\n\n");
            }
            if (file_doc.copyright) |copyright| {
                try self.writeString("**Copyright:** ");
                try self.writeString(copyright);
                try self.writeString("\n\n");
            }
            if (file_doc.dates.len > 0) {
                if (file_doc.dates.len == 1) {
                    try self.writeString("**Date:** ");
                    try self.writeString(file_doc.dates[0].date);
                    if (file_doc.dates[0].description) |desc| {
                        try self.writeString(" (");
                        try self.writeString(desc);
                        try self.writeString(")");
                    }
                    try self.writeString("\n\n");
                } else {
                    try self.writeString("**History:**\n");
                    for (file_doc.dates) |date_info| {
                        try self.writeString("- ");
                        try self.writeString(date_info.date);
                        if (date_info.description) |desc| {
                            try self.writeString(": ");
                            try self.writeString(desc);
                        }
                        try self.writeString("\n");
                    }
                    try self.writeString("\n");
                }
            }
        }

        // Functions section
        if (module.functions.len > 0) {
            var has_visible_funcs = false;
            for (module.functions) |func| {
                if (!self.shouldExclude(func.name, func.doc)) {
                    has_visible_funcs = true;
                    break;
                }
            }
            if (has_visible_funcs) {
                try self.writeString("## Functions\n\n");
                try self.writeFunctionsWithGroups(module.functions);
            }
        }

        // Structs section
        if (module.structs.len > 0) {
            var has_visible_structs = false;
            for (module.structs) |s| {
                if (!self.shouldExclude(s.name, s.doc)) {
                    has_visible_structs = true;
                    break;
                }
            }
            if (has_visible_structs) {
                try self.writeString("## Structures\n\n");
                for (module.structs) |s| {
                    if (self.shouldExclude(s.name, s.doc)) continue;
                    try self.writeStruct(s);
                }
            }
        }

        // Unions section
        if (module.unions.len > 0) {
            var has_visible_unions = false;
            for (module.unions) |u| {
                if (!self.shouldExclude(u.name, u.doc)) {
                    has_visible_unions = true;
                    break;
                }
            }
            if (has_visible_unions) {
                try self.writeString("## Unions\n\n");
                for (module.unions) |u| {
                    if (self.shouldExclude(u.name, u.doc)) continue;
                    try self.writeUnion(u);
                }
            }
        }

        // Enums section
        if (module.enums.len > 0) {
            var has_visible_enums = false;
            for (module.enums) |e| {
                if (!self.shouldExclude(e.name, e.doc)) {
                    has_visible_enums = true;
                    break;
                }
            }
            if (has_visible_enums) {
                try self.writeString("## Enumerations\n\n");
                for (module.enums) |e| {
                    if (self.shouldExclude(e.name, e.doc)) continue;
                    try self.writeEnum(e);
                }
            }
        }

        // Typedefs section
        if (module.typedefs.len > 0) {
            var has_visible_typedefs = false;
            for (module.typedefs) |td| {
                if (!self.shouldExclude(td.name, td.doc)) {
                    has_visible_typedefs = true;
                    break;
                }
            }
            if (has_visible_typedefs) {
                try self.writeString("## Type Definitions\n\n");
                for (module.typedefs) |td| {
                    if (self.shouldExclude(td.name, td.doc)) continue;
                    try self.writeTypedef(td);
                }
            }
        }

        // Macros section
        if (module.macros.len > 0) {
            var has_visible_macros = false;
            for (module.macros) |macro| {
                if (!self.shouldExclude(macro.name, macro.doc)) {
                    has_visible_macros = true;
                    break;
                }
            }
            if (has_visible_macros) {
                try self.writeString("## Macros\n\n");
                for (module.macros) |macro| {
                    if (self.shouldExclude(macro.name, macro.doc)) continue;
                    try self.writeMacro(macro);
                }
            }
        }

        // Classes section (C++)
        if (module.classes.len > 0) {
            var has_visible_classes = false;
            for (module.classes) |class| {
                if (!self.shouldExclude(class.name, class.doc)) {
                    has_visible_classes = true;
                    break;
                }
            }
            if (has_visible_classes) {
                try self.writeString("## Classes\n\n");
                for (module.classes) |class| {
                    if (self.shouldExclude(class.name, class.doc)) continue;
                    try self.writeClass(class);
                }
            }
        }

        // Type Aliases section (C++)
        if (module.type_aliases.len > 0) {
            var has_visible_aliases = false;
            for (module.type_aliases) |alias| {
                if (alias.docstring == null or alias.docstring.?.exclude != .full) {
                    has_visible_aliases = true;
                    break;
                }
            }
            if (has_visible_aliases) {
                try self.writeString("## Type Aliases\n\n");
                for (module.type_aliases) |alias| {
                    if (alias.docstring != null and alias.docstring.?.exclude == .full) continue;
                    try self.writeTypeAlias(alias);
                }
            }
        }

        // Concepts section (C++20)
        if (module.concepts.len > 0) {
            var has_visible_concepts = false;
            for (module.concepts) |concept| {
                if (concept.docstring == null or concept.docstring.?.exclude != .full) {
                    has_visible_concepts = true;
                    break;
                }
            }
            if (has_visible_concepts) {
                try self.writeString("## Concepts\n\n");
                for (module.concepts) |concept| {
                    if (concept.docstring != null and concept.docstring.?.exclude == .full) continue;
                    try self.writeConcept(concept);
                }
            }
        }

        return self.buffer.items;
    }

    fn writeHeader(self: *Self, name: []const u8) !void {
        try self.writeString("# ");
        try self.writeString(name);
        try self.writeString("\n\n");
    }

    fn writeString(self: *Self, s: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, s);
    }

    /// Writes a string with HTML entities escaped (< > &)
    /// Used for type strings that appear outside code blocks
    fn writeEscaped(self: *Self, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '<' => try self.buffer.appendSlice(self.allocator, "&lt;"),
                '>' => try self.buffer.appendSlice(self.allocator, "&gt;"),
                '&' => try self.buffer.appendSlice(self.allocator, "&amp;"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
    }

    /// Writes text with @ref tags converted to markdown links
    /// Processes inline @ref and \ref tags and converts them to [text](link) format
    fn writeTextWithRefs(self: *Self, text: []const u8, pages: []const types.Page) !void {
        // Check if text contains any @ref tags
        if (!extractor_mod.DocstringExtractor.containsRef(text)) {
            // No refs, just write as-is
            try self.writeString(text);
            return;
        }

        // Process text and replace @ref tags with markdown links
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
                    // No more refs, write rest of text
                    try self.writeString(text[pos..]);
                    return;
                }
            };

            // Write text before @ref
            try self.writeString(text[pos..ref_pos]);

            // Skip past "@ref " or "\ref "
            pos = ref_pos + 5;

            // Extract target and optional display text
            const rest = text[pos..];
            var target: []const u8 = "";
            var display_text: ?[]const u8 = null;
            var consumed: usize = 0;

            // Check for quoted display text
            if (std.mem.indexOf(u8, rest, "\"")) |quote_start| {
                // Find closing quote
                if (std.mem.indexOfPos(u8, rest, quote_start + 1, "\"")) |quote_end| {
                    target = std.mem.trim(u8, rest[0..quote_start], " \t");
                    display_text = rest[quote_start + 1 .. quote_end];
                    consumed = quote_end + 1;
                }
            }

            if (consumed == 0) {
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

                target = std.mem.trim(u8, rest[0..target_end], " \t");
                consumed = target_end;
            }

            // Try to resolve the reference
            if (self.symbol_table) |sym_table| {
                var resolver = xref.XRefResolver.init(sym_table, self.current_file, self.output_format);
                const ref_link = types.RefLink{
                    .target = target,
                    .display_text = display_text,
                };

                if (resolver.resolveRef(ref_link, pages)) |resolved| {
                    // Generate markdown link based on output format
                    const link_text = resolved.text;
                    const link_target = try self.generateRefLink(resolved);
                    defer self.allocator.free(link_target);

                    try self.writeString("[");
                    try self.writeString(link_text);
                    try self.writeString("](");
                    try self.writeString(link_target);
                    try self.writeString(")");
                } else {
                    // Reference not found - render as code with warning comment
                    try self.writeString("`");
                    try self.writeString(target);
                    try self.writeString("`");
                    // TODO: Add warning to stderr or log
                }
            } else {
                // No symbol table - render as code
                try self.writeString("`");
                try self.writeString(target);
                try self.writeString("`");
            }

            pos += consumed;
        }
    }

    /// Generates a link target for a resolved @ref
    fn generateRefLink(self: *Self, resolved: xref.XRefResolver.RefLinkResult) ![]const u8 {
        switch (resolved.kind) {
            .symbol => {
                // For symbols, link to the anchor in the target file
                if (self.output_format == .mdbook) {
                    // mdbook format: relative path to file + anchor
                    // TODO: Calculate proper relative path
                    return try std.fmt.allocPrint(self.allocator, "{s}.md#{s}", .{ resolved.target_file, resolved.anchor });
                } else {
                    // Single markdown file: just anchor
                    return try std.fmt.allocPrint(self.allocator, "#{s}", .{resolved.anchor});
                }
            },
            .page => {
                // For pages, link to the page file
                if (self.output_format == .mdbook) {
                    return try std.fmt.allocPrint(self.allocator, "{s}.md", .{resolved.target_file});
                } else {
                    return try std.fmt.allocPrint(self.allocator, "#{s}", .{resolved.anchor});
                }
            },
            .section, .anchor => {
                // For sections/anchors, link to the anchor
                return try std.fmt.allocPrint(self.allocator, "#{s}", .{resolved.anchor});
            },
        }
    }

    /// Writes a code block with optional Godbolt link
    fn writeCodeBlockWithGodbolt(self: *Self, code: []const u8, language: []const u8) !void {
        // Write code block
        try self.writeString("```");
        try self.writeString(language);
        try self.writeString("\n");
        try self.writeString(code);
        try self.writeString("\n```\n");

        // Add Godbolt link if enabled and language is C/C++
        if (self.cfg.godbolt.enabled and
            (std.mem.eql(u8, language, "c") or
                std.mem.eql(u8, language, "cpp") or
                std.mem.eql(u8, language, "c++")))
        {
            var gen = godbolt_mod.GodboltUrlGenerator.init(self.allocator);
            gen.setCompiler(self.cfg.godbolt.compiler);
            gen.setOptions(self.cfg.godbolt.options);

            const link = try gen.generateMarkdownLink(code, self.cfg.godbolt.link_text);
            defer self.allocator.free(link);

            try self.writeString("\n");
            try self.writeString(link);
            try self.writeString("\n");
        }

        try self.writeString("\n");
    }

    /// Extracts the base type name from a type string
    /// e.g., "const struct Point *" -> "Point"
    /// e.g., "const struct Point* a" -> "Point" (handles param name in type)
    /// e.g., "const Point2<T>" -> "Point2" (handles C++ templates)
    /// e.g., "spatial::Point2<T>" -> "Point2" (handles C++ namespaces)
    /// e.g., "std::vector<Point2<T>>" -> "vector" (handles nested templates)
    pub fn extractBaseType(type_str: []const u8) []const u8 {
        var result = type_str;

        // Strip leading const
        if (std.mem.startsWith(u8, result, "const ")) {
            result = result[6..];
        }

        // Strip leading struct/enum/union keywords
        if (std.mem.startsWith(u8, result, "struct ")) {
            result = result[7..];
        } else if (std.mem.startsWith(u8, result, "enum ")) {
            result = result[5..];
        } else if (std.mem.startsWith(u8, result, "union ")) {
            result = result[6..];
        }

        // Find the end of the type name (before * & space or <)
        // This handles cases like "Point* a" and "Point2<T>"
        var end: usize = 0;
        for (result, 0..) |c, i| {
            if (c == '*' or c == '&' or c == ' ' or c == '<') {
                break;
            }
            end = i + 1;
        }
        if (end > 0) {
            result = result[0..end];
        }

        // Strip namespace prefix (e.g., "std::vector" -> "vector", "spatial::Point2" -> "Point2")
        // Find the last :: and take everything after it
        if (std.mem.lastIndexOf(u8, result, "::")) |idx| {
            result = result[idx + 2 ..];
        }

        return result;
    }

    /// Writes a type with optional cross-reference link
    /// Uses HTML escaping for angle brackets (template types like Vec2<T>)
    fn writeTypeWithLink(self: *Self, type_str: []const u8) !void {
        if (self.symbol_table) |table| {
            // Extract base type for lookup
            const base_type = extractBaseType(type_str);

            if (table.lookup(base_type)) |info| {
                // Found a known symbol - generate a link
                const link = try self.generateLink(base_type, info);
                defer if (link.needs_free) self.allocator.free(link.text);

                // Write the type with the base type as a link
                // e.g., "const Point *" becomes "const [Point](#point) *"
                if (std.mem.indexOf(u8, type_str, base_type)) |start| {
                    // Write prefix (e.g., "const ") - escaped for HTML
                    if (start > 0) {
                        try self.writeEscaped(type_str[0..start]);
                    }
                    // Write linked type (link text is already safe)
                    try self.writeString(link.text);
                    // Write suffix (e.g., " *" or "<T>") - escaped for HTML
                    const end = start + base_type.len;
                    if (end < type_str.len) {
                        try self.writeEscaped(type_str[end..]);
                    }
                    return;
                }
            } else if (table.getExternalLink(base_type)) |ext_url| {
                // Found an external documentation link (e.g., std:: -> cppreference)
                defer self.allocator.free(ext_url);

                if (std.mem.indexOf(u8, type_str, base_type)) |start| {
                    // Write prefix (e.g., "const ")
                    if (start > 0) {
                        try self.writeEscaped(type_str[0..start]);
                    }
                    // Write external link
                    try self.writeString("[");
                    try self.writeEscaped(base_type);
                    try self.writeString("](");
                    try self.writeString(ext_url);
                    try self.writeString(")");
                    // Write suffix (e.g., " *" or "<T>")
                    const end = start + base_type.len;
                    if (end < type_str.len) {
                        try self.writeEscaped(type_str[end..]);
                    }
                    return;
                }
            }
        }
        // No cross-reference - write plain type with HTML escaping
        try self.writeEscaped(type_str);
    }

    /// Writes a symbol reference with optional cross-reference link (for @see tags)
    fn writeSymbolLink(self: *Self, symbol_name: []const u8) !void {
        if (self.symbol_table) |table| {
            if (table.lookup(symbol_name)) |info| {
                const link = try self.generateLink(symbol_name, info);
                defer if (link.needs_free) self.allocator.free(link.text);
                try self.writeString(link.text);
                return;
            } else if (table.getExternalLink(symbol_name)) |ext_url| {
                // Found an external documentation link (e.g., std::vector -> cppreference)
                defer self.allocator.free(ext_url);
                try self.writeString("[");
                try self.writeString(symbol_name);
                try self.writeString("](");
                try self.writeString(ext_url);
                try self.writeString(")");
                return;
            }
        }
        // No cross-reference - write as code
        try self.writeString("`");
        try self.writeString(symbol_name);
        try self.writeString("`");
    }

    const LinkResult = struct {
        text: []const u8,
        needs_free: bool,
    };

    /// Generates a markdown link for a symbol
    fn generateLink(self: *Self, symbol_name: []const u8, info: xref.SymbolInfo) !LinkResult {
        switch (self.output_format) {
            .markdown => {
                // Single file: use anchor links [name](#anchor)
                // Format: [symbol_name](#anchor)
                const link_len = 1 + symbol_name.len + 2 + 1 + info.anchor.len + 1; // [name](#anchor)
                const link_buf = try self.allocator.alloc(u8, link_len);
                _ = std.fmt.bufPrint(link_buf, "[{s}](#{s})", .{ symbol_name, info.anchor }) catch unreachable;
                return .{ .text = link_buf, .needs_free = true };
            },
            .mdbook => {
                // mdbook: use relative path links between sections
                // Types are in ../types/<file>.md, functions in ../functions/<file>.md
                const target_section = switch (info.kind) {
                    .struct_type, .class_type, .enum_type, .typedef => "types",
                    .function => "functions",
                    .macro => "macros",
                };

                // Get the target file basename (e.g., "include/spatial/geometry.hpp" -> "geometry")
                const target_file = self.getFileBasename(info.source_file);

                // Build the relative link: ../types/geometry.md#anchor
                // Max size: "../" + section + "/" + file + ".md#" + anchor
                const max_len = 3 + target_section.len + 1 + target_file.len + 4 + info.anchor.len;
                const link_buf = try self.allocator.alloc(u8, 1 + symbol_name.len + 2 + max_len + 1);

                const written = std.fmt.bufPrint(link_buf, "[{s}](../{s}/{s}.md#{s})", .{
                    symbol_name,
                    target_section,
                    target_file,
                    info.anchor,
                }) catch unreachable;
                _ = written;

                return .{ .text = link_buf, .needs_free = true };
            },
        }
    }

    /// Processes text and replaces @ref/\ref tags with markdown links
    /// @ref symbol -> [symbol](#symbol) or [symbol](path#anchor)
    /// @ref symbol "text" -> [text](#symbol)
    /// If target not found, renders as code: `symbol`
    fn processRefs(self: *Self, text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) {
            // Look for @ref or \ref
            const ref_start = blk: {
                if (i + 5 <= text.len and std.mem.eql(u8, text[i .. i + 5], "@ref ")) {
                    break :blk i;
                }
                if (i + 5 <= text.len and std.mem.eql(u8, text[i .. i + 5], "\\ref ")) {
                    break :blk i;
                }
                // No ref found at this position, write char and continue
                try self.buffer.append(self.allocator, text[i]);
                i += 1;
                continue;
            };

            // Found @ref, parse it
            i = ref_start + 5; // Skip "@ref " or "\ref "

            // Skip whitespace
            while (i < text.len and (text[i] == ' ' or text[i] == '\t')) {
                i += 1;
            }

            // Extract target (until space, quote, newline, or special chars)
            const target_start = i;
            while (i < text.len and text[i] != ' ' and text[i] != '"' and text[i] != '\n' and text[i] != '\r' and text[i] != ',' and text[i] != '.') {
                i += 1;
            }
            const target = text[target_start..i];

            // Check for optional display text in quotes
            var display_text: ?[]const u8 = null;
            // Look ahead for optional display text - skip spaces temporarily
            var look_ahead = i;
            while (look_ahead < text.len and text[look_ahead] == ' ') {
                look_ahead += 1;
            }
            if (look_ahead < text.len and text[look_ahead] == '"') {
                // Found a quote, advance to it
                i = look_ahead + 1; // Skip opening quote
                const display_start = i;
                while (i < text.len and text[i] != '"') {
                    i += 1;
                }
                display_text = text[display_start..i];
                if (i < text.len) i += 1; // Skip closing quote
            }
            // If no quote found, don't consume the space - it stays for the next iteration

            // Generate link
            const link_text = display_text orelse target;

            // Skip empty targets
            if (target.len == 0) {
                continue;
            }

            // Try to resolve target using symbol table
            if (self.symbol_table) |table| {
                if (table.lookup(target)) |info| {
                    const link = try self.generateLink(target, info);
                    defer if (link.needs_free) self.allocator.free(link.text);

                    // If we have custom display text, modify the link
                    if (display_text) |dt| {
                        try self.writeString("[");
                        try self.writeString(dt);
                        try self.writeString("](");
                        // Extract href from link - find the URL part
                        if (std.mem.indexOf(u8, link.text, "](")) |start| {
                            if (std.mem.lastIndexOf(u8, link.text, ")")) |end| {
                                try self.writeString(link.text[start + 2 .. end]);
                            }
                        }
                        try self.writeString(")");
                    } else {
                        try self.writeString(link.text);
                    }
                    continue;
                }
            }

            // Target not found - render as code
            try self.writeString("`");
            try self.writeString(link_text);
            try self.writeString("`");
        }
    }

    /// Formats template parameters as a signature string for code blocks
    /// e.g., "template<typename T, usize N>\n" or with requires clause
    fn formatTemplateSignature(self: *Self, template_params: []const types.TemplateParam) !void {
        try self.formatTemplateSignatureWithRequires(template_params, null);
    }

    /// Formats template parameters with optional requires clause
    /// e.g., "template<typename T>\nrequires std::integral<T>\n"
    fn formatTemplateSignatureWithRequires(self: *Self, template_params: []const types.TemplateParam, requires_clause: ?[]const u8) !void {
        if (template_params.len == 0) return;

        try self.writeString("template<");
        for (template_params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.writeString(param.kind);
            if (param.is_variadic) {
                try self.writeString("...");
            }
            try self.writeString(" ");
            try self.writeString(param.name);
            if (param.default_value) |default| {
                try self.writeString(" = ");
                try self.writeString(default);
            }
        }
        try self.writeString(">\n");

        // Add requires clause if present
        if (requires_clause) |req| {
            try self.writeString("requires ");
            try self.writeString(req);
            try self.writeString("\n");
        }
    }

    /// Formats template parameters as a short param list for headings
    /// e.g., "<T, N>" (with HTML escaping)
    fn formatTemplateParamList(self: *Self, template_params: []const types.TemplateParam) !void {
        if (template_params.len == 0) return;

        try self.writeString("&lt;");
        for (template_params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.writeString(param.name);
            if (param.is_variadic) {
                try self.writeString("...");
            }
        }
        try self.writeString("&gt;");
    }

    /// Writes C++ attributes in [[attr]] format for code blocks
    /// e.g., [[nodiscard]] [[deprecated("msg")]]
    fn writeAttributeList(self: *Self, attributes: []const types.Attribute) !void {
        for (attributes, 0..) |attr, i| {
            if (i > 0) try self.writeString(" ");
            try self.writeString("[[");
            try self.writeString(attr.name);
            if (attr.argument) |arg| {
                try self.writeString("(\"");
                try self.writeString(arg);
                try self.writeString("\")");
            }
            try self.writeString("]]");
        }
    }

    /// Writes attributes as a documentation section
    /// Handles special attributes like [[deprecated]] and [[nodiscard]]
    fn writeAttributesSection(self: *Self, attributes: []const types.Attribute) !void {
        if (attributes.len == 0) return;

        // Check for deprecated attribute - render as deprecation notice
        for (attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "deprecated")) {
                try self.writeString("> **Deprecated**");
                if (attr.argument) |arg| {
                    try self.writeString(": ");
                    try self.writeString(arg);
                }
                try self.writeString("\n\n");
            }
        }

        // Collect other attributes for display
        var has_other_attrs = false;
        for (attributes) |attr| {
            if (!std.mem.eql(u8, attr.name, "deprecated")) {
                has_other_attrs = true;
                break;
            }
        }

        if (has_other_attrs) {
            try self.writeString("**Attributes:** ");
            var first = true;
            for (attributes) |attr| {
                if (std.mem.eql(u8, attr.name, "deprecated")) continue;

                if (!first) try self.writeString(", ");
                first = false;

                try self.writeString("`[[");
                try self.writeString(attr.name);
                if (attr.argument) |arg| {
                    try self.writeString("(\"");
                    try self.writeString(arg);
                    try self.writeString("\")");
                }
                try self.writeString("]]`");
            }
            try self.writeString("\n\n");
        }
    }

    /// Gets the basename of a file path without extension
    /// e.g., "include/spatial/geometry.hpp" -> "geometry"
    fn getFileBasename(self: *Self, path: []const u8) []const u8 {
        _ = self;
        var result = path;

        // Get filename part (after last /)
        if (std.mem.lastIndexOfScalar(u8, result, '/')) |idx| {
            result = result[idx + 1 ..];
        }

        // Remove extension
        if (std.mem.lastIndexOfScalar(u8, result, '.')) |idx| {
            result = result[0..idx];
        }

        return result;
    }

    /// Writes the generated function signature (used when no @synopsis override)
    fn writeGeneratedSignature(self: *Self, func: types.Function, hide_return_type: bool) !void {
        // Write attributes on their own line if present
        if (func.attributes.len > 0) {
            try self.writeAttributeList(func.attributes);
            try self.writeString("\n");
        }
        try self.formatTemplateSignatureWithRequires(func.template_params, func.requires_clause);
        // Hide return type if @exclude return is specified
        if (hide_return_type) {
            try self.writeString("/* see below */ ");
        } else {
            try self.writeString(func.return_type);
            try self.writeString(" ");
        }
        try self.writeString(func.name);
        try self.writeString("(");

        for (func.params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.writeString(param.type_str);
            try self.writeString(" ");
            try self.writeString(param.name);
        }
        try self.writeString(");\n```\n\n");
    }

    /// Writes functions with group support - groups related functions together
    fn writeFunctionsWithGroups(self: *Self, functions: []const types.Function) !void {
        // Collect groups and ungrouped functions
        var groups = std.StringHashMap(std.ArrayList(types.Function)).init(self.allocator);
        defer {
            var it = groups.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.allocator);
            }
            groups.deinit();
        }

        var group_order: std.ArrayList([]const u8) = .empty;
        defer group_order.deinit(self.allocator);

        var group_headings = std.StringHashMap([]const u8).init(self.allocator);
        defer group_headings.deinit();

        var ungrouped: std.ArrayList(types.Function) = .empty;
        defer ungrouped.deinit(self.allocator);

        // Categorize functions
        for (functions) |func| {
            // Skip excluded functions (by @exclude, namespace blacklist, or pattern)
            if (self.shouldExclude(func.name, func.doc)) continue;

            if (func.doc) |doc| {
                if (doc.group) |group| {
                    // Add to group
                    const gop = try groups.getOrPut(group.name);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .empty;
                        try group_order.append(self.allocator, group.name);
                    }
                    try gop.value_ptr.append(self.allocator, func);

                    // Store heading if this is the first with a heading
                    if (group.heading) |heading| {
                        if (!group_headings.contains(group.name)) {
                            try group_headings.put(group.name, heading);
                        }
                    }
                    continue;
                }
            }
            // Ungrouped function
            try ungrouped.append(self.allocator, func);
        }

        // Write grouped functions first
        for (group_order.items) |group_name| {
            if (groups.get(group_name)) |group_funcs| {
                // Write group heading
                if (group_headings.get(group_name)) |heading| {
                    try self.writeString("### ");
                    try self.writeString(heading);
                    try self.writeString("\n\n");
                } else {
                    // Use group name as heading if no explicit heading
                    try self.writeString("### ");
                    try self.writeString(group_name);
                    try self.writeString("\n\n");
                }

                // Write all functions in the group
                for (group_funcs.items) |func| {
                    try self.writeFunctionInGroup(func);
                }
                try self.writeString("---\n\n");
            }
        }

        // Write ungrouped functions with output_section support
        var current_section: ?[]const u8 = null;
        for (ungrouped.items) |func| {
            // Check for output_section change
            const func_section = if (func.doc) |doc| doc.output_section else null;
            if (func_section) |section| {
                if (current_section == null or !std.mem.eql(u8, current_section.?, section)) {
                    // New section - write section header
                    try self.writeString("### ");
                    try self.writeString(section);
                    try self.writeString("\n\n");
                    current_section = section;
                }
            }
            try self.writeFunction(func);
        }
    }

    /// Writes a function that's part of a group (uses #### instead of ###)
    fn writeFunctionInGroup(self: *Self, func: types.Function) !void {
        // Check for return_type exclusion mode
        const hide_return_type = func.doc != null and func.doc.?.exclude == .return_type;

        // Function name as subheading (with template params if present)
        try self.writeString("#### `");
        try self.writeString(func.name);
        try self.formatTemplateParamList(func.template_params);
        try self.writeString("`\n\n");

        // Code block with signature
        try self.writeString("```cpp\n");

        // Check for synopsis override
        if (func.doc) |doc| {
            if (doc.synopsis_override) |synopsis| {
                try self.writeString(synopsis);
                try self.writeString("\n```\n\n");
            } else {
                try self.writeGeneratedSignature(func, hide_return_type);
            }
        } else {
            try self.writeGeneratedSignature(func, hide_return_type);
        }

        // Write documentation (brief only for grouped functions to keep it compact)
        if (func.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }

            // Parameters
            if (doc.params.len > 0) {
                try self.writeString("**Parameters:**\n");
                for (doc.params) |param| {
                    try self.writeString("- `");
                    try self.writeString(param.name);
                    try self.writeString("`: ");
                    try self.writeTextWithRefs(param.description, self.all_pages);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Return value
            if (doc.returns) |ret| {
                try self.writeString("**Returns:** ");
                try self.writeTextWithRefs(ret, self.all_pages);
                try self.writeString("\n\n");
            }
        }
    }

    fn writeFunction(self: *Self, func: types.Function) !void {
        // Check for return_type exclusion mode
        const hide_return_type = func.doc != null and func.doc.?.exclude == .return_type;

        // Function name as heading (with template params if present)
        try self.writeString("### `");
        try self.writeString(func.name);
        try self.formatTemplateParamList(func.template_params);
        try self.writeString("`\n\n");

        // Code block with signature (including attributes)
        try self.writeString("```cpp\n");

        // Check for synopsis override - use custom synopsis instead of generated one
        if (func.doc) |doc| {
            if (doc.synopsis_override) |synopsis| {
                try self.writeString(synopsis);
                try self.writeString("\n```\n\n");
            } else {
                // Generate normal signature
                try self.writeGeneratedSignature(func, hide_return_type);
            }
        } else {
            // No doc, generate normal signature
            try self.writeGeneratedSignature(func, hide_return_type);
        }

        // Render attributes as documentation section
        try self.writeAttributesSection(func.attributes);

        // Documentation
        if (func.doc) |doc| {
            if (doc.brief) |brief| {
                // Process @ref tags in brief
                if (extractor_mod.DocstringExtractor.containsRef(brief)) {
                    try self.processRefs(brief);
                } else {
                    try self.writeTextWithRefs(brief, self.all_pages);
                }
                try self.writeString("\n\n");
            }

            // Details section (includes inline examples, code blocks, etc.)
            if (doc.details) |details| {
                // Clean up the details - remove leading asterisks from each line
                var cleaned_lines: std.ArrayList(u8) = .empty;
                defer cleaned_lines.deinit(self.allocator);

                var lines_iter = std.mem.splitScalar(u8, details, '\n');
                var first = true;
                while (lines_iter.next()) |line| {
                    if (!first) {
                        try cleaned_lines.append(self.allocator, '\n');
                    }
                    first = false;

                    var content = std.mem.trim(u8, line, " \t\r");
                    // Strip leading asterisk if present
                    if (std.mem.startsWith(u8, content, "* ")) {
                        content = content[2..];
                    } else if (std.mem.startsWith(u8, content, "*")) {
                        content = content[1..];
                        content = std.mem.trimLeft(u8, content, " ");
                    }
                    try cleaned_lines.appendSlice(self.allocator, content);
                }

                if (cleaned_lines.items.len > 0) {
                    // Process @ref tags in details
                    if (extractor_mod.DocstringExtractor.containsRef(cleaned_lines.items)) {
                        try self.processRefs(cleaned_lines.items);
                    } else {
                        try self.writeString(cleaned_lines.items);
                    }
                    try self.writeString("\n\n");
                }
            }

            if (doc.params.len > 0) {
                try self.writeString("**Parameters:**\n");
                for (doc.params) |param| {
                    try self.writeString("- `");
                    try self.writeString(param.name);
                    try self.writeString("`");
                    // Try to find the type from the function signature
                    for (func.params) |fp| {
                        if (std.mem.eql(u8, fp.name, param.name)) {
                            try self.writeString(" (");
                            try self.writeTypeWithLink(fp.type_str);
                            try self.writeString(")");
                            break;
                        }
                    }
                    try self.writeString(": ");
                    // Process @ref tags in param description
                    if (extractor_mod.DocstringExtractor.containsRef(param.description)) {
                        try self.processRefs(param.description);
                    } else {
                        try self.writeTextWithRefs(param.description, self.all_pages);
                    }
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            if (doc.returns) |ret| {
                try self.writeString("**Returns:** ");
                // Add return type with link if it's a known type
                try self.writeString("(");
                try self.writeTypeWithLink(func.return_type);
                try self.writeString(") ");
                // Process @ref tags in return description
                if (extractor_mod.DocstringExtractor.containsRef(ret)) {
                    try self.processRefs(ret);
                } else {
                    try self.writeTextWithRefs(ret, self.all_pages);
                }
                try self.writeString("\n\n");
            }

            // Return values (@retval)
            if (doc.retvals.len > 0) {
                try self.writeString("**Return Values:**\n");
                for (doc.retvals) |retval| {
                    try self.writeString("- `");
                    try self.writeString(retval.value);
                    try self.writeString("`");
                    if (retval.description.len > 0) {
                        try self.writeString(": ");
                        // Process @ref tags in retval description
                        if (extractor_mod.DocstringExtractor.containsRef(retval.description)) {
                            try self.processRefs(retval.description);
                        } else {
                            try self.writeString(retval.description);
                        }
                    }
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Exceptions
            if (doc.exceptions.len > 0) {
                try self.writeString("**Throws:**\n");
                for (doc.exceptions) |exc| {
                    try self.writeString("- `");
                    try self.writeString(exc.exception_type);
                    try self.writeString("`: ");
                    try self.writeString(exc.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Preconditions
            if (doc.preconditions.len > 0) {
                try self.writeString("**Preconditions:**\n");
                for (doc.preconditions) |pre| {
                    try self.writeString("- ");
                    try self.writeString(pre);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Postconditions
            if (doc.postconditions.len > 0) {
                try self.writeString("**Postconditions:**\n");
                for (doc.postconditions) |post| {
                    try self.writeString("- ");
                    try self.writeString(post);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // C++ Standard-style sections
            if (doc.effects) |effects| {
                try self.writeString("*Effects:* ");
                try self.writeString(effects);
                try self.writeString("\n\n");
            }

            if (doc.requires) |requires| {
                try self.writeString("*Requires:* ");
                try self.writeString(requires);
                try self.writeString("\n\n");
            }

            if (doc.complexity) |complexity| {
                try self.writeString("*Complexity:* ");
                try self.writeString(complexity);
                try self.writeString("\n\n");
            }

            if (doc.remarks.len > 0) {
                for (doc.remarks) |remark| {
                    try self.writeString("*Remarks:* ");
                    try self.writeString(remark);
                    try self.writeString("\n\n");
                }
            }

            if (doc.sync) |sync| {
                try self.writeString("*Thread Safety:* ");
                try self.writeString(sync);
                try self.writeString("\n\n");
            }

            if (doc.invariants.len > 0) {
                try self.writeString("**Invariants:**\n");
                for (doc.invariants) |inv| {
                    try self.writeString("- ");
                    try self.writeString(inv);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Group membership
            if (doc.ingroup) |group| {
                try self.writeString("**Group:** `");
                try self.writeString(group);
                try self.writeString("`\n\n");
            }

            if (doc.deprecated) |dep| {
                try self.writeString("> **Deprecated:** ");
                try self.writeString(dep);
                try self.writeString("\n\n");
            }

            // Notes
            if (doc.notes.len > 0) {
                for (doc.notes) |note| {
                    try self.writeString("> **Note:** ");
                    try self.writeString(note);
                    try self.writeString("\n\n");
                }
            }

            // Warnings
            if (doc.warnings.len > 0) {
                for (doc.warnings) |warning| {
                    try self.writeString("> **Warning:** ");
                    try self.writeString(warning);
                    try self.writeString("\n\n");
                }
            }

            // Attention notices
            if (doc.attention.len > 0) {
                for (doc.attention) |att| {
                    try self.writeString("> ⚠️ **Attention:** ");
                    try self.writeString(att);
                    try self.writeString("\n\n");
                }
            }

            // Important notices
            if (doc.important.len > 0) {
                for (doc.important) |imp| {
                    try self.writeString("> ❗ **Important:** ");
                    try self.writeString(imp);
                    try self.writeString("\n\n");
                }
            }

            // Examples
            if (doc.examples.len > 0) {
                try self.writeString("**Examples:**\n\n");
                for (doc.examples) |example| {
                    // Check if it's a file reference or inline code
                    if (std.mem.indexOf(u8, example, "\n") == null and
                        (std.mem.endsWith(u8, example, ".c") or
                            std.mem.endsWith(u8, example, ".h") or
                            std.mem.endsWith(u8, example, ".cpp") or
                            std.mem.endsWith(u8, example, ".hpp") or
                            std.mem.indexOf(u8, example, ":") != null))
                    {
                        // File reference - output as include directive for mdbook
                        try self.writeString("```c\n{{#include ");
                        try self.writeString(example);
                        try self.writeString("}}\n```\n\n");
                    } else {
                        // Inline code
                        try self.writeCodeBlockWithGodbolt(example, "c");
                    }
                }
            }

            // Snippets (@snippet external code inclusion)
            if (doc.snippets.len > 0) {
                // Only write Examples header if we didn't already have examples
                if (doc.examples.len == 0) {
                    try self.writeString("**Examples:**\n\n");
                }
                for (doc.snippets) |snippet_ref| {
                    if (self.snippet_extractor) |extractor| {
                        if (extractor.extract(snippet_ref)) |code| {
                            const lang = snippet_mod.SnippetExtractor.getLanguage(snippet_ref);
                            try self.writeCodeBlockWithGodbolt(code, lang);
                        } else |err| {
                            // Show error placeholder
                            try self.writeString("```\n// Snippet not found: ");
                            try self.writeString(snippet_ref.file);
                            try self.writeString(" [");
                            try self.writeString(snippet_ref.anchor);
                            try self.writeString("]\n// Error: ");
                            try self.writeString(snippet_mod.SnippetExtractor.errorDescription(err));
                            try self.writeString("\n```\n\n");
                        }
                    } else {
                        // No extractor available, show reference
                        try self.writeString("```\n// See: ");
                        try self.writeString(snippet_ref.file);
                        try self.writeString(" [");
                        try self.writeString(snippet_ref.anchor);
                        try self.writeString("]\n```\n\n");
                    }
                }
            }

            // See also - with cross-reference links
            if (doc.see_also.len > 0) {
                try self.writeString("**See also:** ");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeSymbolLink(ref);
                }
                try self.writeString("\n\n");
            }

            // Tests
            if (doc.tests.len > 0) {
                try self.writeString("**Tests:** ");
                for (doc.tests, 0..) |test_ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeString("`");
                    try self.writeString(test_ref.name);
                    try self.writeString("`");
                }
                try self.writeString("\n\n");
            }

            // Since version
            if (doc.since) |since| {
                try self.writeString("**Since:** ");
                try self.writeString(since);
                try self.writeString("\n\n");
            }

            // TODOs
            if (doc.todos.len > 0) {
                try self.writeString("> **TODO:**\n");
                for (doc.todos) |todo| {
                    try self.writeString("> - ");
                    try self.writeString(todo.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Bugs
            if (doc.bugs.len > 0) {
                try self.writeString("> **Known Bugs:**\n");
                for (doc.bugs) |bug| {
                    try self.writeString("> - ");
                    try self.writeString(bug.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Date/History
            if (doc.dates.len > 0) {
                if (doc.dates.len == 1) {
                    try self.writeString("**Date:** ");
                    try self.writeString(doc.dates[0].date);
                    if (doc.dates[0].description) |desc| {
                        try self.writeString(" (");
                        try self.writeString(desc);
                        try self.writeString(")");
                    }
                    try self.writeString("\n\n");
                } else {
                    try self.writeString("**History:**\n");
                    for (doc.dates) |date_info| {
                        try self.writeString("- ");
                        try self.writeString(date_info.date);
                        if (date_info.description) |desc| {
                            try self.writeString(": ");
                            try self.writeString(desc);
                        }
                        try self.writeString("\n");
                    }
                    try self.writeString("\n");
                }
            }

            // Copyright
            if (doc.copyright) |copyright| {
                try self.writeString("**Copyright:** ");
                try self.writeString(copyright);
                try self.writeString("\n\n");
            }

            // Mermaid diagrams
            if (doc.mermaid_diagrams.len > 0) {
                for (doc.mermaid_diagrams) |diagram| {
                    if (diagram.caption) |caption| {
                        try self.writeString("**");
                        try self.writeString(caption);
                        try self.writeString("**\n\n");
                    }
                    try self.writeString("```mermaid\n");
                    try self.writeString(diagram.content);
                    try self.writeString("\n```\n\n");
                }
            }

            // Code blocks
            if (doc.code_blocks.len > 0) {
                for (doc.code_blocks) |block| {
                    const lang = block.language orelse "cpp";
                    try self.writeCodeBlockWithGodbolt(block.content, lang);
                }
            }
        }

        // Template parameters (merge parsed params with @tparam docs)
        if (func.template_params.len > 0 or (func.doc != null and func.doc.?.tparams.len > 0)) {
            try self.writeString("**Template Parameters:**\n");
            for (func.template_params) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                if (param.is_variadic) {
                    try self.writeString("...");
                }
                try self.writeString("` (");
                try self.writeString(param.kind);
                if (param.is_variadic) {
                    try self.writeString("...");
                }
                try self.writeString(")");
                if (param.default_value) |default| {
                    try self.writeString(" = `");
                    try self.writeString(default);
                    try self.writeString("`");
                }
                // Look for @tparam documentation for this parameter
                if (func.doc) |doc| {
                    for (doc.tparams) |tparam| {
                        if (std.mem.eql(u8, tparam.name, param.name)) {
                            if (tparam.description.len > 0) {
                                try self.writeString(": ");
                                try self.writeString(tparam.description);
                            }
                            break;
                        }
                    }
                }
                try self.writeString("\n");
            }
            try self.writeString("\n");
        }

        try self.writeString("---\n\n");
    }

    fn writeStruct(self: *Self, s: types.Struct) !void {
        // Struct name as heading
        try self.writeString("### `");
        try self.writeString(s.name);
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```c\nstruct ");
        try self.writeString(s.name);
        try self.writeString(" {\n");

        for (s.fields) |field| {
            try self.writeString("    ");
            try self.writeString(field.type_str);
            try self.writeString(" ");
            try self.writeString(field.name);
            try self.writeString(";\n");
        }
        try self.writeString("};\n```\n\n");

        // Documentation
        if (s.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
        }

        // Fields documentation with type links
        if (s.fields.len > 0) {
            try self.writeString("**Fields:**\n");
            for (s.fields) |field| {
                try self.writeString("- `");
                try self.writeString(field.name);
                try self.writeString("` (");
                try self.writeTypeWithLink(field.type_str);
                try self.writeString(")");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeString("\n");
        }

        try self.writeString("---\n\n");
    }

    fn writeUnion(self: *Self, u: types.Union) !void {
        // Union name as heading
        try self.writeString("### `");
        try self.writeString(u.name);
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```c\nunion ");
        try self.writeString(u.name);
        try self.writeString(" {\n");

        for (u.fields) |field| {
            try self.writeString("    ");
            try self.writeString(field.type_str);
            try self.writeString(" ");
            try self.writeString(field.name);
            try self.writeString(";\n");
        }
        try self.writeString("};\n```\n\n");

        // Documentation
        if (u.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
        }

        // Fields documentation with type links
        if (u.fields.len > 0) {
            try self.writeString("**Fields:**\n");
            for (u.fields) |field| {
                try self.writeString("- `");
                try self.writeString(field.name);
                try self.writeString("` (");
                try self.writeTypeWithLink(field.type_str);
                try self.writeString(")");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeString("\n");
        }

        try self.writeString("---\n\n");
    }

    fn writeEnum(self: *Self, e: types.Enum) !void {
        // Enum name as heading
        try self.writeString("### `");
        try self.writeString(e.name);
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```c\nenum ");
        try self.writeString(e.name);
        try self.writeString(" {\n");

        for (e.values) |val| {
            try self.writeString("    ");
            try self.writeString(val.name);
            if (val.value) |v| {
                var buf: [32]u8 = undefined;
                const num_str = std.fmt.bufPrint(&buf, " = {d}", .{v}) catch "";
                try self.writeString(num_str);
            }
            try self.writeString(",\n");
        }
        try self.writeString("};\n```\n\n");

        // Documentation
        if (e.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
        }

        // Values documentation
        var has_docs = false;
        for (e.values) |val| {
            if (val.doc != null) {
                has_docs = true;
                break;
            }
        }

        if (has_docs) {
            try self.writeString("**Values:**\n");
            for (e.values) |val| {
                try self.writeString("- `");
                try self.writeString(val.name);
                try self.writeString("`");
                if (val.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeString("\n");
        }

        try self.writeString("---\n\n");
    }

    fn writeTypedef(self: *Self, td: types.Typedef) !void {
        // Typedef name as heading
        try self.writeString("### `");
        try self.writeString(td.name);
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```c\ntypedef ");
        try self.writeString(td.underlying);
        try self.writeString(" ");
        try self.writeString(td.name);
        try self.writeString(";\n```\n\n");

        // Documentation
        if (td.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
        }

        try self.writeString("---\n\n");
    }

    fn writeMacro(self: *Self, macro: types.Macro) !void {
        // Macro name as heading
        try self.writeString("### `");
        try self.writeString(macro.name);
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```c\n#define ");
        try self.writeString(macro.name);

        // Parameters for function-like macros
        if (macro.params) |params| {
            try self.writeString("(");
            for (params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param);
            }
            try self.writeString(")");
        }

        // Body
        if (macro.body.len > 0) {
            try self.writeString(" ");
            try self.writeString(macro.body);
        }
        try self.writeString("\n```\n\n");

        // Documentation
        if (macro.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }

            // Parameters for function-like macros
            if (doc.params.len > 0) {
                try self.writeString("**Parameters:**\n");
                for (doc.params) |param| {
                    try self.writeString("- `");
                    try self.writeString(param.name);
                    try self.writeString("`: ");
                    try self.writeTextWithRefs(param.description, self.all_pages);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Notes
            if (doc.notes.len > 0) {
                for (doc.notes) |note| {
                    try self.writeString("> **Note:** ");
                    try self.writeString(note);
                    try self.writeString("\n\n");
                }
            }

            // Warnings
            if (doc.warnings.len > 0) {
                for (doc.warnings) |warning| {
                    try self.writeString("> **Warning:** ");
                    try self.writeString(warning);
                    try self.writeString("\n\n");
                }
            }

            // See also
            if (doc.see_also.len > 0) {
                try self.writeString("**See also:** ");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeSymbolLink(ref);
                }
                try self.writeString("\n\n");
            }

            // TODOs
            if (doc.todos.len > 0) {
                try self.writeString("> **TODO:**\n");
                for (doc.todos) |todo| {
                    try self.writeString("> - ");
                    try self.writeString(todo.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Bugs
            if (doc.bugs.len > 0) {
                try self.writeString("> **Known Bugs:**\n");
                for (doc.bugs) |bug| {
                    try self.writeString("> - ");
                    try self.writeString(bug.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }
        }

        try self.writeString("---\n\n");
    }

    fn writeClass(self: *Self, class: types.Class) !void {
        // Class name as heading (with template params if present)
        try self.writeString("### `");
        try self.writeString(class.name);
        try self.formatTemplateParamList(class.template_params);
        try self.writeString("`\n\n");

        // Inheritance line (before code block)
        if (class.base_classes.len > 0) {
            try self.writeString("**Inherits from:** ");
            for (class.base_classes, 0..) |base, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeTypeWithLink(base.name);
                try self.writeString(" (");
                switch (base.access) {
                    .public => try self.writeString("public"),
                    .protected => try self.writeString("protected"),
                    .private => try self.writeString("private"),
                }
                if (base.is_virtual) {
                    try self.writeString(" virtual");
                }
                try self.writeString(")");
            }
            try self.writeString("\n\n");
        }

        // Generate inheritance diagram if class participates in inheritance
        if (self.all_classes) |classes| {
            try self.writeInheritanceDiagram(class, classes);
        }

        // Code block with class definition
        try self.writeString("```cpp\n");
        // Write attributes on their own line if present
        if (class.attributes.len > 0) {
            try self.writeAttributeList(class.attributes);
            try self.writeString("\n");
        }
        try self.formatTemplateSignatureWithRequires(class.template_params, class.requires_clause);
        try self.writeString("class ");
        try self.writeString(class.name);

        // Add base classes to synopsis
        if (class.base_classes.len > 0) {
            try self.writeString(" : ");
            for (class.base_classes, 0..) |base, i| {
                if (i > 0) try self.writeString(", ");
                switch (base.access) {
                    .public => try self.writeString("public "),
                    .protected => try self.writeString("protected "),
                    .private => try self.writeString("private "),
                }
                if (base.is_virtual) {
                    try self.writeString("virtual ");
                }
                try self.writeString(base.name);
            }
        }

        try self.writeString(" {\n");

        // Group fields and methods by access specifier
        const access_order = [_]types.AccessSpecifier{ .public, .protected, .private };
        const access_names = [_][]const u8{ "public", "protected", "private" };

        for (access_order, 0..) |access, idx| {
            var has_members = false;

            // Check if there are any members with this access level
            for (class.fields) |field| {
                if (field.access == access) {
                    has_members = true;
                    break;
                }
            }
            if (!has_members) {
                for (class.methods) |method| {
                    if (method.access == access) {
                        has_members = true;
                        break;
                    }
                }
            }

            if (has_members) {
                try self.writeString(access_names[idx]);
                try self.writeString(":\n");

                // Write fields
                for (class.fields) |field| {
                    if (field.access == access) {
                        try self.writeString("    ");
                        try self.writeString(field.type_str);
                        try self.writeString(" ");
                        try self.writeString(field.name);
                        try self.writeString(";\n");
                    }
                }

                // Write methods
                for (class.methods) |method| {
                    if (method.access == access) {
                        try self.writeString("    ");
                        if (method.is_virtual) try self.writeString("virtual ");
                        if (method.is_static) try self.writeString("static ");
                        try self.writeString(method.return_type);
                        try self.writeString(" ");
                        try self.writeString(method.name);
                        try self.writeString("(");
                        for (method.params, 0..) |param, i| {
                            if (i > 0) try self.writeString(", ");
                            try self.writeString(param.type_str);
                            try self.writeString(" ");
                            try self.writeString(param.name);
                        }
                        try self.writeString(")");
                        if (method.is_const) try self.writeString(" const");
                        if (method.is_override) try self.writeString(" override");
                        if (method.is_final) try self.writeString(" final");
                        if (method.is_pure_virtual) {
                            try self.writeString(" = 0");
                        }
                        try self.writeString(";\n");
                    }
                }
            }
        }

        try self.writeString("};\n```\n\n");

        // Render attributes as documentation section
        try self.writeAttributesSection(class.attributes);

        // Documentation
        if (class.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }

            if (doc.details) |details| {
                try self.writeTextWithRefs(details, self.all_pages);
                try self.writeString("\n\n");
            }

            // See also
            if (doc.see_also.len > 0) {
                try self.writeString("**See also:** ");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeSymbolLink(ref);
                }
                try self.writeString("\n\n");
            }

            // Invariants (class invariants from @invariant tags)
            if (doc.invariants.len > 0) {
                try self.writeString("**Invariants:**\n");
                for (doc.invariants) |inv| {
                    try self.writeString("- ");
                    try self.writeString(inv);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // TODOs
            if (doc.todos.len > 0) {
                try self.writeString("> **TODO:**\n");
                for (doc.todos) |todo| {
                    try self.writeString("> - ");
                    try self.writeString(todo.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Bugs
            if (doc.bugs.len > 0) {
                try self.writeString("> **Known Bugs:**\n");
                for (doc.bugs) |bug| {
                    try self.writeString("> - ");
                    try self.writeString(bug.description);
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Mermaid diagrams
            if (doc.mermaid_diagrams.len > 0) {
                for (doc.mermaid_diagrams) |diagram| {
                    if (diagram.caption) |caption| {
                        try self.writeString("**");
                        try self.writeString(caption);
                        try self.writeString("**\n\n");
                    }
                    try self.writeString("```mermaid\n");
                    try self.writeString(diagram.content);
                    try self.writeString("\n```\n\n");
                }
            }

            // Code blocks
            if (doc.code_blocks.len > 0) {
                for (doc.code_blocks) |block| {
                    const lang = block.language orelse "cpp";
                    try self.writeCodeBlockWithGodbolt(block.content, lang);
                }
            }
        }

        // Template parameters (merge parsed params with @tparam docs)
        if (class.template_params.len > 0 or (class.doc != null and class.doc.?.tparams.len > 0)) {
            try self.writeString("**Template Parameters:**\n");
            for (class.template_params) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                if (param.is_variadic) {
                    try self.writeString("...");
                }
                try self.writeString("` (");
                try self.writeString(param.kind);
                if (param.is_variadic) {
                    try self.writeString("...");
                }
                try self.writeString(")");
                if (param.default_value) |default| {
                    try self.writeString(" = `");
                    try self.writeString(default);
                    try self.writeString("`");
                }
                // Look for @tparam documentation for this parameter
                if (class.doc) |doc| {
                    for (doc.tparams) |tparam| {
                        if (std.mem.eql(u8, tparam.name, param.name)) {
                            if (tparam.description.len > 0) {
                                try self.writeString(": ");
                                try self.writeString(tparam.description);
                            }
                            break;
                        }
                    }
                }
                try self.writeString("\n");
            }
            try self.writeString("\n");
        }

        // Document public methods
        var has_public_methods = false;
        for (class.methods) |method| {
            if (method.access == .public) {
                has_public_methods = true;
                break;
            }
        }

        if (has_public_methods) {
            try self.writeString("**Public Methods:**\n\n");
            for (class.methods) |method| {
                if (method.access == .public) {
                    try self.writeString("- `");
                    try self.writeString(method.name);
                    try self.writeString("(");
                    for (method.params, 0..) |param, i| {
                        if (i > 0) try self.writeString(", ");
                        try self.writeEscaped(param.type_str);
                    }
                    try self.writeString(")`");
                    if (method.doc) |doc| {
                        if (doc.brief) |brief| {
                            try self.writeString(": ");
                            try self.writeTextWithRefs(brief, self.all_pages);
                        }
                    }
                    try self.writeString("\n");
                }
            }
            try self.writeString("\n");
        }

        // Nested Types section
        if (class.nested_classes.len > 0 or class.nested_enums.len > 0) {
            try self.writeString("**Nested Types:**\n\n");

            // Nested classes
            if (class.nested_classes.len > 0) {
                try self.writeString("*Classes:*\n");
                for (class.nested_classes) |nested_class| {
                    try self.writeString("- `");
                    try self.writeString(nested_class.name);
                    try self.writeString("`");
                    if (nested_class.doc) |doc| {
                        if (doc.brief) |brief| {
                            try self.writeString(" - ");
                            try self.writeTextWithRefs(brief, self.all_pages);
                        }
                    }
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }

            // Nested enums
            if (class.nested_enums.len > 0) {
                try self.writeString("*Enums:*\n");
                for (class.nested_enums) |nested_enum| {
                    try self.writeString("- `");
                    try self.writeString(nested_enum.name);
                    try self.writeString("`");
                    // Show enum values
                    if (nested_enum.values.len > 0) {
                        try self.writeString(" - ");
                        for (nested_enum.values, 0..) |val, i| {
                            if (i > 0) try self.writeString(", ");
                            try self.writeString(val.name);
                        }
                    }
                    try self.writeString("\n");
                }
                try self.writeString("\n");
            }
        }

        // Friends section
        if (class.friends.len > 0) {
            try self.writeString("**Friends:**\n\n");

            // Friend classes
            var has_friend_classes = false;
            for (class.friends) |friend| {
                if (friend.kind == .class) {
                    has_friend_classes = true;
                    break;
                }
            }
            if (has_friend_classes) {
                try self.writeString("*Classes:*\n");
                for (class.friends) |friend| {
                    if (friend.kind == .class) {
                        try self.writeString("- ");
                        try self.writeTypeWithLink(friend.name);
                        try self.writeString("\n");
                    }
                }
                try self.writeString("\n");
            }

            // Friend functions
            var has_friend_functions = false;
            for (class.friends) |friend| {
                if (friend.kind == .function) {
                    has_friend_functions = true;
                    break;
                }
            }
            if (has_friend_functions) {
                try self.writeString("*Functions:*\n");
                for (class.friends) |friend| {
                    if (friend.kind == .function) {
                        try self.writeString("- `");
                        if (friend.signature) |sig| {
                            try self.writeString(sig);
                        } else {
                            try self.writeString(friend.name);
                            try self.writeString("()");
                        }
                        try self.writeString("`\n");
                    }
                }
                try self.writeString("\n");
            }
        }

        try self.writeString("---\n\n");
    }

    /// Extracts the simple class name from a potentially qualified name
    /// e.g., "spatial::Shape<T>" -> "Shape", "std::vector<int>" -> "vector"
    fn extractSimpleClassName(name: []const u8) []const u8 {
        var result = name;

        // Strip namespace prefix (find last ::)
        if (std.mem.lastIndexOf(u8, result, "::")) |idx| {
            result = result[idx + 2 ..];
        }

        // Strip template parameters (find first <)
        if (std.mem.indexOf(u8, result, "<")) |idx| {
            result = result[0..idx];
        }

        return result;
    }

    /// Checks if a base class name matches a class name
    /// Handles namespace prefixes and template parameters
    fn baseClassMatches(base_name: []const u8, class_name: []const u8) bool {
        const base_simple = extractSimpleClassName(base_name);
        const class_simple = extractSimpleClassName(class_name);
        return std.mem.eql(u8, base_simple, class_simple);
    }

    /// Generates a Mermaid class diagram showing inheritance hierarchy
    fn writeInheritanceDiagram(self: *Self, class: types.Class, all_classes: []const types.Class) !void {
        // Only generate if class has base classes or is a base for other classes
        if (class.base_classes.len == 0) {
            // Check if any class inherits from this one
            var has_children = false;
            for (all_classes) |other| {
                for (other.base_classes) |base| {
                    if (baseClassMatches(base.name, class.name)) {
                        has_children = true;
                        break;
                    }
                }
                if (has_children) break;
            }
            if (!has_children) return;
        }

        try self.writeString("#### Inheritance Diagram\n\n");
        try self.writeString("```mermaid\nclassDiagram\n");

        // Write the current class
        try self.writeClassNode(class);

        // Write base classes
        for (class.base_classes) |base| {
            // Find base class in all_classes to get its details
            var found_base = false;
            for (all_classes) |base_class| {
                if (baseClassMatches(base.name, base_class.name)) {
                    try self.writeClassNode(base_class);
                    found_base = true;
                    break;
                }
            }
            // If base class not found in our list, still add it as a simple node
            if (!found_base) {
                try self.writeString("    class ");
                try self.writeString(base.name);
                try self.writeString("\n");
            }
        }

        // Write inheritance relationships for base classes
        for (class.base_classes) |base| {
            try self.writeString("    ");
            try self.writeString(base.name);
            try self.writeString(" <|-- ");
            try self.writeString(extractSimpleClassName(class.name));
            if (base.is_virtual) {
                try self.writeString(" : virtual");
            }
            try self.writeString("\n");
        }

        // Write child classes (classes that inherit from this one)
        for (all_classes) |other| {
            // Skip if it's the same class
            if (std.mem.eql(u8, other.name, class.name)) continue;

            for (other.base_classes) |base| {
                if (baseClassMatches(base.name, class.name)) {
                    try self.writeClassNode(other);
                    try self.writeString("    ");
                    try self.writeString(extractSimpleClassName(class.name));
                    try self.writeString(" <|-- ");
                    try self.writeString(extractSimpleClassName(other.name));
                    if (base.is_virtual) {
                        try self.writeString(" : virtual");
                    }
                    try self.writeString("\n");
                    break;
                }
            }
        }

        try self.writeString("```\n\n");
    }

    /// Writes a class node for the Mermaid diagram
    fn writeClassNode(self: *Self, class: types.Class) !void {
        try self.writeString("    class ");
        // Use simple class name for Mermaid (avoids issues with :: in names)
        try self.writeString(extractSimpleClassName(class.name));

        // Check if abstract (has pure virtual methods)
        var is_abstract = false;
        for (class.methods) |method| {
            if (method.is_pure_virtual) {
                is_abstract = true;
                break;
            }
        }

        if (is_abstract) {
            try self.writeString(" {\n        <<abstract>>\n    }\n");
        } else {
            try self.writeString("\n");
        }
    }

    fn writeConcept(self: *Self, concept: types.Concept) !void {
        // Concept name as heading
        try self.writeString("### `");
        try self.writeString(concept.name);
        // Add template parameters to heading if present
        if (concept.template_params.len > 0) {
            try self.writeString("&lt;");
            for (concept.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.name);
            }
            try self.writeString("&gt;");
        }
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```cpp\n");
        // Add template declaration
        if (concept.template_params.len > 0) {
            try self.writeString("template<");
            for (concept.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.kind);
                try self.writeString(" ");
                try self.writeString(param.name);
            }
            try self.writeString(">\n");
        }
        try self.writeString("concept ");
        try self.writeString(concept.name);
        try self.writeString(" = ");
        try self.writeString(concept.constraint);
        try self.writeString(";\n```\n\n");

        // Documentation
        if (concept.docstring) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }

            if (doc.details) |details| {
                try self.writeTextWithRefs(details, self.all_pages);
                try self.writeString("\n\n");
            }

            // See also
            if (doc.see_also.len > 0) {
                try self.writeString("**See also:** ");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeSymbolLink(ref);
                }
                try self.writeString("\n\n");
            }
        }

        try self.writeString("---\n\n");
    }

    fn writeTypeAlias(self: *Self, alias: types.TypeAlias) !void {
        // Type alias name as heading
        try self.writeString("### `");
        try self.writeString(alias.name);
        // Add template parameters to heading if present
        if (alias.template_params.len > 0) {
            try self.writeString("&lt;");
            for (alias.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.name);
            }
            try self.writeString("&gt;");
        }
        try self.writeString("`\n\n");

        // Code block with definition
        try self.writeString("```cpp\n");
        // Add template declaration if present
        if (alias.template_params.len > 0) {
            try self.writeString("template<");
            for (alias.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.kind);
                try self.writeString(" ");
                try self.writeString(param.name);
            }
            try self.writeString(">\n");
        }
        try self.writeString("using ");
        try self.writeString(alias.name);
        try self.writeString(" = ");
        try self.writeString(alias.underlying_type);
        try self.writeString(";\n```\n\n");

        // "Alias for" line with link to underlying type
        try self.writeString("Alias for ");
        try self.writeTypeWithLink(alias.underlying_type);
        try self.writeString("\n\n");

        // Documentation
        if (alias.docstring) |doc| {
            if (doc.brief) |brief| {
                try self.writeTextWithRefs(brief, self.all_pages);
                try self.writeString("\n\n");
            }
        }

        try self.writeString("---\n\n");
    }
};

// Tests
test "generate markdown for function" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "add",
                .return_type = "int",
                .params = &[_]types.Parameter{
                    .{ .name = "a", .type_str = "int" },
                    .{ .name = "b", .type_str = "int" },
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "### `add`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "int add(int a, int b)") != null);
}

test "generate markdown for struct" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{
            .{
                .name = "Point",
                .fields = &[_]types.StructField{
                    .{ .name = "x", .type_str = "int", .doc = "X coordinate" },
                    .{ .name = "y", .type_str = "int", .doc = "Y coordinate" },
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "### `Point`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "struct Point") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "int x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "X coordinate") != null);
}

test "generate markdown for enum" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{
            .{
                .name = "Color",
                .values = &[_]types.EnumValue{
                    .{ .name = "RED", .value = 0, .doc = "Red color" },
                    .{ .name = "GREEN", .value = 1, .doc = "Green color" },
                    .{ .name = "BLUE", .value = 2, .doc = "Blue color" },
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "### `Color`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "enum Color") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "RED = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Red color") != null);
}

test "generate markdown for typedef" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{
            .{
                .name = "uint32",
                .underlying = "unsigned int",
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "### `uint32`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "typedef unsigned int uint32") != null);
}

test "generate markdown with function documentation" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "multiply",
                .return_type = "int",
                .params = &[_]types.Parameter{
                    .{ .name = "x", .type_str = "int" },
                    .{ .name = "y", .type_str = "int" },
                },
                .doc = types.DocString{
                    .raw = "",
                    .brief = "Multiplies two integers.",
                    .params = &[_]types.ParamDoc{
                        .{ .name = "x", .description = "First factor" },
                        .{ .name = "y", .description = "Second factor" },
                    },
                    .returns = "Product of x and y",
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "Multiplies two integers.") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "**Parameters:**") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "`x`: First factor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "**Returns:**") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Product of x and y") != null);
}

test "generate markdown with deprecated function" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "old_func",
                .return_type = "void",
                .params = &[_]types.Parameter{},
                .doc = types.DocString{
                    .raw = "",
                    .brief = "Old function.",
                    .deprecated = "Use new_func() instead.",
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "**Deprecated:**") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Use new_func() instead.") != null);
}

test "generate markdown for empty module" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "empty.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "# empty.h") != null);
    // Should not have section headers for empty sections
    try std.testing.expect(std.mem.indexOf(u8, output, "## Functions") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Structures") == null);
}

test "generate markdown header" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "my_library.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.startsWith(u8, output, "# my_library.h\n"));
}

test "extract base type" {
    try std.testing.expectEqualStrings("Point", MarkdownGenerator.extractBaseType("Point"));
    try std.testing.expectEqualStrings("Point", MarkdownGenerator.extractBaseType("Point *"));
    try std.testing.expectEqualStrings("Point", MarkdownGenerator.extractBaseType("const Point *"));
    try std.testing.expectEqualStrings("Point", MarkdownGenerator.extractBaseType("struct Point"));
    try std.testing.expectEqualStrings("Point", MarkdownGenerator.extractBaseType("struct Point *"));
    try std.testing.expectEqualStrings("Color", MarkdownGenerator.extractBaseType("enum Color"));
    try std.testing.expectEqualStrings("Data", MarkdownGenerator.extractBaseType("union Data"));
}

test "generate markdown with cross-references" {
    var symbol_table = xref.SymbolTable.init(std.testing.allocator);
    defer symbol_table.deinit();

    // Register a struct type
    try symbol_table.register("Point", .struct_type, "geometry.h");

    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();
    gen.setSymbolTable(&symbol_table);

    // Create a function that uses the Point type
    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "get_point",
                .return_type = "Point *",
                .params = &[_]types.Parameter{},
                .doc = types.DocString{
                    .raw = "",
                    .brief = "Gets a point.",
                    .returns = "A pointer to a Point",
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);

    // Should contain a link to Point
    try std.testing.expect(std.mem.indexOf(u8, output, "[Point](#point)") != null);
}

test "generate markdown with see_also cross-references" {
    var symbol_table = xref.SymbolTable.init(std.testing.allocator);
    defer symbol_table.deinit();

    // Register related functions
    try symbol_table.register("other_func", .function, "test.h");

    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();
    gen.setSymbolTable(&symbol_table);

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "my_func",
                .return_type = "void",
                .params = &[_]types.Parameter{},
                .doc = types.DocString{
                    .raw = "",
                    .brief = "Does something.",
                    .see_also = &[_][]const u8{"other_func"},
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);

    // Should contain a link to other_func in See also section
    try std.testing.expect(std.mem.indexOf(u8, output, "**See also:**") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[other_func](#other-func)") != null);
}

test "generate markdown without cross-references falls back to plain text" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    // No symbol table set - should fall back to plain text
    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{
            .{
                .name = "my_func",
                .return_type = "void",
                .params = &[_]types.Parameter{},
                .doc = types.DocString{
                    .raw = "",
                    .brief = "Does something.",
                    .see_also = &[_][]const u8{"unknown_func"},
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);

    // Should contain plain code text (no link)
    try std.testing.expect(std.mem.indexOf(u8, output, "`unknown_func`") != null);
}

test "struct fields show type with cross-reference links" {
    var symbol_table = xref.SymbolTable.init(std.testing.allocator);
    defer symbol_table.deinit();

    // Register a type
    try symbol_table.register("Color", .enum_type, "types.h");

    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();
    gen.setSymbolTable(&symbol_table);

    const module = types.Module{
        .name = "test.h",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{
            .{
                .name = "Shape",
                .fields = &[_]types.StructField{
                    .{ .name = "fill_color", .type_str = "Color", .doc = "Fill color" },
                },
                .location = .{ .file = "test.h", .line = 1, .column = 1 },
            },
        },
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
    };

    const output = try gen.generate(module);

    // Should contain a link to Color in the fields section
    try std.testing.expect(std.mem.indexOf(u8, output, "`fill_color` ([Color](#color))") != null);
}

test "generate markdown for type alias" {
    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const module = types.Module{
        .name = "test.hpp",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
        .type_aliases = &[_]types.TypeAlias{
            .{
                .name = "Vec2f",
                .underlying_type = "Vec2<f32>",
            },
        },
    };

    const output = try gen.generate(module);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Type Aliases") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "### `Vec2f`") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "using Vec2f = Vec2<f32>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Alias for Vec2&lt;f32&gt;") != null);
}

test "generate markdown for type alias with cross-reference" {
    var symbol_table = xref.SymbolTable.init(std.testing.allocator);
    defer symbol_table.deinit();

    // Register the underlying type
    try symbol_table.register("Vec2", .class_type, "vector.hpp");

    var gen = MarkdownGenerator.init(std.testing.allocator);
    defer gen.deinit();
    gen.setSymbolTable(&symbol_table);

    const module = types.Module{
        .name = "test.hpp",
        .functions = &[_]types.Function{},
        .structs = &[_]types.Struct{},
        .enums = &[_]types.Enum{},
        .typedefs = &[_]types.Typedef{},
        .type_aliases = &[_]types.TypeAlias{
            .{
                .name = "Vec2f",
                .underlying_type = "Vec2<f32>",
            },
        },
    };

    const output = try gen.generate(module);

    // Should contain a link to Vec2 in the "Alias for" line
    try std.testing.expect(std.mem.indexOf(u8, output, "[Vec2](#vec2)&lt;f32&gt;") != null);
}
