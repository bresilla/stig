const std = @import("std");
const argonaut = @import("argonaut");
const config_mod = @import("config.zig");

pub const VERSION = "0.1.0";
pub const Config = config_mod.Config;

/// Output format for documentation
pub const OutputFormat = enum {
    /// Single markdown file
    markdown,
    /// mdbook directory structure
    mdbook,
    /// JSON structured output
    json,

    pub fn fromConfig(cfg_format: Config.Format) OutputFormat {
        return switch (cfg_format) {
            .markdown => .markdown,
            .mdbook => .mdbook,
            .json => .json,
        };
    }
};

/// CLI argument parsing result
pub const Args = struct {
    input_files: []const []const u8,
    output_file: ?[]const u8,
    output_format: OutputFormat,
    format_explicitly_set: bool,
    book_title: ?[]const u8,
    config_file: ?[]const u8,
    show_help: bool,
    show_version: bool,
    watch_mode: bool,
    serve_mode: bool,
    coverage_mode: bool,
    lint_mode: bool,
    force_rebuild: bool,
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

    // Argument pointers
    output_ptr: ?*[]const u8,
    format_ptr: ?*[]const u8,
    title_ptr: ?*[]const u8,
    config_ptr: ?*[]const u8,
    help_ptr: ?*bool,
    version_ptr: ?*bool,
    watch_ptr: ?*bool,
    serve_ptr: ?*bool,
    coverage_ptr: ?*bool,
    lint_ptr: ?*bool,
    force_ptr: ?*bool,

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
            .help_ptr = null,
            .version_ptr = null,
            .watch_ptr = null,
            .serve_ptr = null,
            .coverage_ptr = null,
            .lint_ptr = null,
            .force_ptr = null,
        };
    }

    /// Parses command-line arguments using argonaut
    pub fn parse(self: *Self) !Args {
        // Create argonaut parser
        self.parser = try argonaut.newParser(
            self.allocator,
            "stig",
            "C/C++ documentation generator using tree-sitter",
        );
        const parser = self.parser.?;

        // Disable argonaut's automatic help - we'll handle it ourselves
        parser.command.disableHelp();

        // Define arguments
        var output_opts = argonaut.Options{};
        output_opts.help = "Output file or directory (default: stdout)";
        self.output_ptr = try parser.string("o", "output", &output_opts);

        var format_opts = argonaut.Options{};
        format_opts.help = "Output format: markdown, mdbook, json (default: markdown)";
        // Don't set default - we'll check if it was explicitly set
        self.format_ptr = try parser.string("f", "format", &format_opts);

        var title_opts = argonaut.Options{};
        title_opts.help = "Book title (for mdbook format)";
        self.title_ptr = try parser.string("", "title", &title_opts);

        var config_opts = argonaut.Options{};
        config_opts.help = "Config file path (default: stig.toml)";
        self.config_ptr = try parser.string("c", "config", &config_opts);

        var version_opts = argonaut.Options{};
        version_opts.help = "Show version information";
        self.version_ptr = try parser.flag("v", "version", &version_opts);

        var watch_opts = argonaut.Options{};
        watch_opts.help = "Watch for file changes and regenerate";
        self.watch_ptr = try parser.flag("w", "watch", &watch_opts);

        var serve_opts = argonaut.Options{};
        serve_opts.help = "Watch mode + spawn mdbook serve for live preview";
        self.serve_ptr = try parser.flag("", "serve", &serve_opts);

        var coverage_opts = argonaut.Options{};
        coverage_opts.help = "Generate documentation coverage report";
        self.coverage_ptr = try parser.flag("C", "coverage", &coverage_opts);

        var lint_opts = argonaut.Options{};
        lint_opts.help = "Lint documentation for errors and warnings";
        self.lint_ptr = try parser.flag("L", "lint", &lint_opts);

        var force_opts = argonaut.Options{};
        force_opts.help = "Force full rebuild, ignore cache";
        self.force_ptr = try parser.flag("", "force", &force_opts);

        var help_opts = argonaut.Options{};
        help_opts.help = "Show this help message";
        self.help_ptr = try parser.flag("h", "help", &help_opts);

        // Get process args - we need to keep these alive since argonaut stores references
        self.process_args = try std.process.argsAlloc(self.allocator);
        const process_args = self.process_args.?;

        // Parse arguments - use parseWithRemainder to get positional args (input files)
        self.remainder = parser.parseWithRemainder(process_args) catch |err| {
            return err;
        };

        // Check for help flag
        if (self.help_ptr.?.*) {
            return Args{
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .show_help = true,
                .show_version = false,
                .watch_mode = false,
                .serve_mode = false,
                .coverage_mode = false,
                .lint_mode = false,
                .force_rebuild = false,
                .allocator = self.allocator,
            };
        }

        // Check for version flag
        if (self.version_ptr.?.*) {
            return Args{
                .input_files = &[_][]const u8{},
                .output_file = null,
                .output_format = .markdown,
                .format_explicitly_set = false,
                .book_title = null,
                .config_file = null,
                .show_help = false,
                .show_version = true,
                .watch_mode = false,
                .serve_mode = false,
                .coverage_mode = false,
                .lint_mode = false,
                .force_rebuild = false,
                .allocator = self.allocator,
            };
        }

        // Parse format - check if it was explicitly set
        const format_str = self.format_ptr.?.*;
        var output_format: OutputFormat = .markdown;
        var format_explicitly_set = false;
        // Only set format_explicitly_set if user actually passed -f flag
        if (format_str.len > 0) {
            format_explicitly_set = true;
            if (std.mem.eql(u8, format_str, "mdbook")) {
                output_format = .mdbook;
            } else if (std.mem.eql(u8, format_str, "md") or std.mem.eql(u8, format_str, "markdown")) {
                output_format = .markdown;
            } else if (std.mem.eql(u8, format_str, "json")) {
                output_format = .json;
            }
        }

        // Get output file (null if empty)
        const output_str = self.output_ptr.?.*;
        const output_file: ?[]const u8 = if (output_str.len > 0) output_str else null;

        // Get title (null if empty)
        const title_str = self.title_ptr.?.*;
        const book_title: ?[]const u8 = if (title_str.len > 0) title_str else null;

        // Get config file (null if empty)
        const config_str = self.config_ptr.?.*;
        const config_file: ?[]const u8 = if (config_str.len > 0) config_str else null;

        // Get watch/serve/coverage/lint/force modes
        const watch_mode = self.watch_ptr.?.* or self.serve_ptr.?.*;
        const serve_mode = self.serve_ptr.?.*;
        const coverage_mode = self.coverage_ptr.?.*;
        const lint_mode = self.lint_ptr.?.*;
        const force_rebuild = self.force_ptr.?.*;

        // Get input files from remainder (positional arguments)
        const input_files = if (self.remainder) |rem|
            try self.allocator.dupe([]const u8, rem)
        else
            &[_][]const u8{};

        return Args{
            .input_files = input_files,
            .output_file = output_file,
            .output_format = output_format,
            .format_explicitly_set = format_explicitly_set,
            .book_title = book_title,
            .config_file = config_file,
            .show_help = false,
            .show_version = false,
            .watch_mode = watch_mode,
            .serve_mode = serve_mode,
            .coverage_mode = coverage_mode,
            .lint_mode = lint_mode,
            .force_rebuild = force_rebuild,
            .allocator = self.allocator,
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
        // Always use our custom help for better formatting
        _ = self;
        printFallbackHelp();
    }

    fn printFallbackHelp() void {
        const help =
            \\stig - C/C++ documentation generator
            \\
            \\USAGE:
            \\    stig [OPTIONS] <INPUT_FILES>...
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to process
            \\
            \\OPTIONS:
            \\    -o, --output <PATH>    Output file or directory (default: stdout)
            \\    -f, --format <FMT>     Output format: markdown, mdbook, json (default: markdown)
            \\    --title <TITLE>        Book title (for mdbook format)
            \\    -c, --config <FILE>    Config file path (default: stig.toml)
            \\    -w, --watch            Watch for file changes and regenerate
            \\    --serve                Watch mode + spawn mdbook serve for live preview
            \\    -C, --coverage         Generate documentation coverage report
            \\    -L, --lint             Lint documentation for errors and warnings
            \\    --force                Force full rebuild, ignore cache
            \\    -h, --help             Show this help message
            \\    -v, --version          Show version information
            \\
            \\CONFIG FILE:
            \\    stig looks for stig.toml in the current directory.
            \\    CLI arguments override config file settings.
            \\
            \\    Example stig.toml:
            \\        title = "My API"
            \\        output = "docs"
            \\        format = "mdbook"
            \\        inputs = ["src/*.h", "include/*.h"]
            \\
            \\SUBCOMMANDS:
            \\    preprocessor    Run as mdbook preprocessor (reads JSON from stdin)
            \\
            \\EXAMPLES:
            \\    stig input.h                         # Output to stdout
            \\    stig input.h -o output.md           # Output to file
            \\    stig src/*.h -o api.md              # Multiple files
            \\    stig src/*.h -f mdbook -o docs/     # Generate mdbook structure
            \\    stig src/*.h -f mdbook --title "My API"  # With custom title
            \\    stig src/*.h -f json -o api.json   # Generate JSON output
            \\    stig src/*.h -f json               # JSON to stdout
            \\    stig -c myconfig.toml               # Use custom config file
            \\    stig src/*.h -f mdbook -o docs/ --watch  # Watch mode
            \\    stig src/*.h -f mdbook -o docs/ --serve  # Watch + live preview
            \\    stig --coverage src/*.h            # Generate coverage report
            \\    stig --lint src/*.h               # Lint documentation
            \\
            \\MDBOOK PREPROCESSOR:
            \\    Add to book.toml:
            \\        [preprocessor.stig]
            \\        command = "stig preprocessor"
            \\
            \\    Use in chapters:
            \\        {{#stig api ../include/mylib.h}}
            \\        {{#stig function my_function}}
            \\        {{#stig struct MyStruct}}
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
