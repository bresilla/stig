const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
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

    // Collect modules for generation
    var modules: std.ArrayList(types.Module) = .empty;
    defer modules.deinit(allocator);

    for (file_data.items) |data| {
        try modules.append(allocator, data.module);
    }

    // Generate output based on format
    switch (args.output_format) {
        .mdbook => {
            // Generate mdbook structure
            const output_dir = args.output_file orelse "docs";
            const config = MdbookConfig{
                .title = args.book_title orelse "API Reference",
                .output_dir = output_dir,
            };

            var mdbook_gen = MdbookGenerator.initWithConfig(allocator, config);
            defer mdbook_gen.deinit();

            mdbook_gen.generate(modules.items) catch |err| {
                std.debug.print("Error generating mdbook: {}\n", .{err});
                return;
            };

            std.debug.print("Generated mdbook structure in: {s}/\n", .{output_dir});
            std.debug.print("Run 'mdbook build {s}' to build the book\n", .{output_dir});
        },
        .markdown => {
            // Generate single markdown output
            var output_buffer: std.ArrayList(u8) = .empty;
            defer output_buffer.deinit(allocator);

            for (modules.items) |module| {
                var gen = MarkdownGenerator.init(allocator);
                defer gen.deinit();

                const markdown = try gen.generate(module);
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
                const stdout = &file_writer.interface;
                defer stdout.flush() catch {};

                try stdout.writeAll(output_buffer.items);
            }
        },
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
