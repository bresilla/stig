const std = @import("std");

pub const VERSION = "0.1.0";

/// Output format for documentation
pub const OutputFormat = enum {
    /// Single markdown file
    markdown,
    /// mdbook directory structure
    mdbook,
};

/// CLI argument parsing result
pub const Args = struct {
    input_files: []const []const u8,
    output_file: ?[]const u8,
    output_format: OutputFormat,
    book_title: ?[]const u8,
    show_help: bool,
    show_version: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Args) void {
        self.allocator.free(self.input_files);
    }
};

/// CLI argument parser
pub const ArgParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    /// Parses command-line arguments
    pub fn parse(self: *Self) !Args {
        var args_iter = std.process.args();
        // Skip program name
        _ = args_iter.skip();

        var input_files: std.ArrayList([]const u8) = .empty;
        var output_file: ?[]const u8 = null;
        var output_format: OutputFormat = .markdown;
        var book_title: ?[]const u8 = null;
        var show_help = false;
        var show_version = false;

        while (args_iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                show_help = true;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
                show_version = true;
            } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
                output_file = args_iter.next();
                if (output_file == null) {
                    return error.MissingOutputFile;
                }
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
                const format_str = args_iter.next();
                if (format_str == null) {
                    return error.MissingFormatValue;
                }
                if (std.mem.eql(u8, format_str.?, "mdbook")) {
                    output_format = .mdbook;
                } else if (std.mem.eql(u8, format_str.?, "markdown") or std.mem.eql(u8, format_str.?, "md")) {
                    output_format = .markdown;
                } else {
                    std.debug.print("Unknown format: {s}\n", .{format_str.?});
                    return error.UnknownFormat;
                }
            } else if (std.mem.eql(u8, arg, "--title")) {
                book_title = args_iter.next();
                if (book_title == null) {
                    return error.MissingTitleValue;
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // Unknown flag
                std.debug.print("Unknown option: {s}\n", .{arg});
                return error.UnknownOption;
            } else {
                // Positional argument (input file)
                try input_files.append(self.allocator, arg);
            }
        }

        return Args{
            .input_files = try input_files.toOwnedSlice(self.allocator),
            .output_file = output_file,
            .output_format = output_format,
            .book_title = book_title,
            .show_help = show_help,
            .show_version = show_version,
            .allocator = self.allocator,
        };
    }

    /// Prints help message
    pub fn printHelp(self: *Self) void {
        _ = self;
        const help =
            \\stinger - C/C++ documentation generator
            \\
            \\USAGE:
            \\    stinger [OPTIONS] <INPUT_FILES>...
            \\
            \\ARGS:
            \\    <INPUT_FILES>...    C/C++ header files to process
            \\
            \\OPTIONS:
            \\    -o, --output <PATH>    Output file or directory (default: stdout)
            \\    -f, --format <FMT>     Output format: markdown, mdbook (default: markdown)
            \\    --title <TITLE>        Book title (for mdbook format)
            \\    -h, --help             Show this help message
            \\    -v, --version          Show version information
            \\
            \\EXAMPLES:
            \\    stinger input.h                         # Output to stdout
            \\    stinger input.h -o output.md           # Output to file
            \\    stinger src/*.h -o api.md              # Multiple files
            \\    stinger src/*.h -f mdbook -o docs/     # Generate mdbook structure
            \\    stinger src/*.h -f mdbook --title "My API"  # With custom title
            \\
        ;
        std.debug.print("{s}", .{help});
    }

    /// Prints version information
    pub fn printVersion(self: *Self) void {
        _ = self;
        std.debug.print("stinger {s}\n", .{VERSION});
    }
};

// Tests
test "parse help flag" {
    // Can't easily test args parsing without mocking
}
