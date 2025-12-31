//! Command-line argument parser library for Zig
//! Provides a fluent API for defining CLI arguments, flags, and subcommands
//! with automatic help generation and validation support.


const std = @import("std");
pub const Parser = @import("parser.zig").Parser;
pub const Command = @import("command.zig").Command;
pub const Argument = @import("argument.zig").Argument;
pub const Options = @import("options.zig").Options;

/// Special constant to disable description display in help output.
/// When used as a description string, the associated command or argument
/// will not appear in the generated help text.
pub const DisableDescription = "DISABLEDDESCRIPTIONWILLNOTSHOWUP";

/// Creates and initializes a new command-line argument parser.
///
/// This is the primary entry point for the library. The parser manages
/// the root command and provides methods for defining arguments, flags,
/// and subcommands.
///
/// Parameters:
///   - allocator: Memory allocator for parser and argument storage
///   - name: Program name (typically argv[0])
///   - description: Brief description shown in help output
///
/// Returns: Pointer to initialized Parser or error
///
/// Example:
///   const parser = try parser.newParser(allocator, "myapp", "My CLI application");
///   defer parser.deinit();
pub fn newParser(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !*Parser {
    return try Parser.init(allocator, name, description);
}

test "basic parser creation" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    try std.testing.expectEqualStrings("test", parser.name);
}

test "parser with string argument" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const name = try parser.string("n", "name", null);

    var args = [_][]const u8{ "test", "--name", "John" };
    try parser.parse(&args);

    try std.testing.expectEqualStrings("John", name.*);
}

test "parser with flag argument" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const verbose = try parser.flag("v", "verbose", null);

    var args = [_][]const u8{ "test", "-v" };
    try parser.parse(&args);

    try std.testing.expect(verbose.*);
}

test "parser with int argument" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const count = try parser.int("c", "count", null);

    var args = [_][]const u8{ "test", "--count", "42" };
    try parser.parse(&args);

    try std.testing.expectEqual(@as(i64, 42), count.*);
}

test "parser with subcommand" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "git", "Git version control");
    defer parser.deinit();

    const commit = try parser.newCommand("commit", "Commit changes");
    const message = try commit.string("m", "message", null);

    var args = [_][]const u8{ "git", "commit", "-m", "Initial commit" };
    try parser.parse(&args);

    try std.testing.expect(commit.happened);
    try std.testing.expectEqualStrings("Initial commit", message.*);
}

test "parser with required argument missing" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    var opts = Options{};
    opts.required = true;

    _ = try parser.string("n", "name", &opts);

    var args = [_][]const u8{"test"};
    const result = parser.parse(&args);

    try std.testing.expectError(error.RequiredArgumentMissing, result);
}

test "parser with positional argument" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const filename = try parser.stringPositional(null);

    var args = [_][]const u8{ "test", "file.txt" };
    try parser.parse(&args);

    try std.testing.expectEqualStrings("file.txt", filename.*);
}

test "parser with string list" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const files = try parser.stringList("f", "file", null);

    var args = [_][]const u8{ "test", "-f", "a.txt", "-f", "b.txt" };
    try parser.parse(&args);

    try std.testing.expectEqual(@as(usize, 2), files.items.len);
    try std.testing.expectEqualStrings("a.txt", files.items[0]);
    try std.testing.expectEqualStrings("b.txt", files.items[1]);
}

test "parser with default value" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    var opts = Options{};
    opts.default_string = "default_name";

    const name = try parser.string("n", "name", &opts);

    var args = [_][]const u8{"test"};
    try parser.parse(&args);

    try std.testing.expectEqualStrings("default_name", name.*);
}

test "parser with selector" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    var allowed = [_][]const u8{ "red", "green", "blue" };
    const color = try parser.selector("c", "color", &allowed, null);

    var args = [_][]const u8{ "test", "--color", "green" };
    try parser.parse(&args);

    try std.testing.expectEqualStrings("green", color.*);
}

test "parser with flag counter" {
    const allocator = std.testing.allocator;
    const parser = try newParser(allocator, "test", "Test program");
    defer parser.deinit();

    const verbose = try parser.flagCounter("v", "verbose", null);

    var args = [_][]const u8{ "test", "-vvv" };
    try parser.parse(&args);

    try std.testing.expectEqual(@as(i64, 3), verbose.*);
}
