const std = @import("std");
const Options = @import("options.zig").Options;

/// Enumeration of all supported argument types.
pub const ArgumentType = enum {
    help,
    flag,
    flag_counter,
    string,
    int,
    float,
    file,
    string_list,
    int_list,
    float_list,
    file_list,
    selector,
};

/// Tagged union holding the actual value for each argument type.
///
/// The active variant matches the ArgumentType enum.
/// Memory management is handled by the Argument.deinit() method.
pub const ArgumentValue = union(ArgumentType) {
    help: void,
    flag: bool,
    flag_counter: i64,
    string: []const u8,
    int: i64,
    float: f64,
    file: std.fs.File,
    string_list: std.ArrayList([]const u8),
    int_list: std.ArrayList(i64),
    float_list: std.ArrayList(f64),
    file_list: std.ArrayList(std.fs.File),
    selector: []const u8,
};

/// Represents a single command-line argument with its configuration and value.
///
/// Arguments track their parsed state and can validate, parse, and format
/// themselves. They maintain references to their parent command for
/// context during parsing.
pub const Argument = struct {
    allocator: std.mem.Allocator,
    value: ArgumentValue,
    opts: Options,
    sname: []const u8, // Short name (single character, e.g., "v")
    lname: []const u8, // Long name (full word, e.g., "verbose")
    size: usize, // Number of values this argument consumes (1 for flags, 2 for valued args)
    unique: bool, // If true, argument can only appear once
    parsed: bool, // Tracks if this argument was successfully parsed
    selector_options: ?[]const []const u8, // Valid choices for selector type
    parent: ?*anyopaque, // Parent Command pointer (type-erased to avoid circular dependency)
    eq_char: bool, // True if parsed using --name=value format
    arg_type: ArgumentType,

    pub fn initHelp(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .help = {} },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 1,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .help,
        };
    }

    pub fn initFlag(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .flag = false },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 1,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .flag,
        };
    }

    pub fn initFlagCounter(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .flag_counter = 0 },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 1,
            .unique = false,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .flag_counter,
        };
    }

    pub fn initString(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .string = "" },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .string,
        };
    }

    pub fn initInt(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .int = 0 },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .int,
        };
    }

    pub fn initFloat(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .float = 0.0 },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .float,
        };
    }

    pub fn initFile(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .file = undefined },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = true,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .file,
        };
    }

    pub fn initStringList(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .string_list = std.ArrayList([]const u8){} },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = false,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .string_list,
        };
    }

    pub fn initIntList(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .int_list = std.ArrayList(i64){} },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = false,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .int_list,
        };
    }

    pub fn initFloatList(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .float_list = std.ArrayList(f64){} },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = false,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .float_list,
        };
    }

    pub fn initFileList(allocator: std.mem.Allocator, short: []const u8, long: []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .file_list = std.ArrayList(std.fs.File){} },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = false,
            .parsed = false,
            .selector_options = null,
            .parent = parent,
            .eq_char = false,
            .arg_type = .file_list,
        };
    }

    pub fn initSelector(allocator: std.mem.Allocator, short: []const u8, long: []const u8, allowed: []const []const u8, opts: ?*Options, parent: ?*anyopaque) !Argument {
        return Argument{
            .allocator = allocator,
            .value = .{ .selector = "" },
            .opts = if (opts) |o| o.* else Options{},
            .sname = short,
            .lname = long,
            .size = 2,
            .unique = true,
            .parsed = false,
            .selector_options = allowed,
            .parent = parent,
            .eq_char = false,
            .arg_type = .selector,
        };
    }

    /// Cleans up resources allocated by this argument.
    ///
    /// Handles type-specific cleanup:
    /// - List types: deinitialize ArrayLists
    /// - File types: close file handles
    /// - Other types: no cleanup needed
    pub fn deinit(self: *Argument) void {
        switch (self.value) {
            .string_list => |*list| list.deinit(self.allocator),
            .int_list => |*list| list.deinit(self.allocator),
            .float_list => |*list| list.deinit(self.allocator),
            .file_list => |*list| {
                for (list.items) |*file| {
                    file.close();
                }
                list.deinit(self.allocator);
            },
            .file => |*file| {
                if (self.parsed) {
                    file.close();
                }
            },
            else => {},
        }
    }

    /// Checks if the given argument string matches this argument's names.
    ///
    /// Returns the count of matches found:
    /// - For long names: returns 1 if matched
    /// - For short names: returns count of occurrences (for flag counters like -vvv)
    ///
    /// Returns 0 if no match.
    pub fn check(self: *Argument, arg: []const u8) !usize {
        const long_count = self.checkLongName(arg);
        if (long_count > 0) {
            return long_count;
        }
        return try self.checkShortName(arg);
    }

    fn checkLongName(self: *Argument, arg: []const u8) usize {
        if (self.lname.len == 0) {
            return 0;
        }

        if (arg.len > 2 and std.mem.startsWith(u8, arg, "--") and arg[2] != '-') {
            if (std.mem.eql(u8, arg[2..], self.lname)) {
                return 1;
            }
        }

        return 0;
    }

    fn checkShortName(self: *Argument, arg: []const u8) !usize {
        if (self.sname.len == 0) {
            return 0;
        }

        if (arg.len > 1 and std.mem.startsWith(u8, arg, "-") and arg[1] != '-') {
            const count = std.mem.count(u8, arg[1..], self.sname);

            if (self.size == 1) {
                return count;
            } else if (self.size > 1) {
                if (count > 1) {
                    return error.ParameterMustFollow;
                }
                if (std.mem.endsWith(u8, arg[1..], self.sname)) {
                    return count;
                }
            }
        }

        return 0;
    }

    pub fn reduce(self: *Argument, position: usize, args: *std.ArrayList([]const u8)) void {
        if (self.opts.positional) {
            self.reducePositional(position, args);
        } else {
            self.reduceLongName(position, args);
            self.reduceShortName(position, args);
        }
    }

    fn reducePositional(self: *Argument, position: usize, args: *std.ArrayList([]const u8)) void {
        _ = self;
        args.items[position] = "";
    }

    fn reduceLongName(self: *Argument, position: usize, args: *std.ArrayList([]const u8)) void {
        const arg = args.items[position];

        if (self.lname.len == 0) {
            return;
        }

        if (arg.len > 2 and std.mem.startsWith(u8, arg, "--") and arg[2] != '-') {
            var check_arg = arg;
            if (self.eq_char) {
                if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                    check_arg = arg[0..eq_pos];
                }
            }

            if (std.mem.eql(u8, check_arg[2..], self.lname)) {
                var i = position;
                while (i < position + self.size and i < args.items.len) : (i += 1) {
                    args.items[i] = "";
                }
            }
        }
    }

    fn reduceShortName(self: *Argument, position: usize, args: *std.ArrayList([]const u8)) void {
        const arg = args.items[position];

        if (self.sname.len == 0) {
            return;
        }

        if (arg.len > 1 and std.mem.startsWith(u8, arg, "-") and arg[1] != '-') {
            if (self.size == 1) {
                if (std.mem.indexOf(u8, arg[1..], self.sname) != null) {
                    const replaced = std.mem.replaceOwned(u8, self.allocator, arg, self.sname, "") catch return;
                    defer self.allocator.free(replaced);

                    if (std.mem.eql(u8, replaced, "-")) {
                        args.items[position] = "";
                    } else {
                        args.items[position] = replaced;
                    }

                    if (self.eq_char) {
                        args.items[position] = "";
                    }
                }
            } else {
                if (std.mem.eql(u8, arg[1..], self.sname)) {
                    var i = position;
                    while (i < position + self.size and i < args.items.len) : (i += 1) {
                        args.items[i] = "";
                    }
                }
            }
        }
    }

    /// Parses the provided argument values according to this argument's type.
    ///
    /// Validates uniqueness constraints, runs custom validators, and delegates
    /// to type-specific parsing functions.
    ///
    /// Parameters:
    ///   - args: Array of string values to parse
    ///   - count: Number of times this argument appeared (for flag counters)
    pub fn parseValue(self: *Argument, args: []const []const u8, count: usize) !void {
        if (self.unique and (self.parsed or count > 1)) {
            return error.ArgumentMustBeUnique;
        }

        if (self.opts.validate) |validate_fn| {
            try validate_fn(args);
        }

        switch (self.value) {
            .help => try self.parseHelp(),
            .flag => try self.parseFlag(),
            .flag_counter => try self.parseFlagCounter(args, count),
            .string => try self.parseString(args),
            .int => try self.parseInt(args),
            .float => try self.parseFloat(args),
            .file => try self.parseFile(args),
            .string_list => try self.parseStringList(args),
            .int_list => try self.parseIntList(args),
            .float_list => try self.parseFloatList(args),
            .file_list => try self.parseFileList(args),
            .selector => try self.parseSelector(args),
        }
    }

    fn parseHelp(self: *Argument) !void {
        const Command = @import("command.zig").Command;
        const parent = @as(*Command, @ptrCast(@alignCast(self.parent.?)));
        const usage_text = try parent.usage(null);
        defer parent.allocator.free(usage_text);

        std.debug.print("{s}\n", .{usage_text});

        if (parent.exit_on_help) {
            std.process.exit(0);
        }
    }

    fn parseFlag(self: *Argument) !void {
        self.value.flag = true;
        self.parsed = true;
    }

    fn parseFlagCounter(self: *Argument, args: []const []const u8, count: usize) !void {
        if (args.len < 1) {
            if (self.size > 1) {
                return error.MustBeFollowedByInteger;
            }
            self.value.flag_counter += @as(i64, @intCast(count));
        } else if (args.len > 1) {
            return error.TooManyArguments;
        } else {
            const val = try std.fmt.parseInt(i64, args[0], 10);
            self.value.flag_counter = val;
        }
        self.parsed = true;
    }

    fn parseString(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByString;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        self.value.string = args[0];
        self.parsed = true;
    }

    fn parseInt(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByInteger;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const val = std.fmt.parseInt(i64, args[0], 10) catch {
            return error.BadIntegerValue;
        };

        self.value.int = val;
        self.parsed = true;
    }

    fn parseFloat(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByFloat;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const val = std.fmt.parseFloat(f64, args[0]) catch {
            return error.BadFloatValue;
        };

        self.value.float = val;
        self.parsed = true;
    }

    fn parseFile(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByFilePath;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const file = try std.fs.cwd().openFile(args[0], self.opts.file_options);
        self.value.file = file;
        self.parsed = true;
    }

    fn parseStringList(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByString;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        try self.value.string_list.append(self.allocator, args[0]);
        self.parsed = true;
    }

    fn parseIntList(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByInteger;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const val = std.fmt.parseInt(i64, args[0], 10) catch {
            return error.BadIntegerValue;
        };

        try self.value.int_list.append(self.allocator, val);
        self.parsed = true;
    }

    fn parseFloatList(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByFloat;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const val = std.fmt.parseFloat(f64, args[0]) catch {
            return error.BadFloatValue;
        };

        try self.value.float_list.append(self.allocator, val);
        self.parsed = true;
    }

    fn parseFileList(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByFilePath;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        const file = std.fs.cwd().openFile(args[0], self.opts.file_options) catch |err| {
            for (self.value.file_list.items) |*f| {
                f.close();
            }
            self.value.file_list.clearRetainingCapacity();
            return err;
        };

        try self.value.file_list.append(self.allocator, file);
        self.parsed = true;
    }

    fn parseSelector(self: *Argument, args: []const []const u8) !void {
        if (args.len < 1) {
            return error.MustBeFollowedByString;
        }
        if (args.len > 1) {
            return error.TooManyArguments;
        }

        if (self.selector_options) |options| {
            var match = false;
            for (options) |opt| {
                if (std.mem.eql(u8, args[0], opt)) {
                    match = true;
                    break;
                }
            }

            if (!match) {
                return error.InvalidSelectorValue;
            }
        }

        self.value.selector = args[0];
        self.parsed = true;
    }

    pub fn parsePositional(self: *Argument, arg: []const u8) !void {
        var args = [_][]const u8{arg};
        try self.parseValue(&args, 1);
    }

    pub fn setDefault(self: *Argument) !void {
        if (self.parsed) {
            return;
        }

        switch (self.value) {
            .flag => {
                if (self.opts.default_bool) |default| {
                    self.value.flag = default;
                }
            },
            .flag_counter, .int => {
                if (self.opts.default_int) |default| {
                    switch (self.value) {
                        .flag_counter => self.value.flag_counter = default,
                        .int => self.value.int = default,
                        else => unreachable,
                    }
                }
            },
            .float => {
                if (self.opts.default_float) |default| {
                    self.value.float = default;
                }
            },
            .string, .selector => {
                if (self.opts.default_string) |default| {
                    switch (self.value) {
                        .string => self.value.string = default,
                        .selector => self.value.selector = default,
                        else => unreachable,
                    }
                }
            },
            .file => {
                if (self.opts.default_string) |default| {
                    const file = try std.fs.cwd().openFile(default, self.opts.file_options);
                    self.value.file = file;
                }
            },
            .string_list => {
                if (self.opts.default_string_list) |default| {
                    try self.value.string_list.appendSlice(self.allocator, default);
                }
            },
            .int_list => {
                if (self.opts.default_int_list) |default| {
                    try self.value.int_list.appendSlice(self.allocator, default);
                }
            },
            .float_list => {
                if (self.opts.default_float_list) |default| {
                    try self.value.float_list.appendSlice(self.allocator, default);
                }
            },
            .file_list => {
                if (self.opts.default_string_list) |default| {
                    for (default) |path| {
                        const file = std.fs.cwd().openFile(path, self.opts.file_options) catch |err| {
                            for (self.value.file_list.items) |*f| {
                                f.close();
                            }
                            self.value.file_list.clearRetainingCapacity();
                            return err;
                        };
                        try self.value.file_list.append(self.allocator, file);
                    }
                }
            },
            else => {},
        }
    }

    pub fn getName(self: Argument) []const u8 {
        if (self.opts.positional) {
            return self.lname;
        }

        if (self.lname.len == 0) {
            return self.sname;
        } else if (self.sname.len == 0) {
            return self.lname;
        } else {
            return self.lname;
        }
    }

    /// Generates usage string for help documentation.
    ///
    /// Format varies by argument type:
    /// - Flags: [-v|--verbose]
    /// - Valued args: [-n|--name "value"]
    /// - Lists: [-f|--file "value" [-f|--file "value" ...]]
    /// - Selectors: [-c|--color (red|green|blue)]
    ///
    /// Optional arguments are wrapped in square brackets.
    pub fn getUsage(self: Argument, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8){};
        const writer = result.writer(allocator);

        if (self.sname.len > 0) {
            try writer.print("-{s}", .{self.sname});
            if (self.lname.len > 0) {
                try writer.writeAll("|");
            }
        }

        if (self.lname.len > 0) {
            try writer.print("--{s}", .{self.lname});
        }

        switch (self.arg_type) {
            .flag, .help => {},
            .flag_counter => {
                if (self.unique or self.size > 1) {
                    try writer.writeAll(" <integer>");
                }
            },
            .int => try writer.writeAll(" <integer>"),
            .float => try writer.writeAll(" <float>"),
            .string => try writer.writeAll(" \"<value>\""),
            .file => try writer.writeAll(" <file>"),
            .selector => {
                if (self.selector_options) |options| {
                    try writer.writeAll(" (");
                    for (options, 0..) |opt, i| {
                        if (i > 0) try writer.writeAll("|");
                        try writer.writeAll(opt);
                    }
                    try writer.writeAll(")");
                }
            },
            .string_list => {
                const base_usage = try self.getUsageBase(allocator);
                defer allocator.free(base_usage);
                try writer.print(" \"<value>\" [{s} \"<value>\" ...]", .{base_usage});
            },
            .int_list => {
                const base_usage = try self.getUsageBase(allocator);
                defer allocator.free(base_usage);
                try writer.print(" <integer> [{s} <integer> ...]", .{base_usage});
            },
            .float_list => {
                const base_usage = try self.getUsageBase(allocator);
                defer allocator.free(base_usage);
                try writer.print(" <float> [{s} <float> ...]", .{base_usage});
            },
            .file_list => {
                const base_usage = try self.getUsageBase(allocator);
                defer allocator.free(base_usage);
                try writer.print(" <file> [{s} <file> ...]", .{base_usage});
            },
        }

        const usage_str = try result.toOwnedSlice(allocator);

        if (!self.opts.required) {
            const wrapped = try std.fmt.allocPrint(allocator, "[{s}]", .{usage_str});
            allocator.free(usage_str);
            return wrapped;
        }

        return usage_str;
    }

    fn getUsageBase(self: Argument, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8){};
        const writer = result.writer(allocator);

        if (self.sname.len > 0) {
            try writer.print("-{s}", .{self.sname});
            if (self.lname.len > 0) {
                try writer.writeAll("|");
            }
        }

        if (self.lname.len > 0) {
            try writer.print("--{s}", .{self.lname});
        }

        return result.toOwnedSlice(allocator);
    }
};
