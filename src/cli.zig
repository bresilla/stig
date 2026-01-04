const std = @import("std");
const argonaut = @import("argonaut");
const config_mod = @import("config.zig");

pub const VERSION = "0.2.0";
pub const Config = config_mod.Config;

/// Output format for documentation
pub const OutputFormat = enum {
    /// Single markdown file
    markdown,
    /// mdbook directory structure
    mdbook,
    /// JSON structured output
    json,
    /// Single-page HTML file
    html,

    pub fn fromConfig(cfg_format: Config.Format) OutputFormat {
        return switch (cfg_format) {
            .markdown => .markdown,
            .mdbook => .mdbook,
            .json => .json,
            .html => .html,
        };
    }
};

/// Output format for check command
pub const CheckOutputFormat = enum {
    /// Human-readable output (default)
    human,
    /// Compiler-style output (file:line:col: severity: message)
    compiler,
    /// JSON output for tooling integration
    json,
};

/// Subcommand type
pub const Subcommand = enum {
    /// Generate documentation (default)
    generate,
    /// Check documentation coverage and quality (linter-style output)
    check,
    /// Run as LSP server for editor integration (stig check with no args)
    check_lsp,
    /// Run as mdbook preprocessor
    preprocessor,
    /// Initialize test infrastructure
    init,
    /// Run tests
    @"test",
    /// Analyze test coverage (which API entities are tested)
    coverage,
    /// Show help
    help,
    /// Show help for generate subcommand
    help_generate,
    /// Show help for check subcommand
    help_check,
    /// Show help for init subcommand
    help_init,
    /// Show help for test subcommand
    help_test,
    /// Show help for coverage subcommand
    help_coverage,
    /// Show version
    version,
};

/// CLI argument parsing result
pub const Args = struct {
    subcommand: Subcommand,
    input_files: []const []const u8,
    output_file: ?[]const u8,
    output_format: OutputFormat,
    format_explicitly_set: bool,
    book_title: ?[]const u8,
    config_file: ?[]const u8,
    watch_mode: bool,
    serve_mode: bool,
    force_rebuild: bool,
    /// Check command options
    check_output_format: CheckOutputFormat,
    min_coverage: ?u8,
    strict: bool, // treat warnings as errors
    /// Coverage command options - test file patterns
    test_patterns: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Args) void {
        self.allocator.free(self.input_files);
    }
};

/// CLI argument parser using argonaut
pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    parser: ?*argonaut.Parser,
    process_args: ?[]const [:0]u8,
    remainder: ?[]const []const u8,

    // Argument pointers for generate subcommand
    output_ptr: ?*[]const u8,
    format_ptr: ?*[]const u8,
    title_ptr: ?*[]const u8,
    config_ptr: ?*[]const u8,
    watch_ptr: ?*bool,
    serve_ptr: ?*bool,
    force_ptr: ?*bool,

    // Argument pointers for check subcommand
    check_format_ptr: ?*[]const u8,
    min_coverage_ptr: ?*i64,
    strict_ptr: ?*bool,

    // Global flags
    help_ptr: ?*bool,
    version_ptr: ?*bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .parser = null,
            .process_args = null,
            .remainder = null,
            .output_ptr = null,
            .format_ptr = null,
            .title_ptr = null,
            .config_ptr = null,
            .watch_ptr = null,
            .serve_ptr = null,
            .force_ptr = null,
            .check_format_ptr = null,
            .min_coverage_ptr = null,
            .strict_ptr = null,
            .help_ptr = null,
            .version_ptr = null,
        };
    }

    /// Parses command-line arguments using argonaut
    pub fn parse(self: *Self) !Args {
        // Get process args
        self.process_args = try std.process.argsAlloc(self.allocator);
        const process_args = self.process_args.?;

        // Skip program name
        if (process_args.len < 1) {
            return defaultArgs(self.allocator);
        }

        // Check for subcommand or flags first
        var subcommand: Subcommand = .generate;
        var args_start: usize = 1;

        if (process_args.len > 1) {
            const first_arg = process_args[1];

            // Check for help/version flags first
            if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "help")) {
                return Args{
                    .subcommand = .help,
                    .input_files = &[_][]const u8{},
                    .output_file = null,
                    .output_format = .markdown,
                    .format_explicitly_set = false,
                    .book_title = null,
                    .config_file = null,
                    .watch_mode = false,
                    .serve_mode = false,
                    .force_rebuild = false,
                    .check_output_format = .human,
                    .min_coverage = null,
                    .strict = false,
                    .test_patterns = &[_][]const u8{},
                    .allocator = self.allocator,
                };
            }

            if (std.mem.eql(u8, first_arg, "-v") or std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "version")) {
                return Args{
                    .subcommand = .version,
                    .input_files = &[_][]const u8{},
                    .output_file = null,
                    .output_format = .markdown,
                    .format_explicitly_set = false,
                    .book_title = null,
                    .config_file = null,
                    .watch_mode = false,
                    .serve_mode = false,
                    .force_rebuild = false,
                    .check_output_format = .human,
                    .min_coverage = null,
                    .strict = false,
                    .test_patterns = &[_][]const u8{},
                    .allocator = self.allocator,
                };
            }

            // Check for subcommands
            if (std.mem.eql(u8, first_arg, "generate") or std.mem.eql(u8, first_arg, "gen")) {
                subcommand = .generate;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "check")) {
                subcommand = .check;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "preprocessor") or std.mem.eql(u8, first_arg, "preprocess")) {
                subcommand = .preprocessor;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "supports")) {
                // mdbook support check - just return preprocessor mode
                subcommand = .preprocessor;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "init")) {
                subcommand = .init;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "test")) {
                subcommand = .@"test";
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "coverage") or std.mem.eql(u8, first_arg, "cov")) {
                subcommand = .coverage;
                args_start = 2;
            }
        }

        // Parse based on subcommand
        return switch (subcommand) {
            .generate => try self.parseGenerateArgs(process_args, args_start),
            .check => try self.parseCheckArgs(process_args, args_start),
            .init => try self.parseInitArgs(process_args, args_start),
            .@"test" => try self.parseTestArgs(process_args, args_start),
            .coverage => try self.parseCoverageArgs(process_args, args_start),
            .preprocessor => Args{
                .subcommand = .preprocessor,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            },
            .check_lsp => unreachable, // returned from parseCheckArgs
            .help, .help_generate, .help_check, .help_init, .help_test, .help_coverage, .version => unreachable, // handled above
        };
    }

    fn parseGenerateArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for generate subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig generate",
            "Generate documentation from C/C++ source files",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var output_opts = argonaut.Options{};
        output_opts.help = "Output file or directory (default: stdout)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

        var format_opts = argonaut.Options{};
        format_opts.help = "Output format: markdown, mdbook, json, html (default: markdown)";
        self.format_ptr = try parser.string("f", "format", &format_opts);

        var title_opts = argonaut.Options{};
        title_opts.help = "Book title (for mdbook/html format)";
        self.title_ptr = try parser.string("", "title", &title_opts);

        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var watch_opts = argonaut.Options{};
        watch_opts.help = "Watch for file changes and regenerate";
        self.watch_ptr = try parser.flag("w", "watch", &watch_opts);

        var serve_opts = argonaut.Options{};
        serve_opts.help = "Watch mode + spawn mdbook serve for live preview";
        self.serve_ptr = try parser.flag("", "serve", &serve_opts);

        var force_opts = argonaut.Options{};
        force_opts.help = "Force full rebuild, ignore cache";
        self.force_ptr = try parser.flag("", "force", &force_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for generate command";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Build args slice starting from args_start
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(self.allocator);

        // Add a dummy first element (program name) for argonaut
        try args_list.append(self.allocator, "stig");
        for (process_args[args_start..]) |arg| {
            try args_list.append(self.allocator, arg);
        }

        // Parse
        self.remainder = parser.parseWithRemainder(args_list.items) catch |err| {
            return err;
        };

        // Check for help
        if (self.help_ptr.?.*) {
            return Args{
                .subcommand = .help_generate,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Parse format
        const format_str = self.format_ptr.?.*;
        var output_format: OutputFormat = .markdown;
        var format_explicitly_set = false;
        if (format_str.len > 0) {
            format_explicitly_set = true;
            if (std.mem.eql(u8, format_str, "mdbook")) {
                output_format = .mdbook;
            } else if (std.mem.eql(u8, format_str, "md") or std.mem.eql(u8, format_str, "markdown")) {
                output_format = .markdown;
            } else if (std.mem.eql(u8, format_str, "json")) {
                output_format = .json;
            } else if (std.mem.eql(u8, format_str, "html")) {
                output_format = .html;
            }
        }

        // Get other values
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        const title_str = self.title_ptr.?.*;
        const book_title: ?[]const u8 = if (title_str.len > 0) title_str else null;

        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        const watch_mode = self.watch_ptr.?.* or self.serve_ptr.?.*;
        const serve_mode = self.serve_ptr.?.*;
        const force_rebuild = self.force_ptr.?.*;

        // Get input files from remainder
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .subcommand = .generate,
            .input_files = input_files,
            .output_file = output_file,
            .output_format = output_format,
            .format_explicitly_set = format_explicitly_set,
            .book_title = book_title,
            .config_file = config_file,
            .watch_mode = watch_mode,
            .serve_mode = serve_mode,
            .force_rebuild = force_rebuild,
            .check_output_format = .human,
            .min_coverage = null,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn parseCheckArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for check subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig check",
            "Check documentation coverage and quality",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var format_opts = argonaut.Options{};
        format_opts.help = "Output format: human, compiler, json (default: human)";
        self.check_format_ptr = try parser.string("f", "format", &format_opts);

        var coverage_opts = argonaut.Options{};
        coverage_opts.help = "Minimum coverage percentage required (0-100)";
        self.min_coverage_ptr = try parser.int("", "min-coverage", &coverage_opts);

        var strict_opts = argonaut.Options{};
        strict_opts.help = "Treat warnings as errors";
        self.strict_ptr = try parser.flag("", "strict", &strict_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for check command";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Build args slice starting from args_start
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(self.allocator);

        try args_list.append(self.allocator, "stig");
        for (process_args[args_start..]) |arg| {
            try args_list.append(self.allocator, arg);
        }

        // Parse
        self.remainder = parser.parseWithRemainder(args_list.items) catch |err| {
            return err;
        };

        // Check for help
        if (self.help_ptr.?.*) {
            return Args{
                .subcommand = .help_check,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Parse check format
        const format_str = if (self.check_format_ptr) |ptr| ptr.* else "";
        var check_output_format: CheckOutputFormat = .human;
        if (format_str.len > 0) {
            if (std.mem.eql(u8, format_str, "compiler") or std.mem.eql(u8, format_str, "gcc")) {
                check_output_format = .compiler;
            } else if (std.mem.eql(u8, format_str, "json")) {
                check_output_format = .json;
            }
        }

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Get min coverage
        const min_coverage_val = self.min_coverage_ptr.?.*;
        const min_coverage: ?u8 = if (min_coverage_val > 0) @intCast(@min(min_coverage_val, 100)) else null;

        // Get strict mode
        const strict = self.strict_ptr.?.*;

        // Get input files from remainder
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        // If `stig check` with no arguments at all, run as LSP server
        if (input_files.len == 0 and config_file == null and min_coverage == null and !strict and format_str.len == 0) {
            return Args{
                .subcommand = .check_lsp,
                .input_files = input_files,
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        return Args{
            .subcommand = .check,
            .input_files = input_files,
            .output_file = null,
            .output_format = .markdown,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
            .check_output_format = check_output_format,
            .min_coverage = min_coverage,
            .strict = strict,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn parseInitArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for init subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig init",
            "Initialize test infrastructure for a C/C++ project",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path to create (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var force_opts = argonaut.Options{};
        force_opts.help = "Overwrite existing files";
        self.force_ptr = try parser.flag("", "force", &force_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for init command";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Build args slice starting from args_start
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(self.allocator);

        try args_list.append(self.allocator, "stig");
        for (process_args[args_start..]) |arg| {
            try args_list.append(self.allocator, arg);
        }

        // Parse
        self.remainder = parser.parseWithRemainder(args_list.items) catch |err| {
            return err;
        };

        // Check for help
        if (self.help_ptr.?.*) {
            return Args{
                .subcommand = .help_init,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Get force flag
        const force_rebuild = self.force_ptr.?.*;

        return Args{
            .subcommand = .init,
            .input_files = &[_][]const u8{},
            .output_file = null,
            .output_format = .markdown,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = force_rebuild,
            .check_output_format = .human,
            .min_coverage = null,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn parseTestArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for test subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig test",
            "Compile and run tests",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var format_opts = argonaut.Options{};
        format_opts.help = "Output format: console, json, junit (default: console)";
        self.check_format_ptr = try parser.string("f", "format", &format_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for test command";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Build args slice starting from args_start
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(self.allocator);

        try args_list.append(self.allocator, "stig");
        for (process_args[args_start..]) |arg| {
            try args_list.append(self.allocator, arg);
        }

        // Parse
        self.remainder = parser.parseWithRemainder(args_list.items) catch |err| {
            return err;
        };

        // Check for help
        if (self.help_ptr.?.*) {
            return Args{
                .subcommand = .help_test,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Parse test output format
        const format_str = if (self.check_format_ptr) |ptr| ptr.* else "";
        var check_output_format: CheckOutputFormat = .human;
        if (format_str.len > 0) {
            if (std.mem.eql(u8, format_str, "json")) {
                check_output_format = .json;
            } else if (std.mem.eql(u8, format_str, "junit") or std.mem.eql(u8, format_str, "xml")) {
                check_output_format = .compiler; // reuse for junit
            }
        }

        // Get input files (test files or binary) from remainder
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .subcommand = .@"test",
            .input_files = input_files,
            .output_file = null,
            .output_format = .markdown,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
            .check_output_format = check_output_format,
            .min_coverage = null,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn parseCoverageArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for coverage subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig coverage",
            "Analyze test coverage - which API entities are tested",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var format_opts = argonaut.Options{};
        format_opts.help = "Output format: human, compiler, json (default: human)";
        self.check_format_ptr = try parser.string("f", "format", &format_opts);

        var coverage_opts = argonaut.Options{};
        coverage_opts.help = "Minimum test coverage percentage required (0-100)";
        self.min_coverage_ptr = try parser.int("", "min-coverage", &coverage_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for coverage command";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Build args slice starting from args_start
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(self.allocator);

        try args_list.append(self.allocator, "stig");
        for (process_args[args_start..]) |arg| {
            try args_list.append(self.allocator, arg);
        }

        // Parse
        self.remainder = parser.parseWithRemainder(args_list.items) catch |err| {
            return err;
        };

        // Check for help
        if (self.help_ptr.?.*) {
            return Args{
                .subcommand = .help_coverage,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                .check_output_format = .human,
                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Parse output format
        const format_str = if (self.check_format_ptr) |ptr| ptr.* else "";
        var check_output_format: CheckOutputFormat = .human;
        if (format_str.len > 0) {
            if (std.mem.eql(u8, format_str, "compiler") or std.mem.eql(u8, format_str, "gcc")) {
                check_output_format = .compiler;
            } else if (std.mem.eql(u8, format_str, "json")) {
                check_output_format = .json;
            }
        }

        // Get min coverage
        const min_coverage_val = self.min_coverage_ptr.?.*;
        const min_coverage: ?u8 = if (min_coverage_val > 0) @intCast(@min(min_coverage_val, 100)) else null;

        // Get input files (header files) and test patterns from remainder
        // Format: stig coverage <headers...> --tests <test_files...>
        // For now, we'll use config file for test patterns
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .subcommand = .coverage,
            .input_files = input_files,
            .output_file = null,
            .output_format = .markdown,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
            .check_output_format = check_output_format,
            .min_coverage = min_coverage,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn defaultArgs(allocator: std.mem.Allocator) Args {
        return Args{
            .subcommand = .help,
            .input_files = &[_][]const u8{},
            .output_file = null,
            .output_format = .markdown,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = null,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
            .check_output_format = .human,
            .min_coverage = null,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = allocator,
        };
    }

    /// Merges CLI args with config file, CLI takes precedence
    pub fn mergeWithConfig(args: *Args, cfg: Config) void {
        // Format: only use config format if CLI format was not explicitly set
        if (!args.format_explicitly_set) {
            args.output_format = OutputFormat.fromConfig(cfg.format);
        }

        // CLI args take precedence over config file
        // Only use config output_dir for mdbook format (markdown defaults to stdout)
        if (args.output_file == null and cfg.output_dir.len > 0 and args.output_format == .mdbook) {
            args.output_file = cfg.output_dir;
        }
        if (args.book_title == null and cfg.title.len > 0) {
            args.book_title = cfg.title;
        }
    }

    /// Prints help message
    pub fn printHelp(self: *Self) void {
        _ = self;
        printMainHelp();
    }

    /// Prints help for generate subcommand
    pub fn printGenerateHelp() void {
        const help =
            \\stig generate - Generate documentation from C/C++ source files
            \\
            \\USAGE:
            \\    stig generate [OPTIONS] <INPUT_FILES>...
            \\    stig [OPTIONS] <INPUT_FILES>...          (generate is the default)
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to process
            \\
            \\OPTIONS:
            \\    -o, --output <PATH>    Output file or directory (default: stdout)
            \\    -f, --format <FMT>     Output format: markdown, mdbook, json, html
            \\    --title <TITLE>        Book title (for mdbook/html format)
            \\    -c, --config <FILE>    Config file path (default: stig.toml)
            \\    -w, --watch            Watch for file changes and regenerate
            \\    --serve                Watch mode + spawn mdbook serve for live preview
            \\    --force                Force full rebuild, ignore cache
            \\    -h, --help             Show this help message
            \\
            \\EXAMPLES:
            \\    stig generate input.h                    # Output to stdout
            \\    stig input.h -o output.md                # Output to file
            \\    stig src/*.h -f mdbook -o docs/          # Generate mdbook
            \\    stig src/*.h -f mdbook --serve           # Watch + live preview
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for check subcommand
    pub fn printCheckHelp() void {
        const help =
            \\stig check - Check documentation coverage and quality
            \\
            \\USAGE:
            \\    stig check [OPTIONS] <INPUT_FILES>...
            \\    stig check                               (LSP server mode)
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to check
            \\
            \\OPTIONS:
            \\    -c, --config <FILE>       Config file path (default: stig.toml)
            \\    -f, --format <FMT>        Output format: human, compiler, json
            \\    --min-coverage <N>        Minimum coverage percentage (0-100)
            \\    --strict                  Treat warnings as errors
            \\    -h, --help                Show this help message
            \\
            \\OUTPUT FORMATS:
            \\    human      Human-readable report with summary (default)
            \\    compiler   Compiler-style output for CI/CD integration:
            \\               file:line:col: severity: message
            \\    json       JSON output for tooling integration
            \\
            \\LSP MODE:
            \\    When called with no arguments, stig check runs as an LSP server
            \\    for editor integration (VS Code, Neovim, etc.). The server
            \\    provides real-time documentation diagnostics.
            \\
            \\EXIT CODES:
            \\    0    All checks passed
            \\    1    Errors found (undocumented items, invalid references)
            \\    2    Warnings found (with --strict) or coverage below threshold
            \\
            \\EXAMPLES:
            \\    stig check                               # Start LSP server
            \\    stig check src/*.h                       # Human-readable report
            \\    stig check -f compiler src/*.h           # CI/CD friendly output
            \\    stig check --min-coverage 80 src/*.h     # Fail if < 80% coverage
            \\    stig check --strict src/*.h              # Treat warnings as errors
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for init subcommand
    pub fn printInitHelp() void {
        const help =
            \\stig init - Initialize test infrastructure for a C/C++ project
            \\
            \\USAGE:
            \\    stig init [OPTIONS]
            \\
            \\OPTIONS:
            \\    -c, --config <FILE>    Config file path to create (default: stig.toml)
            \\    --force                Overwrite existing files
            \\    -h, --help             Show this help message
            \\
            \\DESCRIPTION:
            \\    Creates the test infrastructure for your project:
            \\
            \\    ./stig.toml          - Configuration file (for documentation)
            \\    ./test/              - Test directory
            \\    ./test/stig_test.h   - Test framework header (includes main())
            \\    ./test/test_example.cpp - Example test file
            \\
            \\    Each test file is standalone - just #include "stig_test.h" and
            \\    use STIG_TEST() macro. Compile with CMake using stig_add_tests().
            \\
            \\EXAMPLES:
            \\    stig init                    # Initialize in current directory
            \\    stig init --force            # Overwrite existing files
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for test subcommand
    pub fn printTestHelp() void {
        const help =
            \\stig test - Run pre-compiled test binaries
            \\
            \\USAGE:
            \\    stig test <BINARY> [BINARY...]
            \\
            \\ARGS:
            \\    <BINARY>...    Pre-compiled test binaries to run
            \\
            \\OPTIONS:
            \\    -h, --help     Show this help message
            \\
            \\DESCRIPTION:
            \\    Runs pre-compiled test binaries built with stig's test framework.
            \\
            \\    Tests should be compiled using CMake with stig_add_tests():
            \\
            \\        stig_add_tests(my_tests
            \\            SOURCES test/*.cpp
            \\            LIBRARIES my_library
            \\        )
            \\
            \\    Then run with: stig test ./build/my_tests_test_foo
            \\
            \\    Test output uses GoogleTest-style format with pass/fail status.
            \\
            \\EXAMPLES:
            \\    stig test ./build/test_core           # Run single test
            \\    stig test ./build/test_*              # Run multiple tests
            \\    ctest --test-dir build                # Or use CTest directly
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for coverage subcommand
    pub fn printCoverageHelp() void {
        const help =
            \\stig coverage - Analyze test coverage (which API entities are tested)
            \\
            \\USAGE:
            \\    stig coverage [OPTIONS]
            \\    stig cov [OPTIONS]                       (alias)
            \\
            \\OPTIONS:
            \\    -c, --config <FILE>       Config file path (default: stig.toml)
            \\    -f, --format <FMT>        Output format: human, compiler, json
            \\    --min-coverage <N>        Minimum test coverage percentage (0-100)
            \\    -h, --help                Show this help message
            \\
            \\DESCRIPTION:
            \\    Analyzes which documented API entities (functions, classes, methods)
            \\    are being exercised by your test files. This is NOT line coverage -
            \\    it's API coverage showing which parts of your public API have tests.
            \\
            \\    The command:
            \\    1. Parses header files to build a symbol table of documented entities
            \\    2. Parses test files to find which entities are called/used
            \\    3. Reports which documented entities have tests vs which don't
            \\
            \\CONFIG FILE (stig.toml):
            \\    [coverage]
            \\    sources = ["include/**/*.hpp"]    # Header files to analyze
            \\    tests = ["test/**/*.cpp"]         # Test files to scan
            \\    min_coverage = 80                 # Minimum coverage threshold
            \\
            \\OUTPUT FORMATS:
            \\    human      Human-readable report with summary (default)
            \\    compiler   Compiler-style output for CI/CD integration
            \\    json       JSON output for tooling integration
            \\
            \\EXIT CODES:
            \\    0    Coverage meets threshold
            \\    1    Coverage below threshold
            \\
            \\EXAMPLES:
            \\    stig coverage                            # Use config file
            \\    stig coverage --min-coverage 80         # Fail if < 80% tested
            \\    stig coverage -f json                   # JSON output for CI
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    fn printMainHelp() void {
        const help =
            \\stig - C/C++ documentation generator
            \\
            \\USAGE:
            \\    stig <COMMAND> [OPTIONS] <INPUT_FILES>...
            \\    stig [OPTIONS] <INPUT_FILES>...          (defaults to 'generate')
            \\
            \\COMMANDS:
            \\    generate      Generate documentation from source files (default)
            \\    check         Check documentation coverage and quality
            \\    coverage      Analyze test coverage (which API entities are tested)
            \\    init          Initialize test infrastructure
            \\    test          Run pre-compiled test binaries
            \\    preprocessor  Run as mdbook preprocessor
            \\    help          Show this help message
            \\    version       Show version information
            \\
            \\GLOBAL OPTIONS:
            \\    -h, --help      Show help (use 'stig <command> --help' for command help)
            \\    -v, --version   Show version information
            \\
            \\CONFIG FILE:
            \\    stig looks for stig.toml in the current directory.
            \\    CLI arguments override config file settings.
            \\
            \\EXAMPLES:
            \\    stig input.h                             # Generate markdown to stdout
            \\    stig generate -f mdbook -o docs/ src/*.h # Generate mdbook
            \\    stig check src/*.h                       # Check documentation
            \\    stig coverage                            # Analyze test coverage
            \\    stig init                                # Initialize test infrastructure
            \\    stig test ./build/test_*                 # Run tests
            \\
            \\For more information on a command, run:
            \\    stig <command> --help
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints version information
    pub fn printVersion(self: *Self) void {
        _ = self;
        std.debug.print("stig {s}\n", .{VERSION});
    }

    pub fn deinit(self: *Self) void {
        if (self.remainder) |rem| {
            self.allocator.free(rem);
        }
        if (self.parser) |parser| {
            parser.deinit();
        }
        if (self.process_args) |args| {
            std.process.argsFree(self.allocator, args);
        }
    }
};

// Tests
test "parse help flag" {
    // Can't easily test args parsing without mocking
}
