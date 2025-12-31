//
// Configuration options for command-line arguments
//
// This module provides the Options struct which allows fine-grained control
// over argument behavior including validation, default values, requirements,
// and special handling for different argument types.
//
// The Options struct is the primary way to customize how arguments are parsed
// and validated. All fields are optional with sensible defaults, making it easy
// to configure only what you need.

const std = @import("std");

/// Function pointer type for custom argument validation.
///
/// Validation functions are called during argument parsing, after the argument
/// is matched but before type conversion occurs. This allows you to implement
/// custom validation logic beyond basic type checking.
///
/// The validation function receives the raw string arguments as they appear
/// on the command line. For single-value arguments, args will have length 1.
/// For list arguments, it may be called multiple times (once per value).
///
/// Parameters:
///   - args: Slice of raw string arguments to validate
///
/// Returns:
///   - Validation succeeds if no error is returned
///   - Any error return will halt parsing and propagate to the caller
///
/// Example - Validating port numbers:
///   fn validatePort(args: []const []const u8) !void {
///       const port = try std.fmt.parseInt(u16, args[0], 10);
///       if (port < 1024) return error.PortNumberTooLow;
///       if (port > 65535) return error.PortNumberTooHigh;
///   }
///
///   var opts = Options{};
///   opts.validate = validatePort;
///   const port = try parser.int("p", "port", &opts);
///
/// Example - Validating file extensions:
///   fn validateImageFile(args: []const []const u8) !void {
///       const path = args[0];
///       if (!std.mem.endsWith(u8, path, ".png") and 
///           !std.mem.endsWith(u8, path, ".jpg")) {
///           return error.InvalidImageFormat;
///       }
///   }
///
/// Note: The validation function is called for EACH occurrence of a list argument,
/// not once for all values. This allows per-value validation.
pub const ValidateFn = *const fn (args: []const []const u8) anyerror!void;

/// Configuration options for customizing argument behavior.
///
/// Options provides comprehensive control over how arguments are parsed,
/// validated, and presented to users. All fields are optional with defaults
/// that work for most common use cases.
///
/// The same Options struct can be reused across multiple arguments if they
/// share similar configuration requirements.
///
/// Memory Management:
///   - The Options struct itself is typically stack-allocated
///   - String values (help text, defaults) must remain valid for the parser's lifetime
///   - The parser does NOT take ownership of these strings
///
/// Usage Pattern:
///   var opts = Options{};
///   opts.required = true;
///   opts.help = "Path to configuration file";
///   opts.default_string = "/etc/myapp/config.toml";
///   const config_path = try parser.string("c", "config", &opts);
pub const Options = struct {
    /// Marks this argument as required.
    ///
    /// When true, the parser will return error.RequiredArgumentMissing if
    /// the argument is not provided by the user. Required arguments are
    /// displayed without square brackets in help output.
    ///
    /// Default: false (argument is optional)
    ///
    /// Note: Positional arguments ignore this field and are always treated
    /// as optional. If you need required positional behavior, validate in
    /// your application code after parsing.
    required: bool = false,

    /// Optional custom validation function.
    ///
    /// Called after argument matching but before type conversion. Allows
    /// implementing complex validation logic that goes beyond type checking.
    /// Validation failures propagate as errors during parsing.
    ///
    /// Default: null (no custom validation)
    ///
    /// Common use cases:
    ///   - Range validation (e.g., port must be 1-65535)
    ///   - Format validation (e.g., email address pattern)
    ///   - Path validation (e.g., file must exist)
    ///   - Business logic validation (e.g., percentage 0-100)
    ///
    /// See ValidateFn documentation for examples.
    validate: ?ValidateFn = null,

    /// Help text displayed in usage documentation.
    ///
    /// This text appears in the Arguments section when --help is invoked.
    /// Should be a brief, clear description of what the argument does.
    ///
    /// Default: "" (no help text)
    ///
    /// Special value: Use DisableDescription constant from main.zig to
    /// completely hide this argument from help output. Useful for internal
    /// or deprecated arguments.
    ///
    /// The help text is automatically enhanced with default value information
    /// when the argument is optional and has a default. No need to manually
    /// include "Default: X" in your help text.
    ///
    /// Example:
    ///   opts.help = "TCP port number to bind to";
    ///   // Help output: "TCP port number to bind to. Default: 8080"
    help: []const u8 = "",

    /// Default value for boolean flag arguments.
    ///
    /// Applied when the flag is not provided by the user. Rarely needed
    /// since flags default to false naturally.
    ///
    /// Default: null (no default, flag remains false)
    ///
    /// Use case: Inverted flags where absence means true
    ///   opts.default_bool = true;
    ///   const no_color = try parser.flag("", "no-color", &opts);
    ///   // --no-color provided: true
    ///   // --no-color omitted: true (default)
    default_bool: ?bool = null,

    /// Default value for integer arguments and flag counters.
    ///
    /// Applied when the argument is not provided by the user. Commonly used
    /// to provide sensible defaults for optional configuration values.
    ///
    /// Default: null (no default, value remains 0)
    ///
    /// Example:
    ///   opts.default_int = 8080;
    ///   const port = try parser.int("p", "port", &opts);
    ///   // No --port specified: port = 8080
    ///
    /// Note: For flag counters, this sets the initial count when the flag
    /// is not provided at all. The counter still starts from 0 if the flag
    /// appears even once.
    default_int: ?i64 = null,

    /// Default value for floating-point arguments.
    ///
    /// Applied when the argument is not provided by the user.
    ///
    /// Default: null (no default, value remains 0.0)
    ///
    /// Example:
    ///   opts.default_float = 1.5;
    ///   const scale = try parser.float("s", "scale", &opts);
    default_float: ?f64 = null,

    /// Default value for string arguments and selectors.
    ///
    /// Applied when the argument is not provided by the user. The string
    /// must remain valid for the lifetime of the parser - typically this
    /// means using string literals or long-lived allocated memory.
    ///
    /// Default: null (no default, value remains "")
    ///
    /// Example:
    ///   opts.default_string = "info";
    ///   const log_level = try parser.string("l", "log-level", &opts);
    ///
    /// For file arguments: This specifies a default file path to open.
    /// The file is opened during parsing if the argument is not provided.
    ///
    /// For selector arguments: The default must be one of the allowed values.
    default_string: ?[]const u8 = null,

    /// Default values for string list and file list arguments.
    ///
    /// Applied when the argument is not provided at all by the user. If the
    /// user provides the argument even once, the default is ignored and only
    /// user-provided values are included.
    ///
    /// Default: null (no default, list starts empty)
    ///
    /// Example:
    ///   const default_paths = [_][]const u8{ "/etc", "/usr/local/etc" };
    ///   opts.default_string_list = &default_paths;
    ///   const search_paths = try parser.stringList("I", "include", &opts);
    ///   // No -I specified: search_paths = ["/etc", "/usr/local/etc"]
    ///   // With -I /custom: search_paths = ["/custom"] (default ignored)
    ///
    /// For file lists: Each string is treated as a file path to open.
    /// All files are opened during default value application. If any file
    /// fails to open, all previously opened files are closed to prevent leaks.
    default_string_list: ?[]const []const u8 = null,

    /// Default values for integer list arguments.
    ///
    /// Applied when the argument is not provided at all by the user.
    /// Behaves identically to default_string_list but for integer arrays.
    ///
    /// Default: null (no default, list starts empty)
    ///
    /// Example:
    ///   const default_counts = [_]i64{ 10, 20, 30 };
    ///   opts.default_int_list = &default_counts;
    ///   const thresholds = try parser.intList("t", "threshold", &opts);
    default_int_list: ?[]const i64 = null,

    /// Default values for float list arguments.
    ///
    /// Applied when the argument is not provided at all by the user.
    /// Behaves identically to default_string_list but for float arrays.
    ///
    /// Default: null (no default, list starts empty)
    ///
    /// Example:
    ///   const default_weights = [_]f64{ 0.1, 0.5, 0.9 };
    ///   opts.default_float_list = &default_weights;
    ///   const weights = try parser.floatList("w", "weight", &opts);
    default_float_list: ?[]const f64 = null,

    /// Marks this argument as positional (no flag prefix required).
    ///
    /// Positional arguments are matched by their position in the command line
    /// rather than by name. They don't use -- or - prefixes and appear after
    /// all named arguments.
    ///
    /// Default: false (argument uses standard flag syntax)
    ///
    /// When true:
    ///   - Short name is cleared (not used for positional args)
    ///   - Required field is forced to false
    ///   - Argument is matched purely by position
    ///
    /// Example:
    ///   var opts = Options{};
    ///   opts.positional = true;
    ///   const filename = try parser.stringPositional(&opts);
    ///   // Usage: myapp <filename>
    ///   // Not:   myapp --filename <value>
    ///
    /// Positional arguments are processed AFTER all named arguments and
    /// subcommands have been parsed.
    ///
    /// Restrictions:
    ///   - Cannot be flag or flag_counter types
    ///   - Cannot be list types (string_list, int_list, etc.)
    ///   - Multiple positionals are matched left-to-right
    ///
    /// Note: Use the *Positional() convenience methods rather than setting
    /// this field manually. They handle the necessary configuration automatically.
    positional: bool = false,

    /// File opening options for file and file_list argument types.
    ///
    /// Controls how files are opened during argument parsing. Uses the standard
    /// Zig std.fs.File.OpenFlags structure to specify permissions, creation
    /// behavior, and access modes.
    ///
    /// Default: .{} (read-only mode)
    ///
    /// Common configurations:
    ///
    /// Read-only (default):
    ///   opts.file_options = .{};
    ///
    /// Write/create mode:
    ///   opts.file_options = .{ .mode = .write_only };
    ///
    /// Read-write mode:
    ///   opts.file_options = .{ .mode = .read_write };
    ///
    /// Create if doesn't exist:
    ///   opts.file_options = .{
    ///       .mode = .write_only,
    ///   };
    ///   // Note: in Zig, file creation behavior depends on the function used
    ///   // (openFile vs createFile). This parser uses openFile, so files must exist.
    ///
    /// Example - Opening log file for appending:
    ///   var opts = Options{};
    ///   opts.file_options = .{ .mode = .write_only };
    ///   opts.help = "Log file path";
    ///   const log_file = try parser.file("l", "log", &opts);
    ///   defer log_file.close();
    ///
    /// Important: The caller is responsible for closing opened files.
    /// File handles are NOT automatically closed when the parser is destroyed.
    /// Use defer statements or manual cleanup to prevent resource leaks.
    ///
    /// For file_list arguments: All files in the list use the same open flags.
    /// If any file fails to open, previously opened files in the list are
    /// automatically closed to prevent partial resource leaks.
    file_options: std.fs.File.OpenFlags = .{},
};