const std = @import("std");
const types = @import("../model/types.zig");
const xref = @import("../xref.zig");

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

    /// Generates markdown documentation for a module
    pub fn generate(self: *Self, module: types.Module) ![]const u8 {
        // Clear buffer for fresh generation
        self.buffer.clearRetainingCapacity();

        try self.writeHeader(module.name);

        // Functions section
        if (module.functions.len > 0) {
            try self.writeString("## Functions\n\n");
            for (module.functions) |func| {
                try self.writeFunction(func);
            }
        }

        // Structs section
        if (module.structs.len > 0) {
            try self.writeString("## Structures\n\n");
            for (module.structs) |s| {
                try self.writeStruct(s);
            }
        }

        // Enums section
        if (module.enums.len > 0) {
            try self.writeString("## Enumerations\n\n");
            for (module.enums) |e| {
                try self.writeEnum(e);
            }
        }

        // Typedefs section
        if (module.typedefs.len > 0) {
            try self.writeString("## Type Definitions\n\n");
            for (module.typedefs) |td| {
                try self.writeTypedef(td);
            }
        }

        // Macros section
        if (module.macros.len > 0) {
            try self.writeString("## Macros\n\n");
            for (module.macros) |macro| {
                try self.writeMacro(macro);
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

    /// Extracts the base type name from a type string
    /// e.g., "const struct Point *" -> "Point"
    /// e.g., "const struct Point* a" -> "Point" (handles param name in type)
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

        // Find the end of the type name (before * or space)
        // This handles cases like "Point* a" where param name is included
        var end: usize = 0;
        for (result, 0..) |c, i| {
            if (c == '*' or c == '&' or c == ' ') {
                break;
            }
            end = i + 1;
        }
        if (end > 0) {
            result = result[0..end];
        }

        return result;
    }

    /// Writes a type with optional cross-reference link
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
                    // Write prefix (e.g., "const ")
                    if (start > 0) {
                        try self.writeString(type_str[0..start]);
                    }
                    // Write linked type
                    try self.writeString(link.text);
                    // Write suffix (e.g., " *")
                    const end = start + base_type.len;
                    if (end < type_str.len) {
                        try self.writeString(type_str[end..]);
                    }
                    return;
                }
            }
        }
        // No cross-reference - write plain type
        try self.writeString(type_str);
    }

    /// Writes a symbol reference with optional cross-reference link (for @see tags)
    fn writeSymbolLink(self: *Self, symbol_name: []const u8) !void {
        if (self.symbol_table) |table| {
            if (table.lookup(symbol_name)) |info| {
                const link = try self.generateLink(symbol_name, info);
                defer if (link.needs_free) self.allocator.free(link.text);
                try self.writeString(link.text);
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
                // mdbook: use relative path links
                // For now, use simple anchor links within the same section
                const link_len = 1 + symbol_name.len + 2 + 1 + info.anchor.len + 1;
                const link_buf = try self.allocator.alloc(u8, link_len);
                _ = std.fmt.bufPrint(link_buf, "[{s}](#{s})", .{ symbol_name, info.anchor }) catch unreachable;
                return .{ .text = link_buf, .needs_free = true };
            },
        }
    }

    fn writeFunction(self: *Self, func: types.Function) !void {
        // Function name as heading
        try self.writeString("### `");
        try self.writeString(func.name);
        try self.writeString("`\n\n");

        // Code block with signature
        try self.writeString("```c\n");
        try self.writeString(func.return_type);
        try self.writeString(" ");
        try self.writeString(func.name);
        try self.writeString("(");

        for (func.params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.writeString(param.type_str);
            try self.writeString(" ");
            try self.writeString(param.name);
        }
        try self.writeString(");\n```\n\n");

        // Documentation
        if (func.doc) |doc| {
            if (doc.brief) |brief| {
                try self.writeString(brief);
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
                    try self.writeString(cleaned_lines.items);
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
                    try self.writeString(param.description);
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
                try self.writeString(ret);
                try self.writeString("\n\n");
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
                        try self.writeString("```c\n");
                        try self.writeString(example);
                        try self.writeString("\n```\n\n");
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

            // Since version
            if (doc.since) |since| {
                try self.writeString("**Since:** ");
                try self.writeString(since);
                try self.writeString("\n\n");
            }
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
                try self.writeString(brief);
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
                try self.writeString(brief);
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
                try self.writeString(brief);
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
                try self.writeString(brief);
                try self.writeString("\n\n");
            }

            // Parameters for function-like macros
            if (doc.params.len > 0) {
                try self.writeString("**Parameters:**\n");
                for (doc.params) |param| {
                    try self.writeString("- `");
                    try self.writeString(param.name);
                    try self.writeString("`: ");
                    try self.writeString(param.description);
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
