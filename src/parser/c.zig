const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const types = @import("../model/types.zig");

/// C language parser using tree-sitter
pub const CParser = struct {
    parser: *ts.Parser,
    language: *ts.Language,
    allocator: std.mem.Allocator,
    source: []const u8 = "",

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
        };
    }

    /// Destroys the parser and frees resources
    pub fn deinit(self: *Self) void {
        self.parser.destroy();
        self.language.destroy();
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
            };
        }
        defer tree.?.destroy();

        var functions: std.ArrayList(types.Function) = .empty;
        var structs: std.ArrayList(types.Struct) = .empty;
        var enums: std.ArrayList(types.Enum) = .empty;
        var typedefs: std.ArrayList(types.Typedef) = .empty;

        const root = tree.?.rootNode();
        try self.walkNode(root, &functions, &structs, &enums, &typedefs, filename);

        return types.Module{
            .name = filename,
            .functions = try functions.toOwnedSlice(self.allocator),
            .structs = try structs.toOwnedSlice(self.allocator),
            .enums = try enums.toOwnedSlice(self.allocator),
            .typedefs = try typedefs.toOwnedSlice(self.allocator),
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
        }

        // Recurse into children
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkNode(child, functions, structs, enums, typedefs, filename);
            }
        }
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

        const start = node.startPoint();
        return types.Function{
            .name = func_name,
            .return_type = return_type,
            .params = params,
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

            const start = node.startPoint();
            return types.Function{
                .name = func_name,
                .return_type = return_type,
                .params = params,
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

        // Get fields
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

        const start = node.startPoint();
        return types.Struct{
            .name = name,
            .fields = try fields.toOwnedSlice(self.allocator),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a struct field
    fn extractField(self: *Self, node: ts.Node) ?types.StructField {
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
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        if (name.len > 0) {
            return types.StructField{
                .name = name,
                .type_str = type_str,
            };
        }
        return null;
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

        const start = node.startPoint();
        return types.Enum{
            .name = name,
            .values = try values.toOwnedSlice(self.allocator),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts an enum value
    fn extractEnumValue(self: *Self, node: ts.Node) !?types.EnumValue {
        var name: []const u8 = "";
        var value: ?i64 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "number_literal")) {
                    const num_text = self.getNodeText(child);
                    value = std.fmt.parseInt(i64, num_text, 0) catch null;
                }
            }
        }

        if (name.len > 0) {
            return types.EnumValue{
                .name = name,
                .value = value,
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
            const start = node.startPoint();
            return types.Typedef{
                .name = name,
                .underlying = underlying,
                .location = types.SourceLocation{
                    .file = filename,
                    .line = start.row + 1,
                    .column = start.column + 1,
                },
            };
        }
        return null;
    }

    /// Gets the text content of a node
    fn getNodeText(self: *Self, node: ts.Node) []const u8 {
        const start = node.startByte();
        const end = node.endByte();
        if (start < self.source.len and end <= self.source.len and start < end) {
            return self.source[start..end];
        }
        return "";
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
