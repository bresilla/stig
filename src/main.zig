const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const types = @import("model/types.zig");

pub fn main() !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &file_writer.interface;
    defer stdout.flush() catch {};

    try stdout.print("stinger v0.1.0 - C/C++ documentation generator\n", .{});
    try stdout.print("Using tree-sitter for parsing\n\n", .{});

    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize parser
    var parser = try CParser.init(allocator);
    defer parser.deinit();

    // Test parsing a simple C snippet
    const source =
        \\/// Adds two integers together.
        \\/// @param a First operand
        \\/// @param b Second operand
        \\/// @return Sum of a and b
        \\int add(int a, int b) {
        \\    return a + b;
        \\}
        \\
        \\/// A simple 2D point structure.
        \\struct Point {
        \\    int x; ///< X coordinate
        \\    int y; ///< Y coordinate
        \\};
        \\
        \\/// Color enumeration.
        \\enum Color {
        \\    RED = 0,
        \\    GREEN = 1,
        \\    BLUE = 2
        \\};
    ;

    const module = try parser.parse(source, "example.c");

    try stdout.print("Parsed module: {s}\n\n", .{module.name});

    // Print functions
    try stdout.print("Functions ({d}):\n", .{module.functions.len});
    for (module.functions) |func| {
        try stdout.print("  - {s} {s}(", .{ func.return_type, func.name });
        for (func.params, 0..) |param, i| {
            if (i > 0) try stdout.print(", ", .{});
            try stdout.print("{s} {s}", .{ param.type_str, param.name });
        }
        try stdout.print(") at line {d}\n", .{func.location.line});
    }

    // Print structs
    try stdout.print("\nStructures ({d}):\n", .{module.structs.len});
    for (module.structs) |s| {
        try stdout.print("  - struct {s} at line {d}\n", .{ s.name, s.location.line });
        for (s.fields) |field| {
            try stdout.print("      {s} {s}\n", .{ field.type_str, field.name });
        }
    }

    // Print enums
    try stdout.print("\nEnumerations ({d}):\n", .{module.enums.len});
    for (module.enums) |e| {
        try stdout.print("  - enum {s} at line {d}\n", .{ e.name, e.location.line });
        for (e.values) |val| {
            if (val.value) |v| {
                try stdout.print("      {s} = {d}\n", .{ val.name, v });
            } else {
                try stdout.print("      {s}\n", .{val.name});
            }
        }
    }
}

test "parser initialization" {
    const language: *ts.Language = @ptrCast(@constCast(ts_c.language()));
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = parser.parseString("int x;", null);
    try std.testing.expect(tree != null);
    defer if (tree) |t| t.destroy();

    if (tree) |t| {
        const root = t.rootNode();
        try std.testing.expectEqualStrings("translation_unit", root.kind());
    }
}
