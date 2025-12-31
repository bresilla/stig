const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const CppParser = @import("parser/cpp.zig").CppParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
const cli = @import("cli.zig");
const config_mod = @import("config.zig");
const types = @import("model/types.zig");
const preprocessor = @import("preprocessor.zig");
const Watcher = @import("watch.zig").Watcher;

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check for preprocessor subcommand first
    var args_iter = std.process.args();
    _ = args_iter.skip(); // Skip program name
    if (args_iter.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "preprocessor") or std.mem.eql(u8, first_arg, "preprocess")) {
            // Check for "supports" subcommand (mdbook calls: stinger preprocessor supports <renderer>)
            if (args_iter.next()) |second_arg| {
                if (std.mem.eql(u8, second_arg, "supports")) {
                    // We support all renderers (html, pdf, etc.)
                    // Exit with 0 to indicate support
                    return;
                }
            }
            // Run as mdbook preprocessor - use page allocator to avoid leak reports on stderr
            preprocessor.runPreprocessor(std.heap.page_allocator) catch |err| {
                std.debug.print("Preprocessor error: {}\n", .{err});
                return;
            };
            return;
        }
        // Handle mdbook's "supports" check (for direct invocation: stinger supports <renderer>)
        if (std.mem.eql(u8, first_arg, "supports")) {
            // We support all renderers (html, pdf, etc.)
            // Exit with 0 to indicate support
            return;
        }
    }

    // Parse CLI arguments
    var arg_parser = cli.ArgParser.init(allocator);
    var args = arg_parser.parse() catch |err| {
        switch (err) {
            error.MissingOutputFile => std.debug.print("Error: -o/--output requires a file path\n", .{}),
            error.MissingConfigFile => std.debug.print("Error: -c/--config requires a file path\n", .{}),
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

    // Load config file
    const config_path = args.config_file orelse "stinger.toml";
    var toml_parser: ?*config_mod.TomlParser = null;
    var config: config_mod.Config = config_mod.Config{};

    if (config_mod.loadFromFile(allocator, config_path)) |result| {
        toml_parser = result.parser;
        config = result.config;
    } else |err| {
        if (args.config_file != null) {
            // Only error if user explicitly specified a config file
            std.debug.print("Error: Cannot load config file '{s}': {}\n", .{ config_path, err });
            return;
        }
        // Use default config if stinger.toml doesn't exist - this is fine
    }

    defer {
        if (toml_parser) |p| {
            p.deinit();
            allocator.destroy(p);
        }
    }

    // Merge CLI args with config (CLI takes precedence)
    cli.ArgParser.mergeWithConfig(&args, config);

    // Check for input files (from CLI or config)
    var input_files = args.input_files;
    if (input_files.len == 0 and config.input_patterns.len > 0) {
        // Use input patterns from config
        input_files = config.input_patterns;
    }

    if (input_files.len == 0) {
        std.debug.print("Error: No input files specified\n\n", .{});
        arg_parser.printHelp();
        return;
    }

    // Watch mode
    if (args.watch_mode) {
        if (args.output_format != .mdbook) {
            std.debug.print("Error: Watch mode requires mdbook format (-f mdbook)\n", .{});
            return;
        }
        const output_dir = args.output_file orelse config.output_dir;
        if (output_dir.len == 0) {
            std.debug.print("Error: Watch mode requires output directory (-o <dir>)\n", .{});
            return;
        }

        var watcher = Watcher.init(
            allocator,
            input_files,
            output_dir,
            args.book_title orelse config.title,
            args.serve_mode,
        );
        defer watcher.deinit();

        watcher.run() catch |err| {
            std.debug.print("Watch error: {}\n", .{err});
        };
        return;
    }

    // Initialize parsers
    var c_parser = try CParser.init(allocator);
    defer c_parser.deinit();

    var cpp_parser = try CppParser.init(allocator);
    defer cpp_parser.deinit();

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

        // Set base path for include directives (directory containing the source file)
        const base_path = std.fs.path.dirname(input_file) orelse ".";
        c_parser.setBasePath(base_path);
        cpp_parser.setBasePath(base_path);

        // Choose parser based on file extension
        const is_cpp = isCppFile(input_file);
        const module = if (is_cpp)
            try cpp_parser.parse(source, input_file)
        else
            try c_parser.parse(source, input_file);

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
            const output_dir = args.output_file orelse config.output_dir;
            const mdbook_config = MdbookConfig{
                .title = args.book_title orelse config.title,
                .output_dir = output_dir,
                .generate_intro = config.generate_intro,
            };

            var mdbook_gen = MdbookGenerator.initWithConfig(allocator, mdbook_config);
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

/// Checks if a file is a C++ file based on extension
fn isCppFile(filename: []const u8) bool {
    const cpp_extensions = [_][]const u8{ ".cpp", ".cxx", ".cc", ".hpp", ".hxx", ".hh", ".C", ".H" };
    for (cpp_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
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
