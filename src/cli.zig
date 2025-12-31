const std = @import("std");

pub const VERSION = "0.1.0";

/// CLI argument parsing result
pub const Args = struct {
    input_files: []const []const u8,
    output_file: ?[]const u8,
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
            \\    -o, --output <FILE>    Output file (default: stdout)
            \\    -h, --help             Show this help message
            \\    -v, --version          Show version information
            \\
            \\EXAMPLES:
            \\    stinger input.h                    # Output to stdout
            \\    stinger input.h -o output.md      # Output to file
            \\    stinger src/*.h -o api.md         # Multiple files
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
