const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const cli = @import("cli.zig");
const types = @import("model/types.zig");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    var arg_parser = cli.ArgParser.init(allocator);
    var args = arg_parser.parse() catch |err| {
        switch (err) {
            error.MissingOutputFile => std.debug.print("Error: -o/--output requires a file path\n", .{}),
            error.UnknownOption => {},
            else => std.debug.print("Error parsing arguments: {}\n", .{err}),
        }
        arg_parser.printHelp();
        return;
    };
    defer args.deinit();

    // Handle help/version
    if (args.show_help) {
        arg_parser.printHelp();
        return;
    }

    if (args.show_version) {
        arg_parser.printVersion();
        return;
    }

    // Check for input files
    if (args.input_files.len == 0) {
        std.debug.print("Error: No input files specified\n\n", .{});
        arg_parser.printHelp();
        return;
    }

    // Initialize parser
    var parser = try CParser.init(allocator);
    defer parser.deinit();

    // Store sources and modules together so sources outlive module usage
    const FileData = struct {
        source: []const u8,
        module: types.Module,
    };

    var file_data: std.ArrayList(FileData) = .empty;
    defer {
        for (file_data.items) |data| {
            allocator.free(data.source);
        }
        file_data.deinit(allocator);
    }

    // Process each input file
    for (args.input_files) |input_file| {
        // Read file
        const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
            std.debug.print("Error: Cannot open file '{s}': {}\n", .{ input_file, err });
            continue;
        };
        defer file.close();

        const source = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error: Cannot read file '{s}': {}\n", .{ input_file, err });
            continue;
        };

        // Parse file
        const module = try parser.parse(source, input_file);
        try file_data.append(allocator, .{ .source = source, .module = module });
    }

    // Generate combined output
    var output_buffer: std.ArrayList(u8) = .empty;
    defer output_buffer.deinit(allocator);

    for (file_data.items) |data| {
        // Create a fresh generator for each module
        var gen = MarkdownGenerator.init(allocator);
        defer gen.deinit();

        const markdown = try gen.generate(data.module);
        try output_buffer.appendSlice(allocator, markdown);
    }

    // Write output
    if (args.output_file) |output_path| {
        // Write to file
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            std.debug.print("Error: Cannot create output file '{s}': {}\n", .{ output_path, err });
            return;
        };
        defer file.close();

        file.writeAll(output_buffer.items) catch |err| {
            std.debug.print("Error: Cannot write to file '{s}': {}\n", .{ output_path, err });
            return;
        };

        std.debug.print("Generated documentation: {s}\n", .{output_path});
    } else {
        // Write to stdout
        var buf: [8192]u8 = undefined;
        var file_writer = std.fs.File.stdout().writer(&buf);
        var stdout = &file_writer.interface;
        defer stdout.flush() catch {};

        try stdout.writeAll(output_buffer.items);
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
