const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const types = @import("model/types.zig");

pub fn main() !void {
    var buf: [8192]u8 = undefined;
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
        \\/** 
        \\ * Adds two integers together.
        \\ * @param a First operand
        \\ * @param b Second operand
        \\ * @return Sum of a and b
        \\ */
        \\int add(int a, int b) {
        \\    return a + b;
        \\}
        \\
        \\/** A simple 2D point structure. */
        \\struct Point {
        \\    int x; /**< X coordinate */
        \\    int y; /**< Y coordinate */
        \\};
        \\
        \\/** Color enumeration. */
        \\enum Color {
        \\    RED = 0,   /**< Red color */
        \\    GREEN = 1, /**< Green color */
        \\    BLUE = 2   /**< Blue color */
        \\};
        \\
        \\/// Typedef for unsigned 32-bit integer
        \\typedef unsigned int uint32;
    ;

    const module = try parser.parse(source, "example.h");

    // Generate markdown
    var md_gen = MarkdownGenerator.init(allocator);
    defer md_gen.deinit();

    const markdown = try md_gen.generate(module);

    try stdout.print("=== Generated Markdown ===\n\n", .{});
    try stdout.writeAll(markdown);
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
