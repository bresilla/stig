const std = @import("std");
const Command = @import("command.zig").Command;
const Argument = @import("argument.zig").Argument;

const max_width: usize = 100;

/// Generates complete usage documentation for a command.
///
/// Output format:
///   usage: <command-chain> [arguments] [<command>]
///          <description>
///
///   Commands:
///     <command>    <description>
///     ...
///
///   Arguments:
///     -s  --long   <description>
///     ...
///
/// The formatter handles line wrapping to stay within max_width characters.
pub fn formatUsage(cmd: *Command, msg: ?[]const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    const writer = result.writer(cmd.allocator);
    if (msg) |message| {
        try writer.print("{s}\n\n", .{message});
    }

    try writer.writeAll("usage:");

    var chain = std.ArrayList([]const u8){};
    defer chain.deinit(cmd.allocator);

    var arguments = std.ArrayList(*Argument){};
    defer arguments.deinit(cmd.allocator);

    try getPrecedingCommands(cmd, &chain, &arguments);

    const left_padding = 7 + chain.items[0].len;

    for (chain.items) |command_name| {
        try addToLastLine(&result, command_name, left_padding, cmd.allocator);
    }

    var used_help = false;
    for (arguments.items) |arg| {
        if (std.mem.eql(u8, arg.opts.help, @import("main.zig").DisableDescription)) {
            continue;
        }

        if (std.mem.eql(u8, arg.lname, "help") and used_help) {
            continue;
        }

        const usage_str = try arg.getUsage(cmd.allocator);
        defer cmd.allocator.free(usage_str);

        try addToLastLine(&result, usage_str, left_padding, cmd.allocator);

        if (std.mem.eql(u8, arg.lname, "help") or std.mem.eql(u8, arg.sname, "h")) {
            used_help = true;
        }
    }

    var subcommands = std.ArrayList(Command){};
    defer subcommands.deinit(cmd.allocator);

    try getSubCommands(cmd, &subcommands);

    if (subcommands.items.len > 0) {
        try addToLastLine(&result, "<command>", left_padding, cmd.allocator);
    }

    try writer.writeAll("\n\n");
    const spaces = try cmd.allocator.alloc(u8, left_padding);
    defer cmd.allocator.free(spaces);
    @memset(spaces, ' ');
    try writer.writeAll(spaces);

    try addToLastLine(&result, cmd.description, left_padding, cmd.allocator); 
    try writer.writeAll("\n\n");

    if (subcommands.items.len > 0) {
        try formatCommands(&result, &subcommands, cmd.allocator);
    }

    if (arguments.items.len > 0) {
        try formatArguments(&result, &arguments, cmd.allocator);
    }

    return result.toOwnedSlice(cmd.allocator);
}

fn getPrecedingCommands(cmd: *Command, chain: *std.ArrayList([]const u8), arguments: *std.ArrayList(*Argument)) !void {
    var current: ?*Command = cmd;

    while (current) |c| {
        try chain.insert(c.allocator, 0, c.name);

        for (c.args.items) |arg| {
            var found = false;
            for (arguments.items) |existing| {
                if (existing == arg) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try arguments.insert(c.allocator, 0, arg); 
            }
        }

        current = c.parent;
    }
}

fn getSubCommands(cmd: *Command, subcommands: *std.ArrayList(Command)) !void {
    if (cmd.commands.items.len > 0) {
        for (cmd.commands.items) |subcmd| {
            if (std.mem.eql(u8, subcmd.description, @import("main.zig").DisableDescription)) {
                continue;
            }
            try subcommands.append(cmd.allocator, subcmd.*);  
        }
    }
}

fn formatCommands(result: *std.ArrayList(u8), commands: *std.ArrayList(Command), allocator: std.mem.Allocator) !void {
    const writer = result.writer(allocator);

    try writer.writeAll("Commands:\n\n");

    var cmd_padding: usize = 0;
    for (commands.items) |cmd| {
        const len = 2 + cmd.name.len + 2;
        if (len > cmd_padding) {
            cmd_padding = len;
        }
    }

    for (commands.items) |cmd| {
        try writer.writeAll("  ");
        try writer.writeAll(cmd.name);

        const spaces_needed = cmd_padding - 2 - cmd.name.len - 1;
        var i: usize = 0;
        while (i < spaces_needed) : (i += 1) {
            try writer.writeAll(" ");
        }

        try addToLastLine(result, cmd.description, cmd_padding, allocator);
        try writer.writeAll("\n");
    }

    try writer.writeAll("\n");
}

fn formatArguments(result: *std.ArrayList(u8), arguments: *std.ArrayList(*Argument), allocator: std.mem.Allocator) !void {
    const writer = result.writer(allocator);

    try writer.writeAll("Arguments:\n\n");

    var arg_padding: usize = 0;
    for (arguments.items) |arg| {
        if (std.mem.eql(u8, arg.opts.help, @import("main.zig").DisableDescription)) {
            continue;
        }

        const len = arg.lname.len + 9;
        if (len > arg_padding) {
            arg_padding = len;
        }
    }

    var used_help = false;
    for (arguments.items) |arg| {
        if (std.mem.eql(u8, arg.opts.help, @import("main.zig").DisableDescription)) {
            continue;
        }

        if (std.mem.eql(u8, arg.lname, "help") and used_help) {
            continue;
        }

        try writer.writeAll("  ");

        if (arg.sname.len > 0) {
            try writer.print("-{s}  ", .{arg.sname});
        } else {
            try writer.writeAll("    ");
        }

        try writer.print("--{s}", .{arg.lname});

        const current_len: usize = 2 + 4 + 2 + arg.lname.len; 
        const spaces_needed = if (arg_padding > current_len) arg_padding - current_len else 0;

        var i: usize = 0;
        while (i < spaces_needed) : (i += 1) {
            try writer.writeAll(" ");
        }

        if (arg.opts.help.len > 0) {
            var help_msg = std.ArrayList(u8){};
            defer help_msg.deinit(allocator);

            try help_msg.appendSlice(allocator, arg.opts.help);

            if (!arg.opts.required) {
                const help_writer = help_msg.writer(allocator);
                if (arg.opts.default_string) |default| {
                    try help_writer.print(". Default: {s}", .{default});
                } else if (arg.opts.default_int) |default| {
                    try help_writer.print(". Default: {d}", .{default});
                } else if (arg.opts.default_float) |default| {
                    try help_writer.print(". Default: {d}", .{default});
                } else if (arg.opts.default_bool) |default| {
                    try help_writer.print(". Default: {}", .{default});
                }
            }

            try addToLastLine(result, help_msg.items, arg_padding, allocator);
        }

        try writer.writeAll("\n");

        if (std.mem.eql(u8, arg.lname, "help") or std.mem.eql(u8, arg.sname, "h")) {
            used_help = true;
        }
    }

    try writer.writeAll("\n");
}

/// Intelligently adds text to the current line with wrapping.
///
/// If the text fits on the current line, it's appended with a space.
/// If not, and the line has at least 10% remaining space, the text
/// is split into words and added recursively.
/// Otherwise, a new line is started with appropriate padding.
///
/// This creates nicely formatted, readable help text that respects
/// the max_width constraint.
fn addToLastLine(result: *std.ArrayList(u8), text: []const u8, left_padding: usize, allocator: std.mem.Allocator) !void {
    const last_line = getLastLine(result.items);
    const has_ten_percent = (max_width - last_line.len) > max_width / 10;

    if (last_line.len + 1 + text.len >= max_width) {
        if (has_ten_percent and std.mem.indexOf(u8, text, " ") != null) {
            var iter = std.mem.splitScalar(u8, text, ' ');
            while (iter.next()) |word| {
                try addToLastLine(result, word, left_padding, allocator);
            }
            return;
        }

        try result.append(allocator, '\n');
        var i: usize = 0;
        while (i < left_padding) : (i += 1) {
            try result.append(allocator, ' '); 
        }
    }

    try result.append(allocator, ' ');
    try result.appendSlice(allocator, text); 
}

fn getLastLine(input: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, input, "\n")) |pos| {
        return input[pos + 1 ..];
    }
    return input;
}
