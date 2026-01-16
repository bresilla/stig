const std = @import("std");
const argonaut = @import("argonaut");
const config_mod = @import("config.zig");

pub const VERSION = "0.0.2";
pub const Config = config_mod.Config;

/// Output format for generate command (SARIF only after streamlining)
pub const OutputFormat = enum {
    /// SARIF output (default and only option for generate)
    sarif,
    /// mdbook directory structure (for render command only)
    mdbook,

    pub fn fromConfig(cfg_format: Config.Format) OutputFormat {
        // All formats now map to sarif for generate command
        _ = cfg_format;
        return .sarif;
    }
};

// Check command outputs SARIF only (unified with generate command)

/// Subcommand type
pub const Subcommand = enum {
    /// Generate SARIF from source files (default)
    generate,
    /// Render mdbook from SARIF file
    render,
    /// Check documentation coverage and quality (linter-style output)
    check,
    /// Run as LSP server for editor integration
    lsp,
    /// Initialize test infrastructure
    init,
    /// Run tests
    @"test",
    /// Show help
    help,
    /// Show help for generate subcommand
    help_generate,
    /// Show help for render subcommand
    help_render,
    /// Show help for check subcommand
    help_check,
    /// Show help for lsp subcommand
    help_lsp,
    /// Show help for init subcommand
    help_init,
    /// Show help for test subcommand
    help_test,
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
                    .output_format = .sarif,
                    .format_explicitly_set = false,
                    .book_title = null,
                    .config_file = null,
                    .watch_mode = false,
                    .serve_mode = false,
                    .force_rebuild = false,
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
                    .output_format = .sarif,
                    .format_explicitly_set = false,
                    .book_title = null,
                    .config_file = null,
                    .watch_mode = false,
                    .serve_mode = false,
                    .force_rebuild = false,
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
            } else if (std.mem.eql(u8, first_arg, "init")) {
                subcommand = .init;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "test")) {
                subcommand = .@"test";
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "lsp")) {
                subcommand = .lsp;
                args_start = 2;
            } else if (std.mem.eql(u8, first_arg, "render")) {
                subcommand = .render;
                args_start = 2;
            }
        }

        // Parse based on subcommand
        return switch (subcommand) {
            .generate => try self.parseGenerateArgs(process_args, args_start),
            .render => try self.parseRenderArgs(process_args, args_start),
            .check => try self.parseCheckArgs(process_args, args_start),
            .init => try self.parseInitArgs(process_args, args_start),
            .@"test" => try self.parseTestArgs(process_args, args_start),
            .lsp => blk: {
                // Check for help flag
                if (process_args.len > args_start) {
                    const arg = process_args[args_start];
                    if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "help")) {
                        break :blk Args{
                            .subcommand = .help_lsp,
                            .input_files = &[_][]const u8{},
                            .output_file = null,
                            .output_format = .sarif,
                            .format_explicitly_set = false,
                            .book_title = null,
                            .config_file = null,
                            .watch_mode = false,
                            .serve_mode = false,
                            .force_rebuild = false,
                                                        .min_coverage = null,
                            .strict = false,
                            .test_patterns = &[_][]const u8{},
                            .allocator = self.allocator,
                        };
                    }
                }
                break :blk Args{
                    .subcommand = .lsp,
                    .input_files = &[_][]const u8{},
                    .output_file = null,
                    .output_format = .sarif,
                    .format_explicitly_set = false,
                    .book_title = null,
                    .config_file = null,
                    .watch_mode = false,
                    .serve_mode = false,
                    .force_rebuild = false,
                                        .min_coverage = null,
                    .strict = false,
                    .test_patterns = &[_][]const u8{},
                    .allocator = self.allocator,
                };
            },
            .help, .help_generate, .help_render, .help_check, .help_lsp, .help_init, .help_test, .version => unreachable, // handled above
        };
    }

    fn parseGenerateArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for generate subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig generate",
            "Generate SARIF from C/C++ source files",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var output_opts = argonaut.Options{};
        output_opts.help = "Output SARIF file (default: stdout)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

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
                .output_format = .sarif,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get values
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

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
            .output_format = .sarif,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = force_rebuild,
                        .min_coverage = null,
            .strict = false,
            .test_patterns = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn parseRenderArgs(self: *Self, process_args: []const [:0]u8, args_start: usize) !Args {
        // Create argonaut parser for render subcommand
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig render",
            "Render mdbook documentation from a SARIF file",
        );
        const parser = self.parser.?;
        parser.command.disableHelp();

        // Define arguments
        var output_opts = argonaut.Options{};
        output_opts.help = "Output directory for mdbook (required)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

        var title_opts = argonaut.Options{};
        title_opts.help = "Override book title";
        self.title_ptr = try parser.string("", "title", &title_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show help for render command";
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
                .subcommand = .help_render,
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .mdbook,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get output directory
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        // Get book title
        const title_str = self.title_ptr.?.*;
        const book_title: ?[]const u8 = if (title_str.len > 0) title_str else null;

        // Get input files from remainder (should be the SARIF file)
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .subcommand = .render,
            .input_files = input_files,
            .output_file = output_file,
            .output_format = .mdbook,
            .format_explicitly_set = false,
            .book_title = book_title,
            .config_file = null,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
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

        var output_opts = argonaut.Options{};
        output_opts.help = "Output SARIF file (default: stdout)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

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
                .output_format = .sarif,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get output file
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Get min coverage (validate range 0-100)
        const min_coverage_val = self.min_coverage_ptr.?.*;
        const min_coverage: ?u8 = if (min_coverage_val >= 0 and min_coverage_val <= 100)
            @intCast(min_coverage_val)
        else if (min_coverage_val > 100) blk: {
            std.debug.print("Warning: min-coverage value {d} exceeds 100, capping at 100\n", .{min_coverage_val});
            break :blk 100;
        } else blk: {
            std.debug.print("Warning: min-coverage value {d} is invalid (must be 0-100), ignoring\n", .{min_coverage_val});
            break :blk null;
        };

        // Get strict mode
        const strict = self.strict_ptr.?.*;

        // Get input files from remainder
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        // If no input files and no config file, show error
        if (input_files.len == 0 and config_file == null) {
            std.debug.print("Error: No input files specified.\n", .{});
            std.debug.print("Usage: stig check [OPTIONS] <INPUT_FILES>...\n", .{});
            std.debug.print("\nFor LSP server mode, use: stig lsp\n", .{});
            return error.MissingInputFiles;
        }

        return Args{
            .subcommand = .check,
            .input_files = input_files,
            .output_file = output_file,
            .output_format = .sarif,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
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
                .output_format = .sarif,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
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
            .output_format = .sarif,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = force_rebuild,
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

        var output_opts = argonaut.Options{};
        output_opts.help = "Output SARIF file (default: stdout)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

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
                .output_format = .sarif,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .watch_mode = false,
                .serve_mode = false,
                .force_rebuild = false,
                                .min_coverage = null,
                .strict = false,
                .test_patterns = &[_][]const u8{},
                .allocator = self.allocator,
            };
        }

        // Get config file
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Get output file
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        // Get input files (test files or binary) from remainder
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .subcommand = .@"test",
            .input_files = input_files,
            .output_file = output_file,
            .output_format = .sarif,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = config_file,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
            .min_coverage = null,
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
            .output_format = .sarif,
            .format_explicitly_set = false,
            .book_title = null,
            .config_file = null,
            .watch_mode = false,
            .serve_mode = false,
            .force_rebuild = false,
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
            \\stig generate - Parse C/C++ sources and output SARIF
            \\
            \\USAGE:
            \\    stig generate [OPTIONS] <INPUT_FILES>...
            \\    stig [OPTIONS] <INPUT_FILES>...          (generate is the default)
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to process
            \\
            \\OPTIONS:
            \\    -o, --output <FILE>    Output SARIF file (default: stdout)
            \\    -c, --config <FILE>    Config file path (default: stig.toml)
            \\    --force                Force full rebuild, ignore cache
            \\    -h, --help             Show this help message
            \\
            \\DESCRIPTION:
            \\    Parses C/C++ header files and outputs a SARIF file containing the
            \\    documentation model. This SARIF file can then be used with 'stig render'
            \\    to generate mdbook documentation.
            \\
            \\EXAMPLES:
            \\    stig generate input.h                    # Output to stdout
            \\    stig generate -o docs.sarif src/*.h      # Output to file
            \\    stig generate -c myconfig.toml *.h       # Use custom config
            \\
            \\SEE ALSO:
            \\    stig render    Generate mdbook from SARIF file
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for render subcommand
    pub fn printRenderHelp() void {
        const help =
            \\stig render - Generate mdbook documentation from a SARIF file
            \\
            \\USAGE:
            \\    stig render [OPTIONS] <SARIF_FILE>
            \\
            \\ARGS:
            \\    <SARIF_FILE>    SARIF file from 'stig generate'
            \\
            \\OPTIONS:
            \\    -o, --output <DIR>     Output directory for mdbook (required)
            \\    --title <TITLE>        Override book title
            \\    -h, --help             Show this help message
            \\
            \\DESCRIPTION:
            \\    Reads a SARIF file produced by 'stig generate' and generates
            \\    an mdbook directory structure with Markdown documentation.
            \\
            \\EXAMPLES:
            \\    stig render docs.sarif -o docs/          # Generate mdbook
            \\    stig render docs.sarif -o book/ --title "My API"
            \\
            \\SEE ALSO:
            \\    stig generate    Parse C/C++ sources to SARIF
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
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to check
            \\
            \\OPTIONS:
            \\    -o, --output <FILE>       Output SARIF to file (default: compiler output)
            \\    -c, --config <FILE>       Config file path (default: stig.toml)
            \\    --min-coverage <N>        Minimum coverage percentage (0-100)
            \\    --strict                  Treat warnings as errors
            \\    -h, --help                Show this help message
            \\
            \\OUTPUT:
            \\    Without -o: Compiler-style output (file:line:col: severity: message)
            \\    With -o:    SARIF format for GitHub code scanning and CI/CD
            \\
            \\EXIT CODES:
            \\    0    All checks passed
            \\    1    Errors found (undocumented items, invalid references)
            \\    2    Warnings found (with --strict) or coverage below threshold
            \\
            \\EXAMPLES:
            \\    stig check src/*.h                       # Compiler output to terminal
            \\    stig check -o check.sarif src/*.h        # SARIF to file
            \\    stig check --min-coverage 80 src/*.h     # Fail if < 80% coverage
            \\    stig check --strict src/*.h              # Treat warnings as errors
            \\
            \\SEE ALSO:
            \\    stig generate    Parse sources to SARIF
            \\    stig render      Generate mdbook from SARIF
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints help for lsp subcommand
    pub fn printLspHelp() void {
        const help =
            \\stig lsp - Run as LSP server for editor integration
            \\
            \\USAGE:
            \\    stig lsp
            \\
            \\DESCRIPTION:
            \\    Starts stig as a Language Server Protocol (LSP) server for
            \\    real-time documentation checking in editors like VS Code,
            \\    Neovim, Emacs, etc.
            \\
            \\FEATURES:
            \\    - Real-time diagnostics for documentation issues
            \\    - Auto-completion for Doxygen tags (@brief, @param, etc.)
            \\    - Quick fixes for common documentation problems
            \\    - Documentation coverage warnings
            \\
            \\EDITOR SETUP:
            \\    VS Code:   Install the stig extension or configure a custom LSP
            \\    Neovim:    Add to your LSP configuration:
            \\               require('lspconfig').stig.setup{}
            \\    Emacs:     Configure with lsp-mode or eglot
            \\
            \\CONFIGURATION:
            \\    The LSP server reads stig.toml from the workspace root for
            \\    lint rules, coverage thresholds, and other settings.
            \\
            \\EXAMPLES:
            \\    stig lsp                                 # Start LSP server
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

    fn printMainHelp() void {
        const help =
            \\stig - C/C++ documentation generator
            \\
            \\USAGE:
            \\    stig <COMMAND> [OPTIONS] <INPUT_FILES>...
            \\    stig [OPTIONS] <INPUT_FILES>...          (defaults to 'generate')
            \\
            \\COMMANDS:
            \\    generate      Parse sources and output SARIF (default)
            \\    render        Generate mdbook from SARIF file
            \\    check         Check documentation coverage and quality
            \\    lsp           Run as LSP server for editor integration
            \\    init          Initialize project configuration
            \\    test          Run pre-compiled test binaries
            \\    help          Show this help message
            \\    version       Show version information
            \\
            \\GLOBAL OPTIONS:
            \\    -h, --help      Show help (use 'stig <command> --help' for command help)
            \\    -v, --version   Show version information
            \\
            \\PIPELINE:
            \\    The recommended workflow is a two-stage pipeline:
            \\    1. stig generate src/*.h -o docs.sarif    # Parse sources to SARIF
            \\    2. stig render docs.sarif -o docs/        # Generate mdbook from SARIF
            \\
            \\CONFIG FILE:
            \\    stig looks for stig.toml in the current directory.
            \\    CLI arguments override config file settings.
            \\
            \\EXAMPLES:
            \\    stig input.h                             # Generate SARIF to stdout
            \\    stig generate -o docs.sarif src/*.h      # Generate SARIF file
            \\    stig render docs.sarif -o docs/          # Generate mdbook
            \\    stig check src/*.h                       # Check documentation
            \\    stig lsp                                 # Start LSP server
            \\    stig init                                # Initialize project
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
