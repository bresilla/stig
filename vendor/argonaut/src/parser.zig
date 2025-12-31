const std = @import("std");
const Command = @import("command.zig").Command;
const Argument = @import("argument.zig").Argument;
const Options = @import("options.zig").Options;
const ArgumentType = @import("argument.zig").ArgumentType;

pub const Parser = struct {
    command: Command,
    allocator: std.mem.Allocator,
    
    /// Creates a new parser with the given program name and description.
    ///
    /// Automatically adds a default help argument (-h, --help).
    /// The returned parser must be freed with deinit().
    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !*Parser {
        const parser = try allocator.create(Parser);
        parser.* = .{
            .command = try Command.init(allocator, name, description, null),
            .allocator = allocator,
        };

        try parser.command.addHelpArg("h", "help");

        return parser;
    }
    
    /// Frees all memory associated with the parser.
    ///
    /// You must call this function when you're done using the parser to prevent
    /// memory leaks. This will clean up all commands, arguments, and allocated
    /// resources.
    pub fn deinit(self: *Parser) void {
        self.command.deinit();
        self.allocator.destroy(self);
    }
    
    /// Parses the provided argument array.
    ///
    /// This is the main entry point after defining all arguments.
    /// Performs parsing in three phases:
    /// 1. Named arguments (flags and options)
    /// 2. Subcommands
    /// 3. Positional arguments
    ///
    /// Returns error if any required arguments are missing,
    /// unknown arguments are present, or validation fails.
    ///
    /// Example:
    ///   const args = try std.process.argsAlloc(allocator);
    ///   defer std.process.argsFree(allocator, args);
    ///   try parser.parse(args);
    pub fn parse(self: *Parser, args: []const []const u8) !void {
        var mutable_args = std.ArrayList([]const u8){};
        defer mutable_args.deinit(self.allocator);

        try mutable_args.appendSlice(self.allocator, args);

        try self.command.parse(&mutable_args);

        try self.command.parsePositionals(&mutable_args);

        const unparsed = try self.getUnparsed(&mutable_args);
        defer self.allocator.free(unparsed);

        if (unparsed.len > 0) {
            return error.UnknownArguments;
        }
    }

    fn getUnparsed(self: *Parser, args: *std.ArrayList([]const u8)) ![]const []const u8 {
        var unparsed = std.ArrayList([]const u8){};

        for (args.items) |arg| {
            if (arg.len > 0) {
                try unparsed.append(self.allocator, arg);
            }
        }

        return unparsed.toOwnedSlice(self.allocator);
    }
    
    /// Creates a new subcommand for your parser.
    ///
    /// You can use subcommands to create CLI tools with multiple actions,
    /// like `git commit` or `docker run`. Each subcommand can have its own
    /// arguments and options.
    ///
    /// **Parameters:**
    /// - `name`: The name of the subcommand (e.g., "commit", "run")
    /// - `description`: A brief description of what the subcommand does
    ///
    /// **Returns:** A pointer to the Command that you can add arguments to
    pub fn newCommand(self: *Parser, name: []const u8, description: []const u8) !*Command {
        return try self.command.newCommand(name, description);
    }
    
    /// Adds a boolean flag argument to your parser.
    ///
    /// Flags are boolean switches that don't take values. If you pass the flag,
    /// it's `true`; otherwise, it's `false`. You can use flags for options like
    /// `--verbose` or `--force`.
    ///
    /// **Parameters:**
    /// - `short`: Short flag name (e.g., "v" for `-v`), use empty string if you don't want one
    /// - `long`: Long flag name (e.g., "verbose" for `--verbose`)
    /// - `opts`: Optional configuration (description, required status, etc.)
    ///
    /// **Returns:** A pointer to a boolean that will be set when you call `parse()`
    ///
    /// **Example:**
    /// ```zig
    /// const verbose = try parser.flag("v", "verbose", null);
    /// try parser.parse(args);
    /// if (verbose.*) {
    ///     std.debug.print("Verbose mode enabled\n", .{});
    /// }
    /// ```
    pub fn flag(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*bool {
        return try self.command.flag(short, long, opts);
    }
    
    /// Adds a counter flag argument to your parser.
    ///
    /// Counter flags count how many times they appear. You can use this for
    /// verbosity levels where `-v` = 1, `-vv` = 2, `-vvv` = 3, etc.
    ///
    /// **Parameters:**
    /// - `short`: Short flag name (e.g., "v")
    /// - `long`: Long flag name (e.g., "verbose")
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an integer that counts flag occurrences
    ///
    /// **Example:**
    /// ```zig
    /// const verbosity = try parser.flagCounter("v", "verbose", null);
    /// try parser.parse(args); // User passes -vvv
    /// std.debug.print("Verbosity level: {}\n", .{verbosity.*}); // Prints 3
    /// ```
    pub fn flagCounter(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*i64 {
        return try self.command.flagCounter(short, long, opts);
    }
    
    /// Adds a string option argument to your parser.
    ///
    /// String options accept text values. You can use them for arguments like
    /// `--file=input.txt` or `-o output.txt`.
    ///
    /// **Parameters:**
    /// - `short`: Short option name (e.g., "f")
    /// - `long`: Long option name (e.g., "file")
    /// - `opts`: Optional configuration (default value, description, etc.)
    ///
    /// **Returns:** A pointer to a string that will contain the parsed value
    pub fn string(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*[]const u8 {
        return try self.command.string(short, long, opts);
    }
    
    /// Adds a positional string argument to your parser.
    ///
    /// Positional arguments don't have flags and are identified by their position.
    /// You can use them for required inputs like `git clone <repository>`.
    ///
    /// **Parameters:**
    /// - `opts`: Optional configuration (description, required status, etc.)
    ///
    /// **Returns:** A pointer to a string that will contain the parsed value
    pub fn stringPositional(self: *Parser, opts: ?*Options) !*[]const u8 {
        return try self.command.stringPositional(opts);
    }
    
    /// Adds an integer option argument to your parser.
    ///
    /// Integer options accept numeric values. You can use them for arguments like
    /// `--port=8080` or `-n 100`.
    ///
    /// **Parameters:**
    /// - `short`: Short option name (e.g., "n")
    /// - `long`: Long option name (e.g., "number")
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an integer that will contain the parsed value
    pub fn int(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*i64 {
        return try self.command.int(short, long, opts);
    }
    
    /// Adds a positional integer argument to your parser.
    ///
    /// This works like `stringPositional()` but parses the value as an integer.
    ///
    /// **Parameters:**
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an integer that will contain the parsed value
    pub fn intPositional(self: *Parser, opts: ?*Options) !*i64 {
        return try self.command.intPositional(opts);
    }
    
    /// Adds a floating-point option argument to your parser.
    ///
    /// Float options accept decimal numbers. You can use them for arguments like
    /// `--threshold=0.95` or `-r 1.5`.
    ///
    /// **Parameters:**
    /// - `short`: Short option name (e.g., "r")
    /// - `long`: Long option name (e.g., "rate")
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a float that will contain the parsed value
    pub fn float(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*f64 {
        return try self.command.float(short, long, opts);
    }
    
    /// Adds a positional floating-point argument to your parser.
    ///
    /// This works like `stringPositional()` but parses the value as a float.
    ///
    /// **Parameters:**
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a float that will contain the parsed value
    pub fn floatPositional(self: *Parser, opts: ?*Options) !*f64 {
        return try self.command.floatPositional(opts);
    }
    
    /// Adds a string list option argument to your parser.
    ///
    /// List options accept multiple values. You can use them when you need to
    /// accept multiple inputs, like `--exclude=*.log --exclude=*.tmp` or
    /// `--tags=urgent,bug,frontend`.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an ArrayList containing all parsed string values
    pub fn stringList(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList([]const u8) {
        return try self.command.stringList(short, long, opts);
    }
    
    /// Adds an integer list option argument to your parser.
    ///
    /// This works like `stringList()` but parses values as integers.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an ArrayList containing all parsed integer values
    pub fn intList(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(i64) {
        return try self.command.intList(short, long, opts);
    }
    
    /// Adds a floating-point list option argument to your parser.
    ///
    /// This works like `stringList()` but parses values as floats.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an ArrayList containing all parsed float values
    pub fn floatList(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(f64) {
        return try self.command.floatList(short, long, opts);
    }
    
    /// Adds a file option argument to your parser.
    ///
    /// File options open and return file handles. You can use them when you need
    /// to read from or write to files specified by the user.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a File handle that you can read from or write to
    pub fn file(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*std.fs.File {
        return try self.command.file(short, long, opts);
    }
    
    /// Adds a positional file argument to your parser.
    ///
    /// This works like `stringPositional()` but opens the file and returns a handle.
    ///
    /// **Parameters:**
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a File handle
    ///
    /// **Example:**
    /// ```zig
    /// const input = try parser.filePositional(null);
    /// try parser.parse(args); // User passes: myapp input.txt
    /// ```
    pub fn filePositional(self: *Parser, opts: ?*Options) !*std.fs.File {
        return try self.command.filePositional(opts);
    }
    
    /// Adds a file list option argument to your parser.
    ///
    /// This accepts multiple file paths and returns handles for all of them.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to an ArrayList containing all opened File handles
    pub fn fileList(self: *Parser, short: []const u8, long: []const u8, opts: ?*Options) !*std.ArrayList(std.fs.File) {
        return try self.command.fileList(short, long, opts);
    }
    
    /// Adds a selector (choice) option argument to your parser.
    ///
    /// Selectors restrict input to a predefined set of allowed values. You can use
    /// them when you want users to choose from specific options, like
    /// `--format=json` or `--format=xml`.
    ///
    /// **Parameters:**
    /// - `short`: Short option name
    /// - `long`: Long option name
    /// - `allowed`: Array of valid string values the user can choose from
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a string containing the selected value
    pub fn selector(self: *Parser, short: []const u8, long: []const u8, allowed: []const []const u8, opts: ?*Options) !*[]const u8 {
        return try self.command.selector(short, long, allowed, opts);
    }
    
    /// Adds a positional selector (choice) argument to your parser.
    ///
    /// This works like `selector()` but for positional arguments.
    ///
    /// **Parameters:**
    /// - `allowed`: Array of valid string values the user can choose from
    /// - `opts`: Optional configuration
    ///
    /// **Returns:** A pointer to a string containing the selected value
    pub fn selectorPositional(self: *Parser, allowed: []const []const u8, opts: ?*Options) !*[]const u8 {
        return try self.command.selectorPositional(allowed, opts);
    }
    
    /// Disables the automatic help argument.
    ///
    /// By default, the parser adds `-h` and `--help` flags. If you want to disable
    /// this behavior (perhaps to use those flags for something else), call this function.
    ///
    /// **Example:**
    /// ```zig
    /// parser.disableHelp();
    /// ```
    pub fn disableHelp(self: *Parser) void {
        self.command.disableHelp();
    }
    
    /// Customizes the help argument flags.
    ///
    /// If you want to use different flags for help (instead of the default `-h`
    /// and `--help`), you can set custom ones with this function.
    ///
    /// **Parameters:**
    /// - `short`: New short flag for help (e.g., "?")
    /// - `long`: New long flag for help (e.g., "info")
    ///
    /// **Example:**
    /// ```zig
    /// try parser.setHelp("?", "info");
    /// ```
    pub fn setHelp(self: *Parser, short: []const u8, long: []const u8) !void {
        try self.command.setHelp(short, long);
    }
    
    /// Controls whether the program exits when help is requested.
    ///
    /// By default, when users pass the help flag, the parser displays usage
    /// information and exits. If you want to handle help manually, you can
    /// disable automatic exit.
    ///
    /// **Parameters:**
    /// - `value`: `true` to exit on help (default), `false` to continue execution
    ///
    /// **Example:**
    /// ```zig
    /// parser.exitOnHelp(false); // Don't exit, let me handle help
    /// ```    
    pub fn exitOnHelp(self: *Parser, value: bool) void {
        self.command.exitOnHelp(value);
    }
    
    /// Generates a usage/help message for your program.
    ///
    /// You can use this to display help information to users. It includes your
    /// program's description, available commands, arguments, and options.
    ///
    /// **Parameters:**
    /// - `msg`: Optional custom message to include at the top of the help text
    ///
    /// **Returns:** A formatted usage string that you should free after use
    ///
    /// **Example:**
    /// ```zig
    /// const help_text = try parser.usage("Welcome to MyApp!");
    /// defer allocator.free(help_text);
    /// std.debug.print("{s}\n", .{help_text});
    /// ```
    pub fn usage(self: *Parser, msg: ?[]const u8) ![]const u8 {
        return try self.command.usage(msg);
    }
    
    /// Gets your program's name.
    ///
    /// **Returns:** The name you provided when creating the parser
    pub fn getName(self: Parser) []const u8 {
        return self.command.name;
    }
    
    /// Gets your program's description.
    ///
    /// **Returns:** The description you provided when creating the parser
    pub fn getDescription(self: Parser) []const u8 {
        return self.command.description;
    }
    
    /// Gets all subcommands you've added to the parser.
    ///
    /// **Returns:** A slice of Command pointers
    ///
    /// **Example:**
    /// ```zig
    /// const commands = parser.getCommands();
    /// for (commands) |cmd| {
    ///     std.debug.print("Command: {s}\n", .{cmd.name});
    /// }
    /// ```
    pub fn getCommands(self: Parser) []const *Command {
        return self.command.commands.items;
    }
    
    /// Gets all arguments you've added to the parser.
    ///
    /// **Returns:** A slice of Argument pointers
    ///
    /// **Example:**
    /// ```zig
    /// const arguments = parser.getArgs();
    /// for (arguments) |arg| {
    ///     std.debug.print("Argument: {s}\n", .{arg.long});
    /// }
    /// ```
    pub fn getArgs(self: Parser) []const *Argument {
        return self.command.args.items;
    }
};