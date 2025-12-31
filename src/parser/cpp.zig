const std = @import("std");
const ts = @import("tree-sitter");
const ts_cpp = @import("tree-sitter-cpp");
const types = @import("../model/types.zig");
const DocstringExtractor = @import("../docstring/extractor.zig").DocstringExtractor;

/// C++ language parser using tree-sitter
pub const CppParser = struct {
    parser: *ts.Parser,
    language: *ts.Language,
    allocator: std.mem.Allocator,
    source: []const u8 = "",
    docstring_extractor: DocstringExtractor,

    const Self = @This();

    /// Creates a new C++ parser
    pub fn init(allocator: std.mem.Allocator) !Self {
        const language: *ts.Language = @ptrCast(@constCast(ts_cpp.language()));
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

    /// Parses C++ source code and extracts documentation
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
        var classes: std.ArrayList(types.Class) = .empty;
        var namespaces: std.ArrayList(types.Namespace) = .empty;

        const root = tree.?.rootNode();
        try self.walkNode(root, &functions, &structs, &enums, &typedefs, &macros, &classes, &namespaces, filename, null);

        return types.Module{
            .name = filename,
            .functions = try functions.toOwnedSlice(self.allocator),
            .structs = try structs.toOwnedSlice(self.allocator),
            .enums = try enums.toOwnedSlice(self.allocator),
            .typedefs = try typedefs.toOwnedSlice(self.allocator),
            .macros = try macros.toOwnedSlice(self.allocator),
            .classes = try classes.toOwnedSlice(self.allocator),
            .namespaces = try namespaces.toOwnedSlice(self.allocator),
        };
    }

    /// Gets text for a node from source
    fn getNodeText(self: *Self, node: ts.Node) []const u8 {
        const start = node.startByte();
        const end = node.endByte();
        if (start < self.source.len and end <= self.source.len and start < end) {
            return self.source[start..end];
        }
        return "";
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
        classes: *std.ArrayList(types.Class),
        namespaces: *std.ArrayList(types.Namespace),
        filename: []const u8,
        current_namespace: ?[]const u8,
    ) !void {
        const node_kind = node.kind();

        if (std.mem.eql(u8, node_kind, "function_definition") or
            std.mem.eql(u8, node_kind, "declaration"))
        {
            if (try self.extractFunctionPrototype(node, filename, current_namespace)) |func| {
                try functions.append(self.allocator, func);
            }
        } else if (std.mem.eql(u8, node_kind, "class_specifier")) {
            if (try self.extractClass(node, filename, current_namespace)) |class| {
                try classes.append(self.allocator, class);
            }
        } else if (std.mem.eql(u8, node_kind, "struct_specifier")) {
            if (try self.extractStruct(node, filename, current_namespace)) |s| {
                try structs.append(self.allocator, s);
            }
        } else if (std.mem.eql(u8, node_kind, "enum_specifier")) {
            if (try self.extractEnum(node, filename, current_namespace)) |e| {
                try enums.append(self.allocator, e);
            }
        } else if (std.mem.eql(u8, node_kind, "namespace_definition")) {
            // Extract namespace and process its body with updated namespace context
            const ns_info = self.extractNamespaceInfo(node, current_namespace);
            try namespaces.append(self.allocator, types.Namespace{
                .name = ns_info.full_name,
                .doc = self.findPrecedingDocstring(node),
            });
            // Process namespace body with new namespace context
            var i: u32 = 0;
            while (i < node.childCount()) : (i += 1) {
                if (node.child(i)) |child| {
                    if (std.mem.eql(u8, child.kind(), "declaration_list")) {
                        var j: u32 = 0;
                        while (j < child.childCount()) : (j += 1) {
                            if (child.child(j)) |body_child| {
                                try self.walkNode(body_child, functions, structs, enums, typedefs, macros, classes, namespaces, filename, ns_info.full_name);
                            }
                        }
                    }
                }
            }
            return; // Don't recurse normally for namespace nodes
        } else if (std.mem.eql(u8, node_kind, "type_definition")) {
            if (try self.extractTypedef(node, filename)) |td| {
                try typedefs.append(self.allocator, td);
            }
        } else if (std.mem.eql(u8, node_kind, "preproc_def") or
            std.mem.eql(u8, node_kind, "preproc_function_def"))
        {
            if (try self.extractMacro(node, filename)) |m| {
                try macros.append(self.allocator, m);
            }
        }

        // Recurse into children
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkNode(child, functions, structs, enums, typedefs, macros, classes, namespaces, filename, current_namespace);
            }
        }
    }

    /// Extracts namespace info (name and full path)
    const NamespaceInfo = struct {
        name: []const u8,
        full_name: []const u8,
    };

    fn extractNamespaceInfo(self: *Self, node: ts.Node, parent_namespace: ?[]const u8) NamespaceInfo {
        var ns_name: []const u8 = "anonymous";

        // Find namespace name
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "namespace_identifier") or
                    std.mem.eql(u8, child_kind, "identifier"))
                {
                    ns_name = self.getNodeText(child);
                    break;
                }
            }
        }

        // Build full namespace path
        const full_ns = if (parent_namespace) |parent|
            std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ parent, ns_name }) catch ns_name
        else
            ns_name;

        return NamespaceInfo{
            .name = ns_name,
            .full_name = full_ns,
        };
    }

    /// Extracts a class definition
    fn extractClass(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Class {
        var name: ?[]const u8 = null;
        var methods: std.ArrayList(types.Method) = .empty;
        var fields: std.ArrayList(types.ClassField) = .empty;
        var current_access: types.AccessSpecifier = .private;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_declaration_list")) {
                    try self.extractClassBody(child, &methods, &fields, &current_access);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findPrecedingDocstring(node);
        const start = node.startPoint();

        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Class{
            .name = full_name,
            .doc = doc,
            .methods = try methods.toOwnedSlice(self.allocator),
            .fields = try fields.toOwnedSlice(self.allocator),
            .namespace = namespace,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts class body
    fn extractClassBody(
        self: *Self,
        node: ts.Node,
        methods: *std.ArrayList(types.Method),
        fields: *std.ArrayList(types.ClassField),
        current_access: *types.AccessSpecifier,
    ) !void {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "access_specifier")) {
                    const spec_text = self.getNodeText(child);
                    if (std.mem.indexOf(u8, spec_text, "public") != null) {
                        current_access.* = .public;
                    } else if (std.mem.indexOf(u8, spec_text, "protected") != null) {
                        current_access.* = .protected;
                    } else if (std.mem.indexOf(u8, spec_text, "private") != null) {
                        current_access.* = .private;
                    }
                } else if (std.mem.eql(u8, child_kind, "function_definition") or
                    std.mem.eql(u8, child_kind, "declaration"))
                {
                    if (try self.extractMethod(child, current_access.*)) |method| {
                        try methods.append(self.allocator, method);
                    }
                } else if (std.mem.eql(u8, child_kind, "field_declaration")) {
                    if (self.extractClassField(child, current_access.*)) |field| {
                        try fields.append(self.allocator, field);
                    }
                }
            }
        }
    }

    /// Extracts a method
    fn extractMethod(self: *Self, node: ts.Node, access: types.AccessSpecifier) !?types.Method {
        var name: ?[]const u8 = null;
        var return_type: ?[]const u8 = null;
        var params: std.ArrayList(types.Parameter) = .empty;
        var is_virtual = false;
        var is_static = false;
        var is_const = false;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "virtual")) {
                    is_virtual = true;
                } else if (std.mem.eql(u8, child_kind, "storage_class_specifier")) {
                    if (std.mem.eql(u8, self.getNodeText(child), "static")) {
                        is_static = true;
                    }
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    if (return_type == null) {
                        return_type = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |fd_child| {
                            const fd_kind = fd_child.kind();
                            if (std.mem.eql(u8, fd_kind, "identifier") or
                                std.mem.eql(u8, fd_kind, "field_identifier"))
                            {
                                name = self.getNodeText(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "parameter_list")) {
                                params = try self.extractParameters(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "type_qualifier")) {
                                if (std.mem.eql(u8, self.getNodeText(fd_child), "const")) {
                                    is_const = true;
                                }
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        return types.Method{
            .name = name.?,
            .return_type = return_type orelse "void",
            .params = try params.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .access = access,
            .is_virtual = is_virtual,
            .is_static = is_static,
            .is_const = is_const,
        };
    }

    /// Extracts a class field
    fn extractClassField(self: *Self, node: ts.Node, access: types.AccessSpecifier) ?types.ClassField {
        var name: ?[]const u8 = null;
        var field_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    field_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.ClassField{
            .name = name.?,
            .type_str = field_type orelse "unknown",
            .doc = if (doc) |d| d.brief else null,
            .access = access,
        };
    }

    /// Extracts function prototype
    fn extractFunctionPrototype(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Function {
        var name: ?[]const u8 = null;
        var return_type: ?[]const u8 = null;
        var params: std.ArrayList(types.Parameter) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    if (return_type == null) {
                        return_type = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |fd_child| {
                            const fd_kind = fd_child.kind();
                            if (std.mem.eql(u8, fd_kind, "identifier")) {
                                name = self.getNodeText(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "parameter_list")) {
                                params = try self.extractParameters(fd_child);
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Function{
            .name = full_name,
            .return_type = return_type orelse "void",
            .params = try params.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts parameters
    fn extractParameters(self: *Self, node: ts.Node) !std.ArrayList(types.Parameter) {
        var params: std.ArrayList(types.Parameter) = .empty;
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "parameter_declaration")) {
                    if (self.extractParameter(child)) |param| {
                        try params.append(self.allocator, param);
                    }
                }
            }
        }
        return params;
    }

    /// Extracts a single parameter
    fn extractParameter(self: *Self, node: ts.Node) ?types.Parameter {
        var name: ?[]const u8 = null;
        var param_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    param_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        return types.Parameter{
            .name = name orelse "unnamed",
            .type_str = param_type orelse "unknown",
            .doc = null,
        };
    }

    /// Extracts struct
    fn extractStruct(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Struct {
        var name: ?[]const u8 = null;
        var fields: std.ArrayList(types.StructField) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_declaration_list")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |body_child| {
                            if (std.mem.eql(u8, body_child.kind(), "field_declaration")) {
                                if (self.extractStructField(body_child)) |field| {
                                    try fields.append(self.allocator, field);
                                }
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Struct{
            .name = full_name,
            .fields = try fields.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a struct field
    fn extractStructField(self: *Self, node: ts.Node) ?types.StructField {
        var name: ?[]const u8 = null;
        var field_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    field_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.StructField{
            .name = name.?,
            .type_str = field_type orelse "unknown",
            .doc = if (doc) |d| d.brief else null,
        };
    }

    /// Extracts enum
    fn extractEnum(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Enum {
        var name: ?[]const u8 = null;
        var values: std.ArrayList(types.EnumValue) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "enumerator_list")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |list_child| {
                            if (std.mem.eql(u8, list_child.kind(), "enumerator")) {
                                if (self.extractEnumValue(list_child)) |val| {
                                    try values.append(self.allocator, val);
                                }
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Enum{
            .name = full_name,
            .values = try values.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts enum value
    fn extractEnumValue(self: *Self, node: ts.Node) ?types.EnumValue {
        var name: ?[]const u8 = null;
        var value: ?i64 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "number_literal")) {
                    value = std.fmt.parseInt(i64, self.getNodeText(child), 0) catch null;
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.EnumValue{
            .name = name.?,
            .value = value,
            .doc = if (doc) |d| d.brief else null,
        };
    }

    /// Extracts typedef
    fn extractTypedef(self: *Self, node: ts.Node, filename: []const u8) !?types.Typedef {
        var name: ?[]const u8 = null;
        var underlying: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "type_identifier")) {
                    if (underlying == null) {
                        underlying = self.getNodeText(child);
                    } else {
                        name = self.getNodeText(child);
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        return types.Typedef{
            .name = name.?,
            .underlying = underlying orelse "unknown",
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts macro
    fn extractMacro(self: *Self, node: ts.Node, filename: []const u8) !?types.Macro {
        var name: ?[]const u8 = null;
        var body: ?[]const u8 = null;

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

        if (name == null) return null;

        const start = node.startPoint();
        return types.Macro{
            .name = name.?,
            .params = null,
            .body = body orelse "",
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Finds preceding docstring
    fn findPrecedingDocstring(self: *Self, node: ts.Node) ?types.DocString {
        var prev = node.prevSibling();
        while (prev != null) {
            const prev_kind = prev.?.kind();
            if (std.mem.eql(u8, prev_kind, "comment")) {
                const text = self.getNodeText(prev.?);
                if (std.mem.startsWith(u8, text, "/**") or
                    std.mem.startsWith(u8, text, "///"))
                {
                    return self.parseDocComment(text);
                }
            } else if (!std.mem.eql(u8, prev_kind, "preproc_ifdef") and
                !std.mem.eql(u8, prev_kind, "preproc_ifndef"))
            {
                break;
            }
            prev = prev.?.prevSibling();
        }
        return null;
    }

    /// Finds trailing docstring
    fn findTrailingDocstring(self: *Self, node: ts.Node) ?types.DocString {
        const next = node.nextSibling();
        if (next != null and std.mem.eql(u8, next.?.kind(), "comment")) {
            const text = self.getNodeText(next.?);
            if (std.mem.startsWith(u8, text, "/**<") or std.mem.startsWith(u8, text, "///<")) {
                return self.parseDocComment(text);
            }
        }
        return null;
    }

    /// Parses doc comment
    fn parseDocComment(self: *Self, text: []const u8) ?types.DocString {
        var result = text;
        if (std.mem.startsWith(u8, result, "/**<")) result = result[4..] else if (std.mem.startsWith(u8, result, "/**")) result = result[3..] else if (std.mem.startsWith(u8, result, "///<")) result = result[4..] else if (std.mem.startsWith(u8, result, "///")) result = result[3..];
        if (std.mem.endsWith(u8, result, "*/")) result = result[0 .. result.len - 2];
        result = std.mem.trim(u8, result, " \t\n\r");
        return self.docstring_extractor.parse(result) catch null;
    }
};

test "cpp parser init" {
    var parser = try CppParser.init(std.testing.allocator);
    defer parser.deinit();
}
