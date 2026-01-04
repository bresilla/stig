const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const types = @import("../model/types.zig");
const DocstringExtractor = @import("../docstring/extractor.zig").DocstringExtractor;
const common = @import("common.zig");

/// C language parser using tree-sitter
pub const CParser = struct {
    parser: *ts.Parser,
    language: *ts.Language,
    allocator: std.mem.Allocator,
    source: []const u8 = "",
    docstring_extractor: DocstringExtractor,

    const Self = @This();

    /// Creates a new C parser
    pub fn init(allocator: std.mem.Allocator) !Self {
        const language: *ts.Language = @ptrCast(@constCast(ts_c.language()));
        const parser = ts.Parser.create();
        try parser.setLanguage(language);

        return Self{
            .parser = parser,
            .language = language,
            .allocator = allocator,
            .docstring_extractor = DocstringExtractor.init(allocator),
        };
    }

    /// Destroys the parser and frees resources
    pub fn deinit(self: *Self) void {
        self.parser.destroy();
        self.language.destroy();
    }

    /// Sets the base path for resolving include directives in docstrings
    pub fn setBasePath(self: *Self, path: []const u8) void {
        self.docstring_extractor.setBasePath(path);
    }

    /// Parses C source code and extracts documentation
    pub fn parse(self: *Self, source: []const u8, filename: []const u8) !types.Module {
        self.source = source;

        const tree = self.parser.parseString(source, null);
        if (tree == null) {
            return types.Module{
                .name = filename,
                .functions = &[_]types.Function{},
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
                .macros = &[_]types.Macro{},
            };
        }
        defer tree.?.destroy();

        var functions: std.ArrayList(types.Function) = .empty;
        var structs: std.ArrayList(types.Struct) = .empty;
        var enums: std.ArrayList(types.Enum) = .empty;
        var typedefs: std.ArrayList(types.Typedef) = .empty;
        var macros: std.ArrayList(types.Macro) = .empty;
        var pages: std.ArrayList(types.Page) = .empty;
        var includes: std.ArrayList(types.IncludeInfo) = .empty;

        const root = tree.?.rootNode();
        try self.walkNode(root, &functions, &structs, &enums, &typedefs, &macros, &includes, filename);

        // Extract custom pages (@page, @mainpage) from standalone doc comments
        try self.extractPages(root, &pages);

        return types.Module{
            .name = filename,
            .functions = try functions.toOwnedSlice(self.allocator),
            .structs = try structs.toOwnedSlice(self.allocator),
            .enums = try enums.toOwnedSlice(self.allocator),
            .typedefs = try typedefs.toOwnedSlice(self.allocator),
            .macros = try macros.toOwnedSlice(self.allocator),
            .pages = try pages.toOwnedSlice(self.allocator),
            .includes = try includes.toOwnedSlice(self.allocator),
        };
    }

    /// Walks the AST and extracts declarations
    fn walkNode(
        self: *Self,
        node: ts.Node,
        functions: *std.ArrayList(types.Function),
        structs: *std.ArrayList(types.Struct),
        enums: *std.ArrayList(types.Enum),
        typedefs: *std.ArrayList(types.Typedef),
        macros: *std.ArrayList(types.Macro),
        includes: *std.ArrayList(types.IncludeInfo),
        filename: []const u8,
    ) !void {
        const kind = node.kind();

        if (std.mem.eql(u8, kind, "function_definition")) {
            if (try self.extractFunction(node, filename)) |func| {
                try functions.append(self.allocator, func);
            }
        } else if (std.mem.eql(u8, kind, "declaration")) {
            // Could be a function prototype or variable declaration
            if (try self.extractFunctionPrototype(node, filename)) |func| {
                try functions.append(self.allocator, func);
            } else if (try self.extractTypedef(node, filename)) |td| {
                try typedefs.append(self.allocator, td);
            }
        } else if (std.mem.eql(u8, kind, "struct_specifier")) {
            if (try self.extractStruct(node, filename)) |s| {
                try structs.append(self.allocator, s);
            }
        } else if (std.mem.eql(u8, kind, "enum_specifier")) {
            if (try self.extractEnum(node, filename)) |e| {
                try enums.append(self.allocator, e);
            }
        } else if (std.mem.eql(u8, kind, "type_definition")) {
            if (try self.extractTypedef(node, filename)) |td| {
                try typedefs.append(self.allocator, td);
            }
        } else if (std.mem.eql(u8, kind, "preproc_def")) {
            // Object-like macro: #define NAME value
            if (self.extractObjectMacro(node, filename)) |macro| {
                try macros.append(self.allocator, macro);
            }
        } else if (std.mem.eql(u8, kind, "preproc_function_def")) {
            // Function-like macro: #define NAME(args) body
            if (try self.extractFunctionMacro(node, filename)) |macro| {
                try macros.append(self.allocator, macro);
            }
        } else if (std.mem.eql(u8, kind, "preproc_include")) {
            if (self.extractInclude(node)) |inc| {
                try includes.append(self.allocator, inc);
            }
        }

        // Recurse into children
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkNode(child, functions, structs, enums, typedefs, macros, includes, filename);
            }
        }
    }

    /// Finds the docstring comment preceding a node
    /// Looks for /** */ or consecutive /// comments immediately before the declaration
    fn findPrecedingDocstring(self: *Self, node: ts.Node) ?types.DocString {
        // Get the previous sibling
        const prev = node.prevSibling() orelse return null;
        const prev_kind = prev.kind();

        // Check if it's a comment
        if (std.mem.eql(u8, prev_kind, "comment")) {
            const comment_text = self.getNodeText(prev);

            // Check if it's a doc comment (/** or ///)
            if (std.mem.startsWith(u8, comment_text, "/**") or
                std.mem.startsWith(u8, comment_text, "///"))
            {
                // Check if there's no blank line between comment and declaration
                const comment_end_line = prev.endPoint().row;
                const decl_start_line = node.startPoint().row;

                // Allow at most 1 line gap (for the newline after comment)
                if (decl_start_line <= comment_end_line + 1) {
                    return self.parseDocComment(prev);
                }
            }
        }

        return null;
    }

    /// Collects consecutive /// comments into a single docstring
    fn collectTripleSlashComments(self: *Self, start_node: ts.Node) ?types.DocString {
        var comments: std.ArrayList([]const u8) = .empty;
        defer comments.deinit(self.allocator);

        var current = start_node;

        // Walk backwards collecting /// comments
        while (true) {
            const text = self.getNodeText(current);
            if (std.mem.startsWith(u8, text, "///")) {
                // Strip /// prefix and leading space
                var content = text[3..];
                if (content.len > 0 and content[0] == ' ') {
                    content = content[1..];
                }
                comments.insert(self.allocator, 0, content) catch break;

                // Check previous sibling
                if (current.prevSibling()) |prev| {
                    if (std.mem.eql(u8, prev.kind(), "comment")) {
                        const prev_text = self.getNodeText(prev);
                        if (std.mem.startsWith(u8, prev_text, "///")) {
                            // Check they're on consecutive lines
                            if (current.startPoint().row == prev.endPoint().row + 1) {
                                current = prev;
                                continue;
                            }
                        }
                    }
                }
            }
            break;
        }

        if (comments.items.len == 0) return null;

        // Join all comments with newlines
        var total_len: usize = 0;
        for (comments.items) |c| {
            total_len += c.len + 1; // +1 for newline
        }

        // For now, just use the raw text and parse it
        const raw = self.getNodeText(start_node);
        return self.parseRawDocstring(raw);
    }

    /// Parses a comment node into a DocString
    fn parseDocComment(self: *Self, comment_node: ts.Node) ?types.DocString {
        const text = self.getNodeText(comment_node);

        if (std.mem.startsWith(u8, text, "///")) {
            return self.collectTripleSlashComments(comment_node);
        } else if (std.mem.startsWith(u8, text, "/**")) {
            return self.parseRawDocstring(text);
        }

        return null;
    }

    /// Parses raw docstring text into structured DocString
    fn parseRawDocstring(self: *Self, raw: []const u8) ?types.DocString {
        const stripped = self.docstring_extractor.stripDelimiters(raw);
        if (stripped.len == 0) return null;

        // Parse the docstring
        const doc = self.docstring_extractor.parse(stripped) catch return null;
        return doc;
    }

    /// Extracts a function definition
    fn extractFunction(self: *Self, node: ts.Node, filename: []const u8) !?types.Function {
        // Get return type
        var return_type: []const u8 = "void";
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier"))
                {
                    return_type = self.getNodeText(child);
                    break;
                }
            }
        }

        // Get function declarator
        const declarator = node.childByFieldName("declarator") orelse return null;
        const func_name = self.extractFunctionName(declarator) orelse return null;
        const params = try self.extractParameters(declarator);

        // Find docstring
        const doc = self.findPrecedingDocstring(node);

        const start = node.startPoint();
        return types.Function{
            .name = func_name,
            .return_type = return_type,
            .params = params,
            .doc = doc,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a function prototype from a declaration
    fn extractFunctionPrototype(self: *Self, node: ts.Node, filename: []const u8) !?types.Function {
        // Look for function_declarator in the declaration
        var return_type: []const u8 = "void";
        var func_declarator: ?ts.Node = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier"))
                {
                    return_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    func_declarator = child;
                } else if (std.mem.eql(u8, child_kind, "pointer_declarator")) {
                    // Handle pointer return types
                    if (self.findFunctionDeclarator(child)) |fd| {
                        func_declarator = fd;
                    }
                }
            }
        }

        if (func_declarator) |fd| {
            const func_name = self.extractFunctionName(fd) orelse return null;
            const params = try self.extractParameters(fd);

            // Find docstring
            const doc = self.findPrecedingDocstring(node);

            const start = node.startPoint();
            return types.Function{
                .name = func_name,
                .return_type = return_type,
                .params = params,
                .doc = doc,
                .location = types.SourceLocation{
                    .file = filename,
                    .line = start.row + 1,
                    .column = start.column + 1,
                },
            };
        }

        return null;
    }

    /// Finds a function_declarator in a nested structure
    fn findFunctionDeclarator(self: *Self, node: ts.Node) ?ts.Node {
        _ = self;
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "function_declarator")) {
                    return child;
                }
            }
        }
        return null;
    }

    /// Extracts function name from a declarator
    fn extractFunctionName(self: *Self, declarator: ts.Node) ?[]const u8 {
        // The declarator might be a function_declarator or contain one
        if (std.mem.eql(u8, declarator.kind(), "function_declarator")) {
            // Look for identifier child
            var i: u32 = 0;
            while (i < declarator.childCount()) : (i += 1) {
                if (declarator.child(i)) |child| {
                    if (std.mem.eql(u8, child.kind(), "identifier")) {
                        return self.getNodeText(child);
                    }
                }
            }
        }
        return null;
    }

    /// Extracts parameters from a function declarator
    fn extractParameters(self: *Self, declarator: ts.Node) ![]const types.Parameter {
        var params: std.ArrayList(types.Parameter) = .empty;

        // Find parameter_list
        var i: u32 = 0;
        while (i < declarator.childCount()) : (i += 1) {
            if (declarator.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "parameter_list")) {
                    // Iterate through parameter_declaration nodes
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |param_node| {
                            if (std.mem.eql(u8, param_node.kind(), "parameter_declaration")) {
                                if (self.extractParameter(param_node)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            }
                        }
                    }
                    break;
                }
            }
        }

        return try params.toOwnedSlice(self.allocator);
    }

    /// Extracts a single parameter
    fn extractParameter(self: *Self, node: ts.Node) ?types.Parameter {
        var type_str: []const u8 = "";
        var name: []const u8 = "";

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier"))
                {
                    type_str = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "pointer_declarator")) {
                    // Handle pointer parameters
                    name = self.extractIdentifierFromDeclarator(child) orelse "";
                    type_str = self.getNodeText(node); // Get full type including pointer
                }
            }
        }

        if (name.len > 0) {
            return types.Parameter{
                .name = name,
                .type_str = type_str,
            };
        }
        return null;
    }

    /// Extracts identifier from a declarator (handles pointers)
    fn extractIdentifierFromDeclarator(self: *Self, node: ts.Node) ?[]const u8 {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "identifier")) {
                    return self.getNodeText(child);
                }
            }
        }
        return null;
    }

    /// Extracts a struct definition
    fn extractStruct(self: *Self, node: ts.Node, filename: []const u8) !?types.Struct {
        // Get struct name
        var name: []const u8 = "";
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "type_identifier")) {
                    name = self.getNodeText(child);
                    break;
                }
            }
        }

        if (name.len == 0) return null;

        // Get fields with their trailing comments
        var fields: std.ArrayList(types.StructField) = .empty;
        const body = node.childByFieldName("body");
        if (body) |field_list| {
            var j: u32 = 0;
            while (j < field_list.childCount()) : (j += 1) {
                if (field_list.child(j)) |field_node| {
                    if (std.mem.eql(u8, field_node.kind(), "field_declaration")) {
                        if (self.extractField(field_node)) |field| {
                            try fields.append(self.allocator, field);
                        }
                    }
                }
            }
        }

        // Find docstring for the struct
        // Need to look at parent's previous sibling since struct_specifier is inside declaration
        var doc: ?types.DocString = null;
        if (node.parent()) |parent| {
            doc = self.findPrecedingDocstring(parent);
        }
        if (doc == null) {
            doc = self.findPrecedingDocstring(node);
        }

        const start = node.startPoint();
        return types.Struct{
            .name = name,
            .fields = try fields.toOwnedSlice(self.allocator),
            .doc = doc,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a struct field with optional trailing comment
    fn extractField(self: *Self, node: ts.Node) ?types.StructField {
        var type_str: []const u8 = "";
        var name: []const u8 = "";
        var doc: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier"))
                {
                    type_str = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "comment")) {
                    // Trailing comment on same line
                    const comment_text = self.getNodeText(child);
                    if (std.mem.startsWith(u8, comment_text, "///<") or
                        std.mem.startsWith(u8, comment_text, "/**<"))
                    {
                        // Doxygen trailing comment
                        doc = self.stripTrailingCommentDelimiters(comment_text);
                    } else if (std.mem.startsWith(u8, comment_text, "///") or
                        std.mem.startsWith(u8, comment_text, "/**"))
                    {
                        doc = self.stripTrailingCommentDelimiters(comment_text);
                    }
                }
            }
        }

        // Also check next sibling for trailing comment
        if (doc == null) {
            if (node.nextSibling()) |next| {
                if (std.mem.eql(u8, next.kind(), "comment")) {
                    // Check if on same line
                    if (next.startPoint().row == node.endPoint().row) {
                        const comment_text = self.getNodeText(next);
                        doc = self.stripTrailingCommentDelimiters(comment_text);
                    }
                }
            }
        }

        if (name.len > 0) {
            return types.StructField{
                .name = name,
                .type_str = type_str,
                .doc = doc,
            };
        }
        return null;
    }

    /// Strips delimiters from trailing comments (///<, /**<, etc.)
    fn stripTrailingCommentDelimiters(_: *Self, text: []const u8) []const u8 {
        return common.stripTrailingCommentDelimiters(text);
    }

    /// Extracts an enum definition
    fn extractEnum(self: *Self, node: ts.Node, filename: []const u8) !?types.Enum {
        // Get enum name
        var name: []const u8 = "";
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "type_identifier")) {
                    name = self.getNodeText(child);
                    break;
                }
            }
        }

        if (name.len == 0) return null;

        // Get values
        var values: std.ArrayList(types.EnumValue) = .empty;
        const body = node.childByFieldName("body");
        if (body) |enumerator_list| {
            var j: u32 = 0;
            while (j < enumerator_list.childCount()) : (j += 1) {
                if (enumerator_list.child(j)) |enum_node| {
                    if (std.mem.eql(u8, enum_node.kind(), "enumerator")) {
                        if (try self.extractEnumValue(enum_node)) |val| {
                            try values.append(self.allocator, val);
                        }
                    }
                }
            }
        }

        // Find docstring
        var doc: ?types.DocString = null;
        if (node.parent()) |parent| {
            doc = self.findPrecedingDocstring(parent);
        }
        if (doc == null) {
            doc = self.findPrecedingDocstring(node);
        }

        const start = node.startPoint();
        return types.Enum{
            .name = name,
            .values = try values.toOwnedSlice(self.allocator),
            .doc = doc,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts an enum value with optional trailing comment
    fn extractEnumValue(self: *Self, node: ts.Node) !?types.EnumValue {
        var name: []const u8 = "";
        var value: ?i64 = null;
        var doc: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "number_literal")) {
                    const num_text = self.getNodeText(child);
                    value = std.fmt.parseInt(i64, num_text, 0) catch null;
                } else if (std.mem.eql(u8, child_kind, "comment")) {
                    const comment_text = self.getNodeText(child);
                    doc = self.stripTrailingCommentDelimiters(comment_text);
                }
            }
        }

        // Check next sibling for trailing comment
        if (doc == null) {
            if (node.nextSibling()) |next| {
                if (std.mem.eql(u8, next.kind(), "comment")) {
                    if (next.startPoint().row == node.endPoint().row) {
                        const comment_text = self.getNodeText(next);
                        doc = self.stripTrailingCommentDelimiters(comment_text);
                    }
                }
            }
        }

        if (name.len > 0) {
            return types.EnumValue{
                .name = name,
                .value = value,
                .doc = doc,
            };
        }
        return null;
    }

    /// Extracts a typedef
    fn extractTypedef(self: *Self, node: ts.Node, filename: []const u8) !?types.Typedef {
        // Check if this is a type_definition node
        if (!std.mem.eql(u8, node.kind(), "type_definition")) {
            return null;
        }

        var underlying: []const u8 = "";
        var name: []const u8 = "";

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier"))
                {
                    underlying = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    // Could be either underlying type or the new name
                    if (underlying.len == 0) {
                        underlying = self.getNodeText(child);
                    } else {
                        name = self.getNodeText(child);
                    }
                }
            }
        }

        if (name.len > 0 and underlying.len > 0) {
            // Find docstring
            const doc = self.findPrecedingDocstring(node);

            const start = node.startPoint();
            return types.Typedef{
                .name = name,
                .underlying = underlying,
                .doc = doc,
                .location = types.SourceLocation{
                    .file = filename,
                    .line = start.row + 1,
                    .column = start.column + 1,
                },
            };
        }
        return null;
    }

    /// Extracts an object-like macro (#define NAME value)
    fn extractObjectMacro(self: *Self, node: ts.Node, filename: []const u8) ?types.Macro {
        var name: []const u8 = "";
        var body: []const u8 = "";

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "preproc_arg")) {
                    body = std.mem.trim(u8, self.getNodeText(child), " \t");
                }
            }
        }

        if (name.len == 0) return null;

        // Find docstring
        const doc = self.findPrecedingDocstring(node);

        const start = node.startPoint();
        return types.Macro{
            .name = name,
            .params = null, // Object-like macro has no params
            .body = body,
            .doc = doc,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a function-like macro (#define NAME(args) body)
    fn extractFunctionMacro(self: *Self, node: ts.Node, filename: []const u8) !?types.Macro {
        var name: []const u8 = "";
        var body: []const u8 = "";
        var params: std.ArrayList([]const u8) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "preproc_params")) {
                    // Extract parameter names
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |param_child| {
                            if (std.mem.eql(u8, param_child.kind(), "identifier")) {
                                try params.append(self.allocator, self.getNodeText(param_child));
                            }
                        }
                    }
                } else if (std.mem.eql(u8, child_kind, "preproc_arg")) {
                    body = std.mem.trim(u8, self.getNodeText(child), " \t");
                }
            }
        }

        if (name.len == 0) {
            params.deinit(self.allocator);
            return null;
        }

        // Find docstring
        const doc = self.findPrecedingDocstring(node);

        const start = node.startPoint();
        return types.Macro{
            .name = name,
            .params = try params.toOwnedSlice(self.allocator),
            .body = body,
            .doc = doc,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts include directive information
    /// Handles both #include <...> and #include "..."
    fn extractInclude(self: *Self, node: ts.Node) ?types.IncludeInfo {
        return common.extractInclude(self.source, node);
    }

    /// Gets the text content of a node
    fn getNodeText(self: *Self, node: ts.Node) []const u8 {
        return common.getNodeText(self.source, node);
    }

    /// Extracts custom pages from standalone doc comments containing @page or @mainpage
    fn extractPages(self: *Self, root: ts.Node, pages: *std.ArrayList(types.Page)) !void {
        try common.extractPages(self.allocator, self.source, root, pages, &self.docstring_extractor);
    }
};

// Tests
test "parse simple function" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "int add(int a, int b) { return a + b; }";
    const module = try parser.parse(source, "test.c");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expectEqualStrings("add", module.functions[0].name);
    try std.testing.expectEqualStrings("int", module.functions[0].return_type);
    try std.testing.expectEqual(@as(usize, 2), module.functions[0].params.len);
}

test "parse function prototype" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "int subtract(int a, int b);";
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expectEqualStrings("subtract", module.functions[0].name);
}

test "parse struct" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "struct Point { int x; int y; };";
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.structs);

    try std.testing.expectEqual(@as(usize, 1), module.structs.len);
    try std.testing.expectEqualStrings("Point", module.structs[0].name);
    try std.testing.expectEqual(@as(usize, 2), module.structs[0].fields.len);
}

test "parse enum" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "enum Color { RED = 0, GREEN = 1, BLUE = 2 };";
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.enums);

    try std.testing.expectEqual(@as(usize, 1), module.enums.len);
    try std.testing.expectEqualStrings("Color", module.enums[0].name);
    try std.testing.expectEqual(@as(usize, 3), module.enums[0].values.len);
    try std.testing.expectEqual(@as(?i64, 0), module.enums[0].values[0].value);
}

test "parse function with docstring" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/** Adds two numbers */
        \\int add(int a, int b);
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expect(module.functions[0].doc != null);
}

test "parse function with doxygen params" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/**
        \\ * @brief Multiplies two integers.
        \\ * @param x First factor
        \\ * @param y Second factor
        \\ * @return Product of x and y
        \\ */
        \\int multiply(int x, int y);
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    const func = module.functions[0];
    try std.testing.expectEqualStrings("multiply", func.name);
    try std.testing.expect(func.doc != null);
    if (func.doc) |doc| {
        try std.testing.expectEqualStrings("Multiplies two integers.", doc.brief.?);
        try std.testing.expectEqual(@as(usize, 2), doc.params.len);
        try std.testing.expectEqualStrings("x", doc.params[0].name);
        try std.testing.expectEqualStrings("Product of x and y", doc.returns.?);
    }
}

test "parse multiple functions" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\int add(int a, int b);
        \\int subtract(int a, int b);
        \\int multiply(int x, int y);
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 3), module.functions.len);
    try std.testing.expectEqualStrings("add", module.functions[0].name);
    try std.testing.expectEqualStrings("subtract", module.functions[1].name);
    try std.testing.expectEqualStrings("multiply", module.functions[2].name);
}

test "parse struct with field docs" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/// A 2D point.
        \\struct Point {
        \\    int x; /**< X coordinate */
        \\    int y; ///< Y coordinate
        \\};
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.structs);

    try std.testing.expectEqual(@as(usize, 1), module.structs.len);
    const s = module.structs[0];
    try std.testing.expectEqualStrings("Point", s.name);
    try std.testing.expectEqual(@as(usize, 2), s.fields.len);
    try std.testing.expectEqualStrings("x", s.fields[0].name);
    try std.testing.expectEqualStrings("y", s.fields[1].name);
    // Check field docs
    try std.testing.expectEqualStrings("X coordinate", s.fields[0].doc.?);
    try std.testing.expectEqualStrings("Y coordinate", s.fields[1].doc.?);
}

test "parse enum with values and docs" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/**
        \\ * Log levels.
        \\ */
        \\enum LogLevel {
        \\    LOG_DEBUG = 0,   /**< Debug messages */
        \\    LOG_INFO = 1,    ///< Info messages
        \\    LOG_ERROR = 2
        \\};
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.enums);

    try std.testing.expectEqual(@as(usize, 1), module.enums.len);
    const e = module.enums[0];
    try std.testing.expectEqualStrings("LogLevel", e.name);
    try std.testing.expectEqual(@as(usize, 3), e.values.len);
    try std.testing.expectEqualStrings("LOG_DEBUG", e.values[0].name);
    try std.testing.expectEqual(@as(?i64, 0), e.values[0].value);
    try std.testing.expectEqualStrings("LOG_INFO", e.values[1].name);
    try std.testing.expectEqual(@as(?i64, 1), e.values[1].value);
}

test "parse typedef" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/// Unsigned 32-bit integer.
        \\typedef unsigned int uint32;
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.typedefs);

    try std.testing.expectEqual(@as(usize, 1), module.typedefs.len);
    const td = module.typedefs[0];
    try std.testing.expectEqualStrings("uint32", td.name);
    try std.testing.expectEqualStrings("unsigned int", td.underlying);
}

test "parse void function" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "void do_nothing(void);";
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.functions);

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expectEqualStrings("do_nothing", module.functions[0].name);
    try std.testing.expectEqualStrings("void", module.functions[0].return_type);
}

test "parse empty source" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source = "";
    const module = try parser.parse(source, "empty.h");

    try std.testing.expectEqual(@as(usize, 0), module.functions.len);
    try std.testing.expectEqual(@as(usize, 0), module.structs.len);
    try std.testing.expectEqual(@as(usize, 0), module.enums.len);
    try std.testing.expectEqual(@as(usize, 0), module.typedefs.len);
}

test "parse source with only comments" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/* This is a comment */
        \\// Another comment
        \\/** Doc comment without declaration */
    ;
    const module = try parser.parse(source, "comments.h");

    try std.testing.expectEqual(@as(usize, 0), module.functions.len);
}

test "parse object-like macro" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/** Version number */
        \\#define VERSION 1
    ;
    const module = try parser.parse(source, "test.h");
    defer std.testing.allocator.free(module.macros);

    try std.testing.expectEqual(@as(usize, 1), module.macros.len);
    try std.testing.expectEqualStrings("VERSION", module.macros[0].name);
    try std.testing.expectEqualStrings("1", module.macros[0].body);
    try std.testing.expect(module.macros[0].params == null);
    try std.testing.expect(module.macros[0].doc != null);
}

test "parse function-like macro" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\/**
        \\ * Returns the maximum of two values.
        \\ * @param a First value
        \\ * @param b Second value
        \\ */
        \\#define MAX(a, b) ((a) > (b) ? (a) : (b))
    ;
    const module = try parser.parse(source, "test.h");
    defer {
        if (module.macros.len > 0) {
            if (module.macros[0].params) |params| {
                std.testing.allocator.free(params);
            }
        }
        std.testing.allocator.free(module.macros);
    }

    try std.testing.expectEqual(@as(usize, 1), module.macros.len);
    const macro = module.macros[0];
    try std.testing.expectEqualStrings("MAX", macro.name);
    try std.testing.expect(macro.params != null);
    try std.testing.expectEqual(@as(usize, 2), macro.params.?.len);
    try std.testing.expectEqualStrings("a", macro.params.?[0]);
    try std.testing.expectEqualStrings("b", macro.params.?[1]);
    try std.testing.expect(macro.doc != null);
    if (macro.doc) |doc| {
        try std.testing.expectEqualStrings("Returns the maximum of two values.", doc.brief.?);
        try std.testing.expectEqual(@as(usize, 2), doc.params.len);
    }
}

test "parse multiple macros" {
    var parser = try CParser.init(std.testing.allocator);
    defer parser.deinit();

    const source =
        \\#define VERSION 1
        \\#define NAME "test"
        \\#define ADD(a, b) ((a) + (b))
    ;
    const module = try parser.parse(source, "test.h");
    defer {
        for (module.macros) |macro| {
            if (macro.params) |params| {
                std.testing.allocator.free(params);
            }
        }
        std.testing.allocator.free(module.macros);
    }

    try std.testing.expectEqual(@as(usize, 3), module.macros.len);
    try std.testing.expectEqualStrings("VERSION", module.macros[0].name);
    try std.testing.expectEqualStrings("NAME", module.macros[1].name);
    try std.testing.expectEqualStrings("ADD", module.macros[2].name);
}
