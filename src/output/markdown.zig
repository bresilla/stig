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
