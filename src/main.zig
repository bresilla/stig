const std = @import("std");
const ts = @import("tree-sitter");
const ts_c = @import("tree-sitter-c");
const CParser = @import("parser/c.zig").CParser;
const CppParser = @import("parser/cpp.zig").CppParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;
const MdbookGenerator = @import("output/mdbook.zig").MdbookGenerator;
const MdbookConfig = @import("output/mdbook.zig").MdbookConfig;
const JsonGenerator = @import("output/json.zig").JsonGenerator;
const xref = @import("xref.zig");
const cli = @import("cli.zig");
const config_mod = @import("config.zig");
const types = @import("model/types.zig");
const preprocessor = @import("preprocessor.zig");
const Watcher = @import("watch.zig").Watcher;
const coverage = @import("coverage.zig");
const snippet = @import("snippet.zig");
const lint = @import("lint.zig");
const cache_mod = @import("cache.zig");
const lsp_server = @import("lsp/server.zig");
const init_cmd = @import("init.zig");
const testing_cmd = @import("testing.zig");
const testcov = @import("testcov.zig");

pub fn main() !void {
    // Get allocator - disable safety checks to avoid leak warnings
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    var arg_parser = cli.ArgParser.init(allocator);
    defer arg_parser.deinit();

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

    // Handle subcommands
    switch (args.subcommand) {
        .help => {
            arg_parser.printHelp();
            return;
        },
        .help_generate => {
            cli.ArgParser.printGenerateHelp();
            return;
        },
        .help_check => {
            cli.ArgParser.printCheckHelp();
            return;
        },
        .help_init => {
            cli.ArgParser.printInitHelp();
            return;
        },
        .help_test => {
            cli.ArgParser.printTestHelp();
            return;
        },
        .help_coverage => {
            cli.ArgParser.printCoverageHelp();
            return;
        },
        .version => {
            arg_parser.printVersion();
            return;
        },
        .preprocessor => {
            // Run as mdbook preprocessor
            preprocessor.runPreprocessor(std.heap.page_allocator) catch |err| {
                std.debug.print("Preprocessor error: {}\n", .{err});
                return;
            };
            return;
        },
        .check => {
            try runCheckCommand(allocator, &args);
            return;
        },
        .check_lsp => {
            // Run as LSP server for editor integration
            lsp_server.runServer(allocator) catch |err| {
                std.debug.print("LSP server error: {}\n", .{err});
                return;
            };
            return;
        },
        .init => {
            init_cmd.runInit(allocator, args.config_file, args.force_rebuild) catch |err| {
                std.debug.print("Init error: {}\n", .{err});
                return;
            };
            return;
        },
        .@"test" => {
            const output_format: testing_cmd.TestOutputFormat = switch (args.check_output_format) {
                .human => .console,
                .json => .json,
                .compiler => .junit,
            };
            const exit_code = testing_cmd.runTest(allocator, args.input_files, args.config_file, output_format) catch |err| {
                std.debug.print("Test error: {}\n", .{err});
                std.process.exit(1);
            };
            std.process.exit(exit_code);
        },
        .coverage => {
            const exit_code = runCoverageCommand(allocator, &args) catch |err| {
                std.debug.print("Coverage error: {}\n", .{err});
                std.process.exit(1);
            };
            std.process.exit(exit_code);
        },
        .generate => {
            try runGenerateCommand(allocator, &args, &arg_parser);
            return;
        },
    }
}

/// Runs the 'check' subcommand - documentation coverage and quality checks
fn runCheckCommand(allocator: std.mem.Allocator, args: *cli.Args) !void {
    // Load config file
    const config_path = args.config_file orelse "stig.toml";
    var config_loader: ?*config_mod.ConfigLoader = null;
    var config: config_mod.Config = config_mod.Config{};

    if (config_mod.loadFromFile(allocator, config_path)) |result| {
        config_loader = result.loader;
        config = result.config;
    } else |err| {
        if (args.config_file != null) {
            std.debug.print("Error: Cannot load config file '{s}': {}\n", .{ config_path, err });
            return;
        }
    }

    defer {
        if (config_loader) |loader| {
            loader.deinit();
            allocator.destroy(loader);
        }
    }

    // Get input files
    var input_patterns = args.input_files;
    if (input_patterns.len == 0 and config.input_patterns.len > 0) {
        input_patterns = config.input_patterns;
    }

    if (input_patterns.len == 0) {
        std.debug.print("Error: No input files specified\n\n", .{});
        cli.ArgParser.printCheckHelp();
        return;
    }

    // Expand glob patterns
    var expanded_files: std.ArrayList([]const u8) = .empty;
    defer {
        for (expanded_files.items) |f| {
            allocator.free(f);
        }
        expanded_files.deinit(allocator);
    }

    for (input_patterns) |pattern| {
        if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
            try expandGlob(allocator, pattern, &expanded_files);
        } else {
            const path_copy = try allocator.dupe(u8, pattern);
            try expanded_files.append(allocator, path_copy);
        }
    }

    const input_files = expanded_files.items;

    if (input_files.len == 0) {
        std.debug.print("Error: No files matched the input patterns\n\n", .{});
        return;
    }

    // Initialize parsers
    var c_parser = try CParser.init(allocator);
    defer c_parser.deinit();

    var cpp_parser = try CppParser.init(allocator);
    defer cpp_parser.deinit();

    // Parse files
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

    for (input_files) |input_file| {
        // Skip implementation files - only check headers for documentation
        if (!isHeaderFile(input_file)) {
            std.debug.print("Skipping implementation file: {s}\n", .{input_file});
            continue;
        }

        const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
            std.debug.print("Error: Cannot open file '{s}': {}\n", .{ input_file, err });
            continue;
        };
        defer file.close();

        const source = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error: Cannot read file '{s}': {}\n", .{ input_file, err });
            continue;
        };

        const base_path = std.fs.path.dirname(input_file) orelse ".";
        c_parser.setBasePath(base_path);
        cpp_parser.setBasePath(base_path);

        const is_cpp = isCppFile(input_file);
        const module = if (is_cpp)
            try cpp_parser.parse(source, input_file)
        else
            try c_parser.parse(source, input_file);

        try file_data.append(allocator, .{ .source = source, .module = module });
    }

    // Collect modules
    var modules: std.ArrayList(types.Module) = .empty;
    defer modules.deinit(allocator);

    for (file_data.items) |data| {
        try modules.append(allocator, data.module);
    }

    // Run coverage analysis
    const min_coverage = args.min_coverage orelse config.coverage.min_coverage;
    const coverage_config = coverage.CoverageConfig{
        .min_coverage = min_coverage,
        .require_param_docs = config.coverage.require_param_docs,
        .require_return_docs = config.coverage.require_return_docs,
        .require_tparam_docs = config.coverage.require_tparam_docs,
        .exclude_patterns = config.coverage.exclude_patterns,
    };

    var report = try coverage.analyze(allocator, modules.items, coverage_config);
    defer report.deinit();

    // Also run lint checks for additional validation
    var symbol_table = xref.SymbolTable.init(allocator);
    defer symbol_table.deinit();
    try symbol_table.buildFromModules(modules.items);

    const lint_config = lint.LintConfig{
        .enabled = config.lint.enabled,
        .treat_warnings_as_errors = args.strict or config.lint.treat_warnings_as_errors,
        .max_brief_length = config.lint.max_brief_length,
        .require_brief = config.lint.require_brief,
        .require_param_docs = config.lint.require_param_docs,
        .require_return_docs = config.lint.require_return_docs,
        .require_tparam_docs = config.lint.require_tparam_docs,
        .check_cross_references = config.lint.check_cross_references,
        .require_brief_period = config.lint.require_brief_period,
        .exclude_patterns = config.lint.exclude_patterns,
    };

    var linter = lint.Linter.init(allocator, lint_config);
    linter.setSymbolTable(&symbol_table);

    var lint_report = try linter.lint(modules.items);
    defer lint_report.deinit();

    // Output based on format
    switch (args.check_output_format) {
        .human => {
            // Print coverage report
            coverage.printHumanReport(report);

            // Print lint issues if any
            if (lint_report.issues.items.len > 0) {
                lint.printReport(lint_report);
            }
        },
        .compiler => {
            // Print in compiler-style format for CI/CD
            coverage.printCompilerReport(report);

            // Also print lint issues in compiler format
            for (lint_report.issues.items) |issue| {
                const severity_str = switch (issue.severity) {
                    .@"error" => "error",
                    .warning => "warning",
                    .info => "note",
                };
                if (issue.line > 0) {
                    std.debug.print("{s}:{d}:1: {s}: [{s}] {s} in {s} '{s}'\n", .{
                        issue.file,
                        issue.line,
                        severity_str,
                        issue.code,
                        issue.message,
                        issue.entity_type,
                        issue.entity_name,
                    });
                } else {
                    std.debug.print("{s}:1:1: {s}: [{s}] {s} in {s} '{s}'\n", .{
                        issue.file,
                        severity_str,
                        issue.code,
                        issue.message,
                        issue.entity_type,
                        issue.entity_name,
                    });
                }
            }
        },
        .json => {
            try coverage.printJsonReport(allocator, report);
        },
    }

    // Determine exit code
    var exit_code: u8 = 0;

    // Check coverage threshold
    if (report.overallPercentage() < @as(f64, @floatFromInt(min_coverage))) {
        if (args.check_output_format == .human) {
            std.debug.print("Coverage ({d:.0}%) is below minimum threshold ({d}%)\n", .{
                report.overallPercentage(),
                min_coverage,
            });
        }
        exit_code = 2;
    }

    // Check for lint errors
    if (lint_report.hasErrors()) {
        exit_code = 1;
    }

    // Check for warnings with strict mode
    if (args.strict and lint_report.hasWarnings()) {
        exit_code = 2;
    }

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

/// Runs the 'coverage' subcommand - test coverage analysis
fn runCoverageCommand(allocator: std.mem.Allocator, args: *cli.Args) !u8 {
    // Load config file
    const config_path = args.config_file orelse "stig.toml";
    var config_loader: ?*config_mod.ConfigLoader = null;
    var config: config_mod.Config = config_mod.Config{};

    if (config_mod.loadFromFile(allocator, config_path)) |result| {
        config_loader = result.loader;
        config = result.config;
    } else |err| {
        if (args.config_file != null) {
            std.debug.print("Error: Cannot load config file '{s}': {}\n", .{ config_path, err });
            return 1;
        }
    }

    defer {
        if (config_loader) |loader| {
            loader.deinit();
            allocator.destroy(loader);
        }
    }

    // Get source files (headers to analyze)
    var source_patterns = args.input_files;
    if (source_patterns.len == 0 and config.input_patterns.len > 0) {
        source_patterns = config.input_patterns;
    }

    // Get test file patterns from config
    var test_patterns = config.test_coverage.test_patterns;
    if (test_patterns.len == 0) {
        // Default test patterns
        test_patterns = &[_][]const u8{ "test/**/*.cpp", "tests/**/*.cpp" };
    }

    if (source_patterns.len == 0) {
        std.debug.print("Error: No source files specified\n", .{});
        std.debug.print("Specify header files in stig.toml [input] or on command line\n\n", .{});
        cli.ArgParser.printCoverageHelp();
        return 1;
    }

    // Expand source file patterns
    var expanded_sources: std.ArrayList([]const u8) = .empty;
    defer {
        for (expanded_sources.items) |f| {
            allocator.free(f);
        }
        expanded_sources.deinit(allocator);
    }

    for (source_patterns) |pattern| {
        if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
            try expandGlob(allocator, pattern, &expanded_sources);
        } else {
            const path_copy = try allocator.dupe(u8, pattern);
            try expanded_sources.append(allocator, path_copy);
        }
    }

    // Expand test file patterns
    var expanded_tests: std.ArrayList([]const u8) = .empty;
    defer {
        for (expanded_tests.items) |f| {
            allocator.free(f);
        }
        expanded_tests.deinit(allocator);
    }

    for (test_patterns) |pattern| {
        if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
            try expandGlob(allocator, pattern, &expanded_tests);
        } else {
            const path_copy = try allocator.dupe(u8, pattern);
            try expanded_tests.append(allocator, path_copy);
        }
    }

    if (expanded_sources.items.len == 0) {
        std.debug.print("Error: No source files matched the patterns\n", .{});
        return 1;
    }

    if (expanded_tests.items.len == 0) {
        std.debug.print("Warning: No test files found matching patterns\n", .{});
        std.debug.print("Configure test patterns in stig.toml:\n", .{});
        std.debug.print("  [test_coverage]\n", .{});
        std.debug.print("  test_patterns = [\"test/**/*.cpp\"]\n\n", .{});
    }

    // Initialize parsers
    var c_parser = try CParser.init(allocator);
    defer c_parser.deinit();

    var cpp_parser = try CppParser.init(allocator);
    defer cpp_parser.deinit();

    // Parse source files to build symbol table
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

    for (expanded_sources.items) |input_file| {
        // Only process header files
        if (!isHeaderFile(input_file)) continue;

        const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
            std.debug.print("Warning: Cannot open file '{s}': {}\n", .{ input_file, err });
            continue;
        };
        defer file.close();

        const source = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Warning: Cannot read file '{s}': {}\n", .{ input_file, err });
            continue;
        };

        const base_path = std.fs.path.dirname(input_file) orelse ".";
        c_parser.setBasePath(base_path);
        cpp_parser.setBasePath(base_path);

        const is_cpp = isCppFile(input_file);
        const module = if (is_cpp)
            try cpp_parser.parse(source, input_file)
        else
            try c_parser.parse(source, input_file);

        try file_data.append(allocator, .{ .source = source, .module = module });
    }

    // Collect modules and build symbol table
    var modules: std.ArrayList(types.Module) = .empty;
    defer modules.deinit(allocator);

    for (file_data.items) |data| {
        try modules.append(allocator, data.module);
    }

    var symbol_table = xref.SymbolTable.init(allocator);
    defer symbol_table.deinit();
    try symbol_table.buildFromModules(modules.items);

    // Run test coverage analysis
    var analyzer = testcov.TestCoverageAnalyzer.init(allocator, &symbol_table);
    defer analyzer.deinit();

    var report = try analyzer.analyzeTestFiles(expanded_tests.items);
    defer report.deinit();

    // Output based on format
    switch (args.check_output_format) {
        .human => testcov.printHumanReport(report),
        .compiler => testcov.printCompilerReport(report),
        .json => try testcov.printJsonReport(allocator, report),
    }

    // Check coverage threshold
    const min_coverage = args.min_coverage orelse config.test_coverage.min_coverage;
    if (report.stats.percentage() < @as(f64, @floatFromInt(min_coverage))) {
        if (args.check_output_format == .human) {
            std.debug.print("Test coverage ({d:.0}%) is below minimum threshold ({d}%)\n", .{
                report.stats.percentage(),
                min_coverage,
            });
        }
        return 1;
    }

    return 0;
}

/// Runs the 'generate' subcommand - documentation generation
fn runGenerateCommand(allocator: std.mem.Allocator, args: *cli.Args, arg_parser: *cli.ArgParser) !void {
    // Load config file
    const config_path = args.config_file orelse "stig.toml";
    var config_loader: ?*config_mod.ConfigLoader = null;
    var config: config_mod.Config = config_mod.Config{};

    if (config_mod.loadFromFile(allocator, config_path)) |result| {
        config_loader = result.loader;
        config = result.config;
    } else |err| {
        if (args.config_file != null) {
            std.debug.print("Error: Cannot load config file '{s}': {}\n", .{ config_path, err });
            return;
        }
    }

    defer {
        if (config_loader) |loader| {
            loader.deinit();
            allocator.destroy(loader);
        }
    }

    // Merge CLI args with config
    cli.ArgParser.mergeWithConfig(args, config);

    // Get input files
    var input_patterns = args.input_files;
    if (input_patterns.len == 0 and config.input_patterns.len > 0) {
        input_patterns = config.input_patterns;
    }

    if (input_patterns.len == 0) {
        std.debug.print("Error: No input files specified\n\n", .{});
        arg_parser.printHelp();
        return;
    }

    // Expand glob patterns
    var expanded_files: std.ArrayList([]const u8) = .empty;
    defer {
        for (expanded_files.items) |f| {
            allocator.free(f);
        }
        expanded_files.deinit(allocator);
    }

    for (input_patterns) |pattern| {
        if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
            try expandGlob(allocator, pattern, &expanded_files);
        } else {
            const path_copy = try allocator.dupe(u8, pattern);
            try expanded_files.append(allocator, path_copy);
        }
    }

    const input_files = expanded_files.items;

    if (input_files.len == 0) {
        std.debug.print("Error: No files matched the input patterns\n\n", .{});
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

    // Store sources and modules together
    const FileData = struct {
        source: []const u8,
        module: types.Module,
        path: []const u8,
    };

    var file_data: std.ArrayList(FileData) = .empty;
    defer {
        for (file_data.items) |data| {
            allocator.free(data.source);
        }
        file_data.deinit(allocator);
    }

    // Initialize incremental cache for mdbook format
    var incr_cache: ?cache_mod.IncrementalCache = null;
    defer if (incr_cache) |*c| c.deinit();

    const cache_output_dir = args.output_file orelse config.output_dir;
    if (args.output_format == .mdbook and !args.force_rebuild and cache_output_dir.len > 0) {
        incr_cache = cache_mod.IncrementalCache.init(allocator, cache_output_dir) catch null;
        if (incr_cache) |*c| {
            c.load() catch {};
        }
    }

    var files_skipped: usize = 0;
    var files_rebuilt: usize = 0;

    // Pre-scan: read all files and determine which need rebuilding
    // This is needed to correctly handle dependency chains
    const PreScanData = struct {
        path: []const u8,
        source: []const u8,
        needs_rebuild: bool,
    };

    var prescan_data: std.ArrayList(PreScanData) = .empty;
    defer {
        for (prescan_data.items) |data| {
            if (!data.needs_rebuild) {
                // Only free sources for skipped files; rebuilt files are freed later
                allocator.free(data.source);
            }
        }
        prescan_data.deinit(allocator);
    }

    // First pass: read all files
    for (input_files) |input_file| {
        // Skip implementation files - only check headers for documentation
        if (!isHeaderFile(input_file)) {
            std.debug.print("Skipping implementation file: {s}\n", .{input_file});
            continue;
        }

        const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
            std.debug.print("Error: Cannot open file '{s}': {}\n", .{ input_file, err });
            continue;
        };
        defer file.close();

        const source = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error: Cannot read file '{s}': {}\n", .{ input_file, err });
            continue;
        };

        try prescan_data.append(allocator, .{
            .path = input_file,
            .source = source,
            .needs_rebuild = true, // Default to true, will be updated below
        });
    }

    // Second pass: determine which files need rebuilding (considering dependencies)
    if (incr_cache) |*cache| {
        // Collect paths and contents for pre-scan
        var paths: std.ArrayList([]const u8) = .empty;
        defer paths.deinit(allocator);
        var contents: std.ArrayList([]const u8) = .empty;
        defer contents.deinit(allocator);

        for (prescan_data.items) |data| {
            try paths.append(allocator, data.path);
            try contents.append(allocator, data.source);
        }

        // Get set of files that need rebuilding
        var files_to_rebuild = cache.getFilesToRebuild(paths.items, contents.items) catch |err| blk: {
            // On error, rebuild everything (already defaulted to true)
            std.debug.print("Warning: Cache pre-scan failed: {}, rebuilding all\n", .{err});
            break :blk null;
        };

        if (files_to_rebuild) |*rebuild_set| {
            defer rebuild_set.deinit();
            // Update prescan data with rebuild decisions
            for (prescan_data.items) |*data| {
                data.needs_rebuild = rebuild_set.contains(data.path);
            }
        }
    }

    // Third pass: process files that need rebuilding
    for (prescan_data.items) |*data| {
        if (!data.needs_rebuild) {
            std.debug.print("Skipping unchanged: {s}\n", .{data.path});
            files_skipped += 1;
            continue;
        }

        files_rebuilt += 1;

        const base_path = std.fs.path.dirname(data.path) orelse ".";
        c_parser.setBasePath(base_path);
        cpp_parser.setBasePath(base_path);

        const is_cpp = isCppFile(data.path);
        const module = if (is_cpp)
            try cpp_parser.parse(data.source, data.path)
        else
            try c_parser.parse(data.source, data.path);

        try file_data.append(allocator, .{ .source = data.source, .module = module, .path = data.path });

        // Update cache entry and dependencies
        if (incr_cache) |*cache| {
            cache.updateEntry(data.path, data.source) catch {};
            // Record include dependencies for incremental rebuilds
            cache.setDependencies(data.path, module.includes) catch {};
        }
    }

    // Collect modules
    var modules: std.ArrayList(types.Module) = .empty;
    defer modules.deinit(allocator);

    for (file_data.items) |data| {
        try modules.append(allocator, data.module);
    }

    // Generate output based on format
    switch (args.output_format) {
        .mdbook => {
            const output_dir = args.output_file orelse config.output_dir;

            if (modules.items.len == 0 and files_skipped > 0) {
                std.debug.print("All {d} files unchanged (cached)\n", .{files_skipped});
                std.debug.print("Use --force to rebuild all files\n", .{});
                return;
            }

            const grouping_strategy: MdbookConfig.GroupingStrategy = switch (config.grouping) {
                .by_header => .by_header,
                .by_prefix => .by_prefix,
                .flat => .flat,
                .by_module => .by_module,
            };

            const mdbook_config = MdbookConfig{
                .title = args.book_title orelse config.title,
                .output_dir = output_dir,
                .generate_intro = config.generate_intro,
                .grouping = grouping_strategy,
                .module_configs = config.modules,
                .external_docs = config.external_docs,
            };

            var mdbook_gen = MdbookGenerator.initWithConfig(allocator, mdbook_config);
            defer mdbook_gen.deinit();

            mdbook_gen.generate(modules.items) catch |err| {
                std.debug.print("Error generating mdbook: {}\n", .{err});
                return;
            };

            // Save cache
            if (incr_cache) |*cache| {
                cache.save() catch |err| {
                    std.debug.print("Warning: Could not save cache: {}\n", .{err});
                };
            }

            if (files_skipped > 0) {
                std.debug.print("Rebuilt {d} file(s), skipped {d} unchanged\n", .{ files_rebuilt, files_skipped });
            }
            std.debug.print("Generated mdbook structure in: {s}/\n", .{output_dir});
            std.debug.print("Run 'mdbook build {s}' to build the book\n", .{output_dir});
        },
        .markdown => {
            var symbol_table = xref.SymbolTable.initWithConfig(allocator, config);
            defer symbol_table.deinit();
            try symbol_table.buildFromModules(modules.items);

            var snippet_extractor = snippet.SnippetExtractor.init(allocator);
            defer snippet_extractor.deinit();

            var output_buffer: std.ArrayList(u8) = .empty;
            defer output_buffer.deinit(allocator);

            for (modules.items) |module| {
                var gen = MarkdownGenerator.init(allocator);
                defer gen.deinit();

                gen.setSymbolTable(&symbol_table);
                gen.setOutputFormat(.markdown);
                gen.setSnippetExtractor(&snippet_extractor);

                const markdown = try gen.generate(module);
                try output_buffer.appendSlice(allocator, markdown);
            }

            if (args.output_file) |output_path| {
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
                var buf: [8192]u8 = undefined;
                var file_writer = std.fs.File.stdout().writer(&buf);
                const stdout = &file_writer.interface;
                defer stdout.flush() catch {};

                try stdout.writeAll(output_buffer.items);
            }
        },
        .json => {
            var json_gen = JsonGenerator.init(allocator);
            defer json_gen.deinit();

            const json_output = json_gen.generate(modules.items) catch |err| {
                std.debug.print("Error generating JSON: {}\n", .{err});
                return;
            };

            if (args.output_file) |output_path| {
                const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
                    std.debug.print("Error: Cannot create output file '{s}': {}\n", .{ output_path, err });
                    return;
                };
                defer file.close();

                file.writeAll(json_output) catch |err| {
                    std.debug.print("Error: Cannot write to file '{s}': {}\n", .{ output_path, err });
                    return;
                };

                std.debug.print("Generated JSON documentation: {s}\n", .{output_path});
            } else {
                var buf: [8192]u8 = undefined;
                var file_writer = std.fs.File.stdout().writer(&buf);
                const stdout = &file_writer.interface;
                defer stdout.flush() catch {};

                try stdout.writeAll(json_output);
            }
        },
    }
}

/// Check if a file is a C/C++ header file that should be documented
/// Following standardese and doxygen conventions, only header files should
/// contain documentation comments. Implementation files (.cpp, .cc, .cxx) are excluded.
fn isHeaderFile(filename: []const u8) bool {
    // C headers
    if (std.mem.endsWith(u8, filename, ".h")) return true;

    // C++ headers
    const cpp_header_extensions = [_][]const u8{ ".hpp", ".hxx", ".hh", ".H" };
    for (cpp_header_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
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

/// Expands a glob pattern to matching file paths
/// Supports ** for recursive directory matching
/// Examples: include/**/*.hpp, include/**.hpp, **/*.h
fn expandGlob(allocator: std.mem.Allocator, pattern: []const u8, results: *std.ArrayList([]const u8)) !void {
    // Check for recursive pattern (**)
    if (std.mem.indexOf(u8, pattern, "**")) |double_star_pos| {
        // Get prefix (directory before **)
        const prefix = if (double_star_pos > 0 and pattern[double_star_pos - 1] == '/')
            pattern[0 .. double_star_pos - 1]
        else if (double_star_pos > 0)
            pattern[0..double_star_pos]
        else
            ".";

        // Get suffix (pattern after **)
        const suffix_start = double_star_pos + 2;
        const suffix = if (suffix_start >= pattern.len)
            "*" // just **, match everything
        else if (pattern[suffix_start] == '/')
            pattern[suffix_start + 1 ..] // **/*.hpp -> *.hpp
        else
            pattern[suffix_start..]; // **.hpp -> *.hpp

        // If suffix starts with ., it's like **.hpp -> we want *.hpp
        const file_pattern = if (suffix.len > 0 and suffix[0] == '.') blk: {
            var buf: [256]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, "*{s}", .{suffix}) catch suffix;
            break :blk result;
        } else suffix;

        try expandRecursive(allocator, prefix, file_pattern, results);
    } else {
        // Simple glob without **
        const last_sep = std.mem.lastIndexOfScalar(u8, pattern, '/');
        const dir_path = if (last_sep) |idx| pattern[0..idx] else ".";
        const file_pattern = if (last_sep) |idx| pattern[idx + 1 ..] else pattern;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.debug.print("Warning: Cannot open directory '{s}': {}\n", .{ dir_path, err });
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            if (globMatch(file_pattern, entry.name)) {
                const full_path = if (last_sep != null)
                    try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name })
                else
                    try allocator.dupe(u8, entry.name);

                try results.append(allocator, full_path);
            }
        }
    }
}

/// Recursively expand directories and match files against suffix pattern
fn expandRecursive(allocator: std.mem.Allocator, base_dir: []const u8, file_pattern: []const u8, results: *std.ArrayList([]const u8)) !void {
    var dir = std.fs.cwd().openDir(base_dir, .{ .iterate = true }) catch {
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full_path = if (std.mem.eql(u8, base_dir, "."))
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_dir, entry.name });

        if (entry.kind == .directory) {
            // Recurse into subdirectory
            try expandRecursive(allocator, full_path, file_pattern, results);
            allocator.free(full_path);
        } else if (entry.kind == .file) {
            // Check if file matches the pattern
            if (globMatch(file_pattern, entry.name)) {
                try results.append(allocator, full_path);
            } else {
                allocator.free(full_path);
            }
        } else {
            allocator.free(full_path);
        }
    }
}

/// Simple glob pattern matching (supports * and ?)
fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_pi: ?usize = null;
    var star_ni: usize = 0;

    while (ni < name.len) {
        if (pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == name[ni])) {
            pi += 1;
            ni += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_pi = pi;
            star_ni = ni;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_ni += 1;
            ni = star_ni;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') {
        pi += 1;
    }

    return pi == pattern.len;
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
