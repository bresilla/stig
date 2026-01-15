//! Markdown Renderer - Converts DocumentModel to Markdown strings
//!
//! This renderer takes a DocumentModel (from JSON) and produces Markdown output.
//! It is designed to be simple and template-like since all cross-reference resolution,
//! anchor generation, and filtering is already done in the DocumentModel.
//!
//! ## Design Principles
//!
//! 1. **Pure Rendering**: No data transformation, just string formatting
//! 2. **Pre-resolved Links**: All cross-references are already resolved in DocumentModel
//! 3. **Pre-computed Anchors**: All anchors are already computed
//! 4. **No Symbol Table**: Not needed - links are resolved
//!
//! ## Usage
//!
//! ```zig
//! var renderer = MarkdownRenderer.init(allocator);
//! defer renderer.deinit();
//!
//! const markdown = try renderer.renderModule(module_doc);
//! ```

const std = @import("std");
const schema = @import("../json/schema.zig");

/// Markdown renderer for DocumentModel
pub const MarkdownRenderer = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    config: RenderConfig,

    pub const RenderConfig = struct {
        /// Use HTML escaping for angle brackets in type names
        escape_html: bool = true,
        /// Include source file locations
        include_locations: bool = false,
        /// Add horizontal rules between sections
        section_separators: bool = true,
        /// Section names (can be localized)
        sections: SectionNames = .{},
    };

    pub const SectionNames = struct {
        functions: []const u8 = "Functions",
        classes: []const u8 = "Classes",
        structs: []const u8 = "Structures",
        unions: []const u8 = "Unions",
        enums: []const u8 = "Enumerations",
        typedefs: []const u8 = "Type Definitions",
        type_aliases: []const u8 = "Type Aliases",
        macros: []const u8 = "Macros",
        concepts: []const u8 = "Concepts",
        parameters: []const u8 = "Parameters",
        template_parameters: []const u8 = "Template Parameters",
        returns: []const u8 = "Returns",
        throws: []const u8 = "Throws",
        see_also: []const u8 = "See Also",
        notes: []const u8 = "Notes",
        warnings: []const u8 = "Warnings",
        examples: []const u8 = "Examples",
        members: []const u8 = "Members",
        public_members: []const u8 = "Public Members",
        protected_members: []const u8 = "Protected Members",
        private_members: []const u8 = "Private Members",
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = .empty,
            .config = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: RenderConfig) Self {
        return Self{
            .allocator = allocator,
            .buffer = .empty,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Clear the buffer for reuse
    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    // =========================================================================
    // Main Rendering Functions
    // =========================================================================

    /// Render a complete module document
    pub fn renderModule(self: *Self, module: schema.ModuleDoc) ![]const u8 {
        self.reset();

        // Module header
        try self.writeHeader(1, module.title orelse module.name);
        try self.writeNewline();

        // File-level documentation
        if (module.file_doc) |doc| {
            try self.renderDocString(doc);
        }

        // Functions section
        if (module.functions.len > 0) {
            try self.writeHeader(2, self.config.sections.functions);
            try self.writeNewline();
            for (module.functions) |func| {
                try self.renderFunction(func);
            }
        }

        // Classes section
        if (module.classes.len > 0) {
            try self.writeHeader(2, self.config.sections.classes);
            try self.writeNewline();
            for (module.classes) |class| {
                try self.renderClass(class);
            }
        }

        // Structs section
        if (module.structs.len > 0) {
            try self.writeHeader(2, self.config.sections.structs);
            try self.writeNewline();
            for (module.structs) |s| {
                try self.renderStruct(s);
            }
        }

        // Unions section
        if (module.unions.len > 0) {
            try self.writeHeader(2, self.config.sections.unions);
            try self.writeNewline();
            for (module.unions) |u| {
                try self.renderUnion(u);
            }
        }

        // Enums section
        if (module.enums.len > 0) {
            try self.writeHeader(2, self.config.sections.enums);
            try self.writeNewline();
            for (module.enums) |e| {
                try self.renderEnum(e);
            }
        }

        // Typedefs section
        if (module.typedefs.len > 0) {
            try self.writeHeader(2, self.config.sections.typedefs);
            try self.writeNewline();
            for (module.typedefs) |td| {
                try self.renderTypedef(td);
            }
        }

        // Type aliases section
        if (module.type_aliases.len > 0) {
            try self.writeHeader(2, self.config.sections.type_aliases);
            try self.writeNewline();
            for (module.type_aliases) |ta| {
                try self.renderTypeAlias(ta);
            }
        }

        // Macros section
        if (module.macros.len > 0) {
            try self.writeHeader(2, self.config.sections.macros);
            try self.writeNewline();
            for (module.macros) |m| {
                try self.renderMacro(m);
            }
        }

        // Concepts section
        if (module.concepts.len > 0) {
            try self.writeHeader(2, self.config.sections.concepts);
            try self.writeNewline();
            for (module.concepts) |c| {
                try self.renderConcept(c);
            }
        }

        return self.buffer.items;
    }

    /// Render a function
    pub fn renderFunction(self: *Self, func: schema.FunctionDoc) !void {
        // Anchor
        try self.writeAnchor(func.anchor);

        // Function name as heading
        try self.writeString("### `");
        try self.writeString(func.name);
        try self.writeTemplateParams(func.template_params);
        try self.writeString("`\n\n");

        // Signature in code block
        try self.writeString("```cpp\n");
        try self.writeString(func.signature);
        try self.writeString("\n```\n\n");

        // Documentation
        if (func.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Parameters
        if (func.parameters.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.parameters);
            try self.writeString(":**\n");
            for (func.parameters) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                try self.writeString("`");
                if (param.type_str.len > 0) {
                    try self.writeString(" (");
                    try self.writeEscaped(param.type_str);
                    try self.writeString(")");
                }
                if (param.doc) |pdoc| {
                    try self.writeString(": ");
                    try self.writeString(pdoc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Location
        if (self.config.include_locations) {
            try self.writeLocation(func.location);
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a class
    pub fn renderClass(self: *Self, class: schema.ClassDoc) !void {
        // Anchor
        try self.writeAnchor(class.anchor);

        // Class name as heading
        try self.writeString("### `");
        try self.writeString(class.name);
        try self.writeTemplateParams(class.template_params);
        try self.writeString("`\n\n");

        // Base classes
        if (class.base_classes.len > 0) {
            try self.writeString("**Inherits from:** ");
            for (class.base_classes, 0..) |base, i| {
                if (i > 0) try self.writeString(", ");
                if (base.resolved_link) |link| {
                    try self.writeString("[");
                    try self.writeString(base.name);
                    try self.writeString("](");
                    try self.writeString(link);
                    try self.writeString(")");
                } else {
                    try self.writeString("`");
                    try self.writeString(base.name);
                    try self.writeString("`");
                }
            }
            try self.writeString("\n\n");
        }

        // Documentation
        if (class.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Public members
        try self.renderMemberGroup(class.members.public, self.config.sections.public_members);

        // Protected members
        try self.renderMemberGroup(class.members.protected, self.config.sections.protected_members);

        // Private members
        try self.renderMemberGroup(class.members.private, self.config.sections.private_members);

        // Nested classes
        if (class.nested_classes.len > 0) {
            try self.writeString("#### Nested Classes\n\n");
            for (class.nested_classes) |nested| {
                try self.renderClass(nested);
            }
        }

        // Nested enums
        if (class.nested_enums.len > 0) {
            try self.writeString("#### Nested Enums\n\n");
            for (class.nested_enums) |nested| {
                try self.renderEnum(nested);
            }
        }

        // Friends
        if (class.friends.len > 0) {
            try self.writeString("#### Friends\n\n");
            for (class.friends) |friend| {
                try self.writeString("- ");
                switch (friend.kind) {
                    .class_ => try self.writeString("class "),
                    .function => try self.writeString("function "),
                }
                try self.writeString("`");
                try self.writeString(friend.name);
                try self.writeString("`");
                if (friend.signature) |sig| {
                    try self.writeString(": `");
                    try self.writeString(sig);
                    try self.writeString("`");
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    fn renderMemberGroup(self: *Self, group: schema.MemberGroup, title: []const u8) !void {
        if (group.methods.len == 0 and group.fields.len == 0) return;

        try self.writeString("#### ");
        try self.writeString(title);
        try self.writeString("\n\n");

        // Methods
        for (group.methods) |method| {
            try self.renderMethod(method);
        }

        // Fields
        if (group.fields.len > 0) {
            try self.writeString("**Fields:**\n");
            for (group.fields) |field| {
                try self.writeString("- `");
                try self.writeEscaped(field.type_str);
                try self.writeString(" ");
                try self.writeString(field.name);
                try self.writeString("`");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }
    }

    fn renderMethod(self: *Self, method: schema.MethodDoc) !void {
        try self.writeAnchor(method.anchor);

        // Method signature
        try self.writeString("##### `");
        try self.writeString(method.name);
        try self.writeString("`\n\n");

        try self.writeString("```cpp\n");
        try self.writeString(method.signature);
        try self.writeString("\n```\n\n");

        // Qualifiers
        var qualifiers: std.ArrayList([]const u8) = .empty;
        defer qualifiers.deinit(self.allocator);

        if (method.qualifiers.is_virtual) qualifiers.append(self.allocator, "virtual") catch return error.OutOfMemory;
        if (method.qualifiers.is_static) qualifiers.append(self.allocator, "static") catch return error.OutOfMemory;
        if (method.qualifiers.is_const) qualifiers.append(self.allocator, "const") catch return error.OutOfMemory;
        if (method.qualifiers.is_override) qualifiers.append(self.allocator, "override") catch return error.OutOfMemory;
        if (method.qualifiers.is_final) qualifiers.append(self.allocator, "final") catch return error.OutOfMemory;
        if (method.qualifiers.is_pure_virtual) qualifiers.append(self.allocator, "pure virtual") catch return error.OutOfMemory;
        if (method.qualifiers.is_constexpr) qualifiers.append(self.allocator, "constexpr") catch return error.OutOfMemory;
        if (method.qualifiers.is_noexcept) qualifiers.append(self.allocator, "noexcept") catch return error.OutOfMemory;

        if (qualifiers.items.len > 0) {
            try self.writeString("*");
            for (qualifiers.items, 0..) |q, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(q);
            }
            try self.writeString("*\n\n");
        }

        // Documentation
        if (method.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Parameters
        if (method.parameters.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.parameters);
            try self.writeString(":**\n");
            for (method.parameters) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                try self.writeString("`");
                if (param.type_str.len > 0) {
                    try self.writeString(" (");
                    try self.writeEscaped(param.type_str);
                    try self.writeString(")");
                }
                if (param.doc) |pdoc| {
                    try self.writeString(": ");
                    try self.writeString(pdoc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }
    }

    /// Render a struct
    pub fn renderStruct(self: *Self, s: schema.StructDoc) !void {
        try self.writeAnchor(s.anchor);

        try self.writeString("### `");
        try self.writeString(s.name);
        try self.writeString("`\n\n");

        // Documentation
        if (s.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Fields
        if (s.fields.len > 0) {
            try self.writeString("**Fields:**\n");
            for (s.fields) |field| {
                try self.writeString("- `");
                try self.writeEscaped(field.type_str);
                try self.writeString(" ");
                try self.writeString(field.name);
                try self.writeString("`");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a union
    pub fn renderUnion(self: *Self, u: schema.UnionDoc) !void {
        try self.writeAnchor(u.anchor);

        try self.writeString("### `");
        try self.writeString(u.name);
        try self.writeString("`\n\n");

        // Documentation
        if (u.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Fields
        if (u.fields.len > 0) {
            try self.writeString("**Members:**\n");
            for (u.fields) |field| {
                try self.writeString("- `");
                try self.writeEscaped(field.type_str);
                try self.writeString(" ");
                try self.writeString(field.name);
                try self.writeString("`");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render an enum
    pub fn renderEnum(self: *Self, e: schema.EnumDoc) !void {
        try self.writeAnchor(e.anchor);

        try self.writeString("### `");
        try self.writeString(e.name);
        try self.writeString("`\n\n");

        // Documentation
        if (e.doc) |doc| {
            try self.renderDocString(doc);
        }

        // Values
        if (e.values.len > 0) {
            try self.writeString("**Values:**\n");
            for (e.values) |val| {
                try self.writeString("- `");
                try self.writeString(val.name);
                try self.writeString("`");
                if (val.value) |v| {
                    try self.writeString(" = ");
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "?";
                    try self.writeString(str);
                }
                if (val.doc) |doc| {
                    try self.writeString(": ");
                    try self.writeString(doc);
                }
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a typedef
    pub fn renderTypedef(self: *Self, td: schema.TypedefDoc) !void {
        try self.writeAnchor(td.anchor);

        try self.writeString("### `");
        try self.writeString(td.name);
        try self.writeString("`\n\n");

        try self.writeString("```cpp\n");
        try self.writeString("typedef ");
        try self.writeString(td.underlying);
        try self.writeString(" ");
        try self.writeString(td.name);
        try self.writeString(";\n```\n\n");

        // Documentation
        if (td.doc) |doc| {
            try self.renderDocString(doc);
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a type alias
    pub fn renderTypeAlias(self: *Self, ta: schema.TypeAliasDoc) !void {
        try self.writeAnchor(ta.anchor);

        try self.writeString("### `");
        try self.writeString(ta.name);
        try self.writeTemplateParams(ta.template_params);
        try self.writeString("`\n\n");

        try self.writeString("```cpp\n");
        if (ta.template_params.len > 0) {
            try self.writeString("template<");
            for (ta.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.writeString(param.name);
            }
            try self.writeString(">\n");
        }
        try self.writeString("using ");
        try self.writeString(ta.name);
        try self.writeString(" = ");
        try self.writeString(ta.underlying_type);
        try self.writeString(";\n```\n\n");

        // Documentation
        if (ta.doc) |doc| {
            try self.renderDocString(doc);
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a macro
    pub fn renderMacro(self: *Self, m: schema.MacroDoc) !void {
        try self.writeAnchor(m.anchor);

        try self.writeString("### `");
        try self.writeString(m.name);
        if (m.params) |params| {
            try self.writeString("(");
            for (params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param);
            }
            try self.writeString(")");
        }
        try self.writeString("`\n\n");

        try self.writeString("```cpp\n");
        try self.writeString("#define ");
        try self.writeString(m.name);
        if (m.params) |params| {
            try self.writeString("(");
            for (params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param);
            }
            try self.writeString(")");
        }
        try self.writeString(" ");
        try self.writeString(m.body);
        try self.writeString("\n```\n\n");

        // Documentation
        if (m.doc) |doc| {
            try self.renderDocString(doc);
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render a concept
    pub fn renderConcept(self: *Self, c: schema.ConceptDoc) !void {
        try self.writeAnchor(c.anchor);

        try self.writeString("### `");
        try self.writeString(c.name);
        try self.writeTemplateParams(c.template_params);
        try self.writeString("`\n\n");

        try self.writeString("```cpp\n");
        if (c.template_params.len > 0) {
            try self.writeString("template<");
            for (c.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.writeString(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.writeString(param.name);
            }
            try self.writeString(">\n");
        }
        try self.writeString("concept ");
        try self.writeString(c.name);
        try self.writeString(" = ");
        try self.writeString(c.constraint);
        try self.writeString(";\n```\n\n");

        // Documentation
        if (c.doc) |doc| {
            try self.renderDocString(doc);
        }

        if (self.config.section_separators) {
            try self.writeString("---\n\n");
        }
    }

    /// Render an index page
    pub fn renderIndex(self: *Self, index: []const schema.IndexEntry, title: []const u8) ![]const u8 {
        self.reset();

        try self.writeHeader(1, title);
        try self.writeNewline();

        // Group by kind
        var functions: std.ArrayList(schema.IndexEntry) = .empty;
        defer functions.deinit(self.allocator);
        var types: std.ArrayList(schema.IndexEntry) = .empty;
        defer types.deinit(self.allocator);
        var macros: std.ArrayList(schema.IndexEntry) = .empty;
        defer macros.deinit(self.allocator);

        for (index) |entry| {
            switch (entry.kind) {
                .function, .method => functions.append(self.allocator, entry) catch return error.OutOfMemory,
                .macro => macros.append(self.allocator, entry) catch return error.OutOfMemory,
                else => types.append(self.allocator, entry) catch return error.OutOfMemory,
            }
        }

        // Functions
        if (functions.items.len > 0) {
            try self.writeHeader(2, "Functions");
            try self.writeNewline();
            for (functions.items) |entry| {
                try self.renderIndexEntry(entry);
            }
            try self.writeNewline();
        }

        // Types
        if (types.items.len > 0) {
            try self.writeHeader(2, "Types");
            try self.writeNewline();
            for (types.items) |entry| {
                try self.renderIndexEntry(entry);
            }
            try self.writeNewline();
        }

        // Macros
        if (macros.items.len > 0) {
            try self.writeHeader(2, "Macros");
            try self.writeNewline();
            for (macros.items) |entry| {
                try self.renderIndexEntry(entry);
            }
            try self.writeNewline();
        }

        return self.buffer.items;
    }

    fn renderIndexEntry(self: *Self, entry: schema.IndexEntry) !void {
        try self.writeString("- [`");
        try self.writeString(entry.name);
        try self.writeString("`](#");
        try self.writeString(entry.anchor);
        try self.writeString(")");
        if (entry.brief) |brief| {
            try self.writeString(" - ");
            try self.writeString(brief);
        }
        try self.writeString("\n");
    }

    /// Render todo list
    pub fn renderTodoList(self: *Self, todos: []const schema.TodoDoc) ![]const u8 {
        self.reset();

        try self.writeHeader(1, "TODO List");
        try self.writeNewline();

        if (todos.len == 0) {
            try self.writeString("No TODOs found.\n");
            return self.buffer.items;
        }

        for (todos) |todo| {
            try self.writeString("- [ ] ");
            try self.writeString(todo.description);
            try self.writeString("\n  - *");
            try self.writeString(todo.entity_name);
            try self.writeString("* (");
            try self.writeString(todo.location.file);
            try self.writeString(":");
            var buf: [16]u8 = undefined;
            const line_str = std.fmt.bufPrint(&buf, "{d}", .{todo.location.line}) catch "?";
            try self.writeString(line_str);
            try self.writeString(")\n");
        }

        return self.buffer.items;
    }

    /// Render bug list
    pub fn renderBugList(self: *Self, bugs: []const schema.BugDoc) ![]const u8 {
        self.reset();

        try self.writeHeader(1, "Known Bugs");
        try self.writeNewline();

        if (bugs.len == 0) {
            try self.writeString("No known bugs.\n");
            return self.buffer.items;
        }

        for (bugs) |bug| {
            try self.writeString("- ");
            try self.writeString(bug.description);
            try self.writeString("\n  - *");
            try self.writeString(bug.entity_name);
            try self.writeString("* (");
            try self.writeString(bug.location.file);
            try self.writeString(":");
            var buf: [16]u8 = undefined;
            const line_str = std.fmt.bufPrint(&buf, "{d}", .{bug.location.line}) catch "?";
            try self.writeString(line_str);
            try self.writeString(")\n");
        }

        return self.buffer.items;
    }

    /// Render a page
    pub fn renderPage(self: *Self, page: schema.PageDoc) ![]const u8 {
        self.reset();

        try self.writeHeader(1, page.title);
        try self.writeNewline();
        try self.writeString(page.content);
        try self.writeNewline();

        return self.buffer.items;
    }

    // =========================================================================
    // DocString Rendering
    // =========================================================================

    fn renderDocString(self: *Self, doc: schema.DocStringDoc) !void {
        // Brief
        if (doc.brief) |brief| {
            try self.writeString(brief);
            try self.writeString("\n\n");
        }

        // Details
        if (doc.details) |details| {
            try self.writeString(details);
            try self.writeString("\n\n");
        }

        // Deprecated notice
        if (doc.deprecated) |deprecated| {
            try self.writeString("> **Deprecated:** ");
            try self.writeString(deprecated);
            try self.writeString("\n\n");
        }

        // Parameters
        if (doc.params.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.parameters);
            try self.writeString(":**\n");
            for (doc.params) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                try self.writeString("`: ");
                try self.writeString(param.description);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Template parameters
        if (doc.tparams.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.template_parameters);
            try self.writeString(":**\n");
            for (doc.tparams) |param| {
                try self.writeString("- `");
                try self.writeString(param.name);
                try self.writeString("`: ");
                try self.writeString(param.description);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Returns
        if (doc.returns) |ret| {
            try self.writeString("**");
            try self.writeString(self.config.sections.returns);
            try self.writeString(":** ");
            try self.writeString(ret);
            try self.writeString("\n\n");
        }

        // Return values
        if (doc.retvals.len > 0) {
            try self.writeString("**Return Values:**\n");
            for (doc.retvals) |rv| {
                try self.writeString("- `");
                try self.writeString(rv.value);
                try self.writeString("`: ");
                try self.writeString(rv.description);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Exceptions
        if (doc.exceptions.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.throws);
            try self.writeString(":**\n");
            for (doc.exceptions) |exc| {
                try self.writeString("- `");
                try self.writeString(exc.exception_type);
                try self.writeString("`: ");
                try self.writeString(exc.description);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Code blocks
        for (doc.code_blocks) |block| {
            try self.writeString("```");
            if (block.language) |lang| {
                try self.writeString(lang);
            }
            try self.writeString("\n");
            try self.writeString(block.content);
            try self.writeString("\n```\n\n");
        }

        // Mermaid diagrams
        for (doc.mermaid_diagrams) |diagram| {
            try self.writeString("```mermaid\n");
            try self.writeString(diagram.content);
            try self.writeString("\n```\n");
            if (diagram.caption) |caption| {
                try self.writeString("*");
                try self.writeString(caption);
                try self.writeString("*\n");
            }
            try self.writeNewline();
        }

        // Notes
        for (doc.notes) |note| {
            try self.writeString("> **Note:** ");
            try self.writeString(note);
            try self.writeString("\n\n");
        }

        // Warnings
        for (doc.warnings) |warning| {
            try self.writeString("> **Warning:** ");
            try self.writeString(warning);
            try self.writeString("\n\n");
        }

        // See also
        if (doc.see_also.len > 0) {
            try self.writeString("**");
            try self.writeString(self.config.sections.see_also);
            try self.writeString(":** ");
            for (doc.see_also, 0..) |ref, i| {
                if (i > 0) try self.writeString(", ");
                if (ref.resolved_url) |url| {
                    try self.writeString("[");
                    try self.writeString(ref.display_text orelse ref.target);
                    try self.writeString("](");
                    try self.writeString(url);
                    try self.writeString(")");
                } else {
                    try self.writeString("`");
                    try self.writeString(ref.target);
                    try self.writeString("`");
                }
            }
            try self.writeString("\n\n");
        }

        // Additional metadata
        if (doc.since) |since| {
            try self.writeString("**Since:** ");
            try self.writeString(since);
            try self.writeString("\n\n");
        }

        if (doc.author) |author| {
            try self.writeString("**Author:** ");
            try self.writeString(author);
            try self.writeString("\n\n");
        }

        if (doc.version) |version| {
            try self.writeString("**Version:** ");
            try self.writeString(version);
            try self.writeString("\n\n");
        }

        // Preconditions
        if (doc.preconditions.len > 0) {
            try self.writeString("**Preconditions:**\n");
            for (doc.preconditions) |pre| {
                try self.writeString("- ");
                try self.writeString(pre);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Postconditions
        if (doc.postconditions.len > 0) {
            try self.writeString("**Postconditions:**\n");
            for (doc.postconditions) |post| {
                try self.writeString("- ");
                try self.writeString(post);
                try self.writeString("\n");
            }
            try self.writeNewline();
        }

        // Complexity
        if (doc.complexity) |complexity| {
            try self.writeString("**Complexity:** ");
            try self.writeString(complexity);
            try self.writeString("\n\n");
        }
    }

    // =========================================================================
    // Utility Functions
    // =========================================================================

    fn writeString(self: *Self, s: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, s);
    }

    fn writeNewline(self: *Self) !void {
        try self.buffer.append(self.allocator, '\n');
    }

    fn writeHeader(self: *Self, level: u8, text: []const u8) !void {
        for (0..level) |_| {
            try self.buffer.append(self.allocator, '#');
        }
        try self.buffer.append(self.allocator, ' ');
        try self.buffer.appendSlice(self.allocator, text);
        try self.buffer.append(self.allocator, '\n');
    }

    fn writeAnchor(self: *Self, anchor: []const u8) !void {
        if (anchor.len == 0) return;
        try self.writeString("<a id=\"");
        try self.writeString(anchor);
        try self.writeString("\"></a>\n\n");
    }

    fn writeEscaped(self: *Self, s: []const u8) !void {
        if (!self.config.escape_html) {
            try self.writeString(s);
            return;
        }

        for (s) |c| {
            switch (c) {
                '<' => try self.writeString("&lt;"),
                '>' => try self.writeString("&gt;"),
                '&' => try self.writeString("&amp;"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
    }

    fn writeTemplateParams(self: *Self, params: []const schema.TemplateParamDoc) !void {
        if (params.len == 0) return;

        try self.writeString("&lt;");
        for (params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.writeString(param.name);
            if (param.is_variadic) try self.writeString("...");
        }
        try self.writeString("&gt;");
    }

    fn writeLocation(self: *Self, loc: schema.LocationDoc) !void {
        try self.writeString("*Defined in ");
        try self.writeString(loc.file);
        try self.writeString(":");
        var buf: [16]u8 = undefined;
        const line_str = std.fmt.bufPrint(&buf, "{d}", .{loc.line}) catch "?";
        try self.writeString(line_str);
        try self.writeString("*\n\n");
    }
};

// ============================================================================
// Tests
// ============================================================================

test "render simple function" {
    const allocator = std.testing.allocator;
    var renderer = MarkdownRenderer.init(allocator);
    defer renderer.deinit();

    const func = schema.FunctionDoc{
        .id = "foo",
        .name = "foo",
        .qualified_name = "foo",
        .anchor = "foo",
        .signature = "int foo(int x)",
        .return_type = "int",
        .parameters = &[_]schema.ParameterDoc{
            .{ .name = "x", .type_str = "int", .doc = "The input value" },
        },
        .doc = schema.DocStringDoc{
            .raw = "",
            .brief = "A simple function",
        },
        .location = .{ .file = "test.hpp", .line = 10, .column = 1 },
        .qualifiers = .{},
    };

    try renderer.renderFunction(func);
    const result = renderer.buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "### `foo`") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "int foo(int x)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "A simple function") != null);
}

test "render module" {
    const allocator = std.testing.allocator;
    var renderer = MarkdownRenderer.init(allocator);
    defer renderer.deinit();

    const module = schema.ModuleDoc{
        .id = "test-module",
        .name = "test.hpp",
        .path = "test",
        .functions = &[_]schema.FunctionDoc{
            .{
                .id = "bar",
                .name = "bar",
                .qualified_name = "bar",
                .anchor = "bar",
                .signature = "void bar()",
                .return_type = "void",
                .parameters = &[_]schema.ParameterDoc{},
                .location = .{ .file = "test.hpp", .line = 5, .column = 1 },
                .qualifiers = .{},
            },
        },
    };

    _ = try renderer.renderModule(module);
    const result = renderer.buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "# test.hpp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "## Functions") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "### `bar`") != null);
}
