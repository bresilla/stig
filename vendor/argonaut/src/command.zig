const std = @import("std");
const Argument = @import("argument.zig").Argument;
const Options = @import("options.zig").Options;
const ArgumentType = @import("argument.zig").ArgumentType;
const usage_formatter = @import("usage.zig");

/// Represents a command or subcommand in the CLI hierarchy.
///
/// Commands can contain arguments, flags, and nested subcommands.
/// Each command manages its own parsing state and can generate
/// usage/help information.
pub const Command = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    args: std.ArrayList(*Argument),
    commands: std.ArrayList(*Command),
    parsed: bool,
    happened: bool,
    parent: ?*Command,
    exit_on_help: bool,
       
    /// Format string for generating unique positional argument names.
    /// Uses command name and argument index to ensure uniqueness.
    const positional_arg_name = "_positionalArg_{s}_{d}";

    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8, parent: ?*Command) !Command {
        return Command{
            .allocator = allocator,
            .name = name,
            .description = description,
            .args = std.ArrayList(*Argument){},
            .commands = std.ArrayList(*Command){},
            .parsed = false,
            .happened = false,
            .parent = parent,
            .exit_on_help = true,
        };
    }
    
    /// Cleanup all allocated resources including nested commands and arguments.
    /// Must be called to prevent memory leaks.
    pub fn deinit(self: *Command) void {
        for (self.args.items) |arg| {
            arg.deinit();
            self.allocator.destroy(arg);
        }
        self.args.deinit(self.allocator);

        for (self.commands.items) |cmd| {
            cmd.deinit();
            self.allocator.destroy(cmd);
        }
        self.commands.deinit(self.allocator);
    }
    
    /// Creates a new subcommand under this command.
    ///
    /// Subcommands inherit the allocator and maintain a parent reference.
    /// Automatically adds a help argument to the new subcommand.
    ///
    /// Example:
    ///   const commit = try parser.newCommand("commit", "Commit changes");
    ///   const message = try commit.string("m", "message", null);
    pub fn newCommand(self: *Command, name: []const u8, description: []const u8) !*Command {
        const cmd = try self.allocator.create(Command);
        cmd.* = try Command.init(self.allocator, name, description, self);
        try cmd.addHelpArg("h", "help");
        try self.commands.append(self.allocator, cmd);
        return cmd;
    }

    pub fn addHelpArg(self: *Command, short: []const u8, long: []const u8) !void {
        var opts = Options{};
        opts.help = "Print help information";

        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initHelp(self.allocator, short, long, &opts, self);
        try self.args.append(self.allocator, arg);
    }
    
    /// Adds a boolean flag argument.
    ///
    /// Flags don't require values - their presence sets them to true.
    /// Can be specified as -f or --flag.
    ///
    /// Returns: Pointer to boolean that will be set during parsing
    pub fn flag(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*bool {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFlag(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.flag;
    }
    
    /// Adds a flag counter argument that tracks repetitions.
    ///
    /// Counts how many times a flag appears (e.g., -vvv = 3).
    /// Can also accept an explicit integer value (-v 5).
    ///
    /// Returns: Pointer to i64 counter value
    pub fn flagCounter(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*i64 {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFlagCounter(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.flag_counter;
    }

    pub fn string(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*[]const u8 {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initString(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.string;
    }
    
    /// Adds a positional string argument (no flag prefix required).
    ///
    /// Positional arguments are matched by position in the argument list
    /// rather than by name. They're useful for required inputs like filenames.
    ///
    /// Example: myapp <filename> instead of myapp --file <filename>
    pub fn stringPositional(self: *Command, opts: ?*Options) !*[]const u8 {
        var options = if (opts) |o| o.* else Options{};
        options.positional = true;

        const name = try std.fmt.allocPrint(self.allocator, positional_arg_name, .{ self.name, self.args.items.len });
        defer self.allocator.free(name);

        return try self.string("", name, &options);
    }

    pub fn int(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*i64 {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initInt(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.int;
    }

    pub fn intPositional(self: *Command, opts: ?*Options) !*i64 {
        var options = if (opts) |o| o.* else Options{};
        options.positional = true;

        const name = try std.fmt.allocPrint(self.allocator, positional_arg_name, .{ self.name, self.args.items.len });
        defer self.allocator.free(name);

        return try self.int("", name, &options);
    }

    pub fn float(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*f64 {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFloat(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.float;
    }

    pub fn floatPositional(self: *Command, opts: ?*Options) !*f64 {
        var options = if (opts) |o| o.* else Options{};
        options.positional = true;

        const name = try std.fmt.allocPrint(self.allocator, positional_arg_name, .{ self.name, self.args.items.len });
        defer self.allocator.free(name);

        return try self.float("", name, &options);
    }
    
    /// Adds a string list argument that accumulates multiple values.
    ///
    /// Can be specified multiple times to build a list:
    /// myapp -f file1.txt -f file2.txt -f file3.txt
    ///
    /// Returns: Pointer to ArrayList containing all provided values
    pub fn stringList(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList([]const u8) {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initStringList(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.string_list;
    }

    pub fn intList(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(i64) {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initIntList(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.int_list;
    }

    pub fn floatList(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(f64) {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFloatList(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.float_list;
    }
    
    /// Adds a file argument that opens the specified file.
    ///
    /// The file is opened during parsing using options from Options.file_options.
    /// User is responsible for closing the file after use.
    ///
    /// Returns: Pointer to opened File handle
    pub fn file(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*std.fs.File {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFile(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.file;
    }

    pub fn filePositional(self: *Command, opts: ?*Options) !*std.fs.File {
        var options = if (opts) |o| o.* else Options{};
        options.positional = true;

        const name = try std.fmt.allocPrint(self.allocator, positional_arg_name, .{ self.name, self.args.items.len });
        defer self.allocator.free(name);

        return try self.file("", name, &options);
    }

    pub fn fileList(self: *Command, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(std.fs.File) {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initFileList(self.allocator, short, long, opts, self);
        try self.addArg(arg);
        return &arg.value.file_list;
    }
    
    /// Adds a selector argument that restricts input to predefined choices.
    ///
    /// Validates that the provided value matches one of the allowed options.
    /// Useful for enum-like inputs (e.g., --log-level debug|info|warn|error).
    ///
    /// Parameters:
    ///   - allowed: Slice of acceptable string values
    ///
    /// Returns: Pointer to selected string value
    pub fn selector(self: *Command, short: []const u8, long: []const u8, allowed: []const []const u8, opts: ?*Options) !*[]const u8 {
        const arg = try self.allocator.create(Argument);
        arg.* = try Argument.initSelector(self.allocator, short, long, allowed, opts, self);
        try self.addArg(arg);
        return &arg.value.selector;
    }

    pub fn selectorPositional(self: *Command, allowed: []const []const u8, opts: ?*Options) !*[]const u8 {
        var options = if (opts) |o| o.* else Options{};
        options.positional = true;

        const name = try std.fmt.allocPrint(self.allocator, positional_arg_name, .{ self.name, self.args.items.len });
        defer self.allocator.free(name);

        return try self.selector("", name, allowed, &options);
    }
    
    /// Validates and registers a new argument with this command.
    ///
    /// Performs validation checks:
    /// - Long name must be provided
    /// - Short name must be single character
    /// - No duplicate names (checks parent commands too)
    /// - Positional args can't be flags or lists
    ///
    /// Note: Help arguments are allowed to have duplicate names
    fn addArg(self: *Command, arg: *Argument) !void {
        if (arg.lname.len == 0) {
            return error.LongNameRequired;
        }

        if (arg.sname.len > 1) {
            return error.ShortNameTooLong;
        }

        var current: ?*Command = self;
        while (current) |cmd| {
            for (cmd.args.items) |existing| {
                if (arg.sname.len > 0 and std.mem.eql(u8, arg.sname, existing.sname)) {
                    if (!std.mem.eql(u8, arg.lname, "help")) {
                        return error.DuplicateShortName;
                    }
                }
                if (std.mem.eql(u8, arg.lname, existing.lname)) {
                    if (!std.mem.eql(u8, arg.lname, "help")) {
                        return error.DuplicateLongName;
                    }
                }
            }
            current = cmd.parent;
        }

        if (arg.opts.positional) {
            switch (arg.arg_type) {
                .flag, .flag_counter, .string_list, .int_list, .float_list, .file_list => {
                    return error.InvalidPositionalType;
                },
                else => {},
            }
            arg.sname = "";
            arg.opts.required = false;
            arg.size = 1;
        }

        try self.args.append(self.allocator, arg);
    }
    
    /// Main parsing entry point for this command.
    ///
    /// Processes the argument list in order:
    /// 1. Validates command name matches (for subcommands)
    /// 2. Parses any subcommands first
    /// 3. Parses this command's arguments
    ///
    /// The args list is modified during parsing - matched arguments
    /// are replaced with empty strings to track what's been processed.
    pub fn parse(self: *Command, args: *std.ArrayList([]const u8)) anyerror!void {
        if (self.parsed) {
            return;
        }

        if (args.items.len < 1) {
            return;
        }

        if (self.name.len == 0) {
            self.name = args.items[0];
        } else {
            if (self.parent != null and !std.mem.eql(u8, self.name, args.items[0])) {
                return;
            }
        }

        self.happened = true;

        _ = args.orderedRemove(0);

        try self.parseSubCommands(args);
        try self.parseArguments(args);

        self.parsed = true;
    }

    fn parseSubCommands(self: *Command, args: *std.ArrayList([]const u8)) !void {
        if (self.commands.items.len > 0) {
            if (args.items.len < 1) {
                return error.SubCommandRequired;
            }

            for (self.commands.items) |cmd| {
                try cmd.parse(args);
                if (cmd.happened) {
                    return;
                }
            }

            return error.SubCommandRequired;
        }
    }
    
    /// Parses named arguments (flags and options with -- or - prefix).
    ///
    /// Handles both space-separated (--name value) and equals-separated
    /// (--name=value) formats. Validates required arguments and applies
    /// default values for missing optional arguments.
    fn parseArguments(self: *Command, args: *std.ArrayList([]const u8)) !void {
        for (self.args.items) |arg| {
            if (arg.opts.positional) {
                continue;
            }

            var i: usize = 0;
            while (i < args.items.len) : (i += 1) {
                const current_arg = args.items[i];
                if (current_arg.len == 0) {
                    continue;
                }

                if (std.mem.indexOf(u8, current_arg, "=")) |eq_pos| {
                    const arg_part = current_arg[0..eq_pos];
                    const val_part = current_arg[eq_pos + 1 ..];

                    const count = try arg.check(arg_part);
                    if (count > 0) {
                        if (val_part.len == 0) {
                            return error.NotEnoughArguments;
                        }

                        arg.eq_char = true;
                        arg.size = 1;

                        var val_array = [_][]const u8{val_part};
                        try arg.parseValue(&val_array, count);
                        arg.reduce(i, args);
                        continue;
                    }
                }

                const count = try arg.check(current_arg);
                if (count > 0) {
                    if (args.items.len < i + arg.size) {
                        return error.NotEnoughArguments;
                    }

                    const arg_values = args.items[i + 1 .. i + arg.size];
                    try arg.parseValue(arg_values, count);
                    arg.reduce(i, args);
                    continue;
                }
            }

            if (arg.opts.required and !arg.parsed) {
                return error.RequiredArgumentMissing;
            } else if (!arg.parsed) {
                try arg.setDefault();
            }
        }
    }

    pub fn parsePositionals(self: *Command, args: *std.ArrayList([]const u8)) !void {
        for (self.args.items) |arg| {
            if (!arg.opts.positional) {
                continue;
            }

            for (args.items, 0..) |current_arg, i| {
                if (current_arg.len == 0) {
                    continue;
                }

                try arg.parsePositional(current_arg);
                arg.reduce(i, args);
                break;
            }

            if (!arg.parsed) {
                try arg.setDefault();
            }
        }

        for (self.commands.items) |cmd| {
            if (cmd.happened) {
                return try cmd.parsePositionals(args);
            }
        }
    }

    pub fn disableHelp(self: *Command) void {
        var i: usize = 0;
        while (i < self.args.items.len) {
            const arg = self.args.items[i];
            if (arg.arg_type == .help) {
                const removed = self.args.orderedRemove(i);
                removed.deinit();
                self.allocator.destroy(removed);
            } else {
                i += 1;
            }
        }

        for (self.commands.items) |cmd| {
            cmd.disableHelp();
        }
    }

    pub fn setHelp(self: *Command, short: []const u8, long: []const u8) !void {
        self.disableHelp();
        try self.addHelpArg(short, long);
    }

    pub fn exitOnHelp(self: *Command, value: bool) void {
        self.exit_on_help = value;
        for (self.commands.items) |cmd| {
            cmd.exitOnHelp(value);
        }
    }

    pub fn usage(self: *Command, msg: ?[]const u8) ![]const u8 {
        for (self.commands.items) |cmd| {
            if (cmd.happened) {
                return try cmd.usage(msg);
            }
        }

        return try usage_formatter.formatUsage(self, msg);
    }
};
