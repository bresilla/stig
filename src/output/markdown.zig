const std = @import("std");
const types = @import("../model/types.zig");

/// Markdown output generator
pub const MarkdownGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
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

            if (doc.returns) |ret| {
                try self.writeString("**Returns:** ");
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

            // See also
            if (doc.see_also.len > 0) {
                try self.writeString("**See also:** ");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeString("`");
                    try self.writeString(ref);
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

        // Fields documentation
        if (s.fields.len > 0) {
            try self.writeString("**Fields:**\n");
            for (s.fields) |field| {
                try self.writeString("- `");
                try self.writeString(field.name);
                try self.writeString("`");
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
