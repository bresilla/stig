const std = @import("std");
const types = @import("model/types.zig");

/// Type of symbol for cross-referencing
pub const SymbolKind = enum {
    function,
    struct_type,
    enum_type,
    typedef,
    macro,
};

/// Information about a symbol's location in documentation
pub const SymbolInfo = struct {
    /// Kind of symbol
    kind: SymbolKind,
    /// Source file where defined
    source_file: []const u8,
    /// Anchor ID for linking (lowercase, hyphenated)
    anchor: []const u8,
    /// Original name
    name: []const u8,
};

/// Symbol table for cross-reference resolution
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(SymbolInfo),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .symbols = std.StringHashMap(SymbolInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free allocated anchors
        var iter = self.symbols.valueIterator();
        while (iter.next()) |info| {
            self.allocator.free(info.anchor);
        }
        self.symbols.deinit();
    }

    /// Registers a symbol in the table
    pub fn register(self: *Self, name: []const u8, kind: SymbolKind, source_file: []const u8) !void {
        const anchor = try self.generateAnchor(name);
        try self.symbols.put(name, SymbolInfo{
            .kind = kind,
            .source_file = source_file,
            .anchor = anchor,
            .name = name,
        });
    }

    /// Looks up a symbol by name
    pub fn lookup(self: *Self, name: []const u8) ?SymbolInfo {
        return self.symbols.get(name);
    }

    /// Generates a markdown anchor from a name (lowercase, replace spaces/underscores with hyphens)
    fn generateAnchor(self: *Self, name: []const u8) ![]u8 {
        var anchor = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z') {
                anchor[i] = c + 32; // lowercase
            } else if (c == '_' or c == ' ') {
                anchor[i] = '-';
            } else {
                anchor[i] = c;
            }
        }
        return anchor;
    }

    /// Builds symbol table from parsed modules
    pub fn buildFromModules(self: *Self, modules: []const types.Module) !void {
        for (modules) |module| {
            // Register functions
            for (module.functions) |func| {
                try self.register(func.name, .function, module.name);
            }

            // Register structs
            for (module.structs) |s| {
                try self.register(s.name, .struct_type, module.name);
            }

            // Register enums
            for (module.enums) |e| {
                try self.register(e.name, .enum_type, module.name);
            }

            // Register typedefs
            for (module.typedefs) |td| {
                try self.register(td.name, .typedef, module.name);
            }
        }
    }

    /// Generates a relative link to a symbol from a given context
    /// Returns null if symbol not found
    pub fn generateLink(self: *Self, symbol_name: []const u8, from_file: []const u8, output_format: OutputFormat) ?[]const u8 {
        const info = self.lookup(symbol_name) orelse return null;
        _ = from_file; // TODO: Calculate relative path
        _ = output_format;

        // For now, return a simple anchor link
        // In mdbook format, this would be more complex with relative paths
        return info.anchor;
    }

    pub const OutputFormat = enum {
        /// Single markdown file - use #anchor links
        markdown,
        /// mdbook structure - use relative path links
        mdbook,
    };
};

/// Cross-reference resolver for markdown generation
pub const XRefResolver = struct {
    symbol_table: *SymbolTable,
    current_file: []const u8,
    output_format: SymbolTable.OutputFormat,

    const Self = @This();

    pub fn init(symbol_table: *SymbolTable, current_file: []const u8, output_format: SymbolTable.OutputFormat) Self {
        return Self{
            .symbol_table = symbol_table,
            .current_file = current_file,
            .output_format = output_format,
        };
    }

    /// Resolves a type name to a markdown link if it exists in the symbol table
    /// Returns the original name if not found
    pub fn resolveTypeLink(self: *Self, type_name: []const u8) []const u8 {
        // Strip pointer/const qualifiers to get base type
        const base_type = self.extractBaseType(type_name);

        if (self.symbol_table.lookup(base_type)) |info| {
            _ = info;
            // For now, just return the base type
            // TODO: Generate actual link syntax
            return base_type;
        }

        return type_name;
    }

    /// Extracts the base type name from a type string
    /// e.g., "const struct Point *" -> "Point"
    fn extractBaseType(self: *Self, type_str: []const u8) []const u8 {
        _ = self;
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

        // Strip trailing pointer/reference
        result = std.mem.trimRight(u8, result, " *&");

        return result;
    }

    /// Generates a markdown link for a symbol
    pub fn makeLink(self: *Self, symbol_name: []const u8) ?LinkResult {
        const info = self.symbol_table.lookup(symbol_name) orelse return null;

        return LinkResult{
            .text = symbol_name,
            .anchor = info.anchor,
            .kind = info.kind,
            .target_file = info.source_file,
        };
    }

    pub const LinkResult = struct {
        text: []const u8,
        anchor: []const u8,
        kind: SymbolKind,
        target_file: []const u8,
    };
};

// Tests
test "symbol table registration and lookup" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.register("Point", .struct_type, "geometry.h");
    try table.register("add", .function, "math.h");

    const point_info = table.lookup("Point");
    try std.testing.expect(point_info != null);
    try std.testing.expectEqual(SymbolKind.struct_type, point_info.?.kind);
    try std.testing.expectEqualStrings("geometry.h", point_info.?.source_file);

    const add_info = table.lookup("add");
    try std.testing.expect(add_info != null);
    try std.testing.expectEqual(SymbolKind.function, add_info.?.kind);

    const missing = table.lookup("NonExistent");
    try std.testing.expect(missing == null);
}

test "anchor generation" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.register("MyStruct", .struct_type, "test.h");
    try table.register("some_function", .function, "test.h");

    const my_struct = table.lookup("MyStruct");
    try std.testing.expectEqualStrings("mystruct", my_struct.?.anchor);

    const some_func = table.lookup("some_function");
    try std.testing.expectEqualStrings("some-function", some_func.?.anchor);
}

test "extract base type" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    var resolver = XRefResolver.init(&table, "test.h", .markdown);

    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("Point"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("Point *"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("const Point *"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("struct Point"));
    try std.testing.expectEqualStrings("Color", resolver.extractBaseType("enum Color"));
}

test "build from modules" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    const modules = [_]types.Module{
        .{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "test_func",
                    .return_type = "int",
                    .params = &[_]types.Parameter{},
                    .location = .{ .file = "test.h", .line = 1, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{
                .{
                    .name = "TestStruct",
                    .fields = &[_]types.StructField{},
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    try table.buildFromModules(&modules);

    try std.testing.expect(table.lookup("test_func") != null);
    try std.testing.expect(table.lookup("TestStruct") != null);
}
