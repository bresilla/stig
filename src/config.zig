const std = @import("std");

/// Stinger configuration loaded from stinger.toml
pub const Config = struct {
    /// Project title for documentation
    title: []const u8 = "API Reference",
    /// Output directory
    output_dir: []const u8 = "docs",
    /// Output format: "markdown" or "mdbook"
    format: Format = .mdbook,
    /// Input file patterns (glob patterns)
    input_patterns: []const []const u8 = &[_][]const u8{},
    /// Language for mdbook
    language: []const u8 = "en",
    /// Whether to generate introduction page
    generate_intro: bool = true,
    /// Grouping strategy
    grouping: Grouping = .by_header,
    /// Authors list
    authors: []const []const u8 = &[_][]const u8{},

    pub const Format = enum {
        markdown,
        mdbook,
    };

    pub const Grouping = enum {
        by_header,
        by_prefix,
        flat,
    };
};

/// Simple TOML parser for stinger configuration
/// Supports basic key-value pairs and sections
pub const TomlParser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize = 0,
    line: usize = 1,

    // Parsed values storage
    strings: std.ArrayList([]u8) = .empty,
    string_arrays: std.ArrayList([][]const u8) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Self {
        return Self{
            .allocator = allocator,
            .content = content,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.strings.items) |s| {
            self.allocator.free(s);
        }
        self.strings.deinit(self.allocator);

        for (self.string_arrays.items) |arr| {
            for (arr) |s| {
                self.allocator.free(@constCast(s));
            }
            self.allocator.free(arr);
        }
        self.string_arrays.deinit(self.allocator);
    }

    /// Parses the TOML content and returns a Config
    pub fn parse(self: *Self) !Config {
        var config = Config{};
        var current_section: ?[]const u8 = null;

        while (self.pos < self.content.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.content.len) break;

            const c = self.content[self.pos];

            if (c == '[') {
                // Section header
                current_section = try self.parseSection();
            } else if (c == '\n') {
                self.pos += 1;
                self.line += 1;
            } else if (std.ascii.isAlphabetic(c) or c == '_') {
                // Key-value pair
                const key = self.parseKey();
                self.skipWhitespace();

                if (self.pos >= self.content.len or self.content[self.pos] != '=') {
                    return error.ExpectedEquals;
                }
                self.pos += 1; // skip '='
                self.skipWhitespace();

                // Apply value to config based on section and key
                try self.applyValue(&config, current_section, key);
            } else {
                self.pos += 1;
            }
        }

        return config;
    }

    fn parseSection(self: *Self) ![]const u8 {
        self.pos += 1; // skip '['
        const start = self.pos;

        while (self.pos < self.content.len and self.content[self.pos] != ']' and self.content[self.pos] != '\n') {
            self.pos += 1;
        }

        if (self.pos >= self.content.len or self.content[self.pos] != ']') {
            return error.UnclosedSection;
        }

        const section = self.content[start..self.pos];
        self.pos += 1; // skip ']'
        return section;
    }

    fn parseKey(self: *Self) []const u8 {
        const start = self.pos;
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
                self.pos += 1;
            } else {
                break;
            }
        }
        return self.content[start..self.pos];
    }

    fn parseStringValue(self: *Self) ![]const u8 {
        if (self.pos >= self.content.len) return error.UnexpectedEof;

        const quote = self.content[self.pos];
        if (quote != '"' and quote != '\'') {
            // Bare value (until newline or comment)
            const start = self.pos;
            while (self.pos < self.content.len and self.content[self.pos] != '\n' and self.content[self.pos] != '#') {
                self.pos += 1;
            }
            return std.mem.trim(u8, self.content[start..self.pos], " \t");
        }

        self.pos += 1; // skip opening quote
        const start = self.pos;

        while (self.pos < self.content.len and self.content[self.pos] != quote) {
            if (self.content[self.pos] == '\\' and self.pos + 1 < self.content.len) {
                self.pos += 2; // skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        if (self.pos >= self.content.len) return error.UnclosedString;

        const value = self.content[start..self.pos];
        self.pos += 1; // skip closing quote

        // Store a copy
        const copy = try self.allocator.dupe(u8, value);
        try self.strings.append(self.allocator, copy);
        return copy;
    }

    fn parseArrayValue(self: *Self) ![]const []const u8 {
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.ExpectedArray;
        }
        self.pos += 1; // skip '['

        var items: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (items.items) |item| {
                self.allocator.free(@constCast(item));
            }
            items.deinit(self.allocator);
        }

        while (self.pos < self.content.len) {
            self.skipWhitespaceAndNewlines();
            if (self.pos >= self.content.len) break;

            if (self.content[self.pos] == ']') {
                self.pos += 1;
                break;
            }

            if (self.content[self.pos] == ',') {
                self.pos += 1;
                continue;
            }

            const value = try self.parseStringValue();
            try items.append(self.allocator, value);
        }

        const result = try items.toOwnedSlice(self.allocator);
        try self.string_arrays.append(self.allocator, result);
        return result;
    }

    fn parseBoolValue(self: *Self) !bool {
        const start = self.pos;
        while (self.pos < self.content.len and std.ascii.isAlphabetic(self.content[self.pos])) {
            self.pos += 1;
        }
        const value = self.content[start..self.pos];

        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return error.InvalidBool;
    }

    fn applyValue(self: *Self, config: *Config, section: ?[]const u8, key: []const u8) !void {
        if (section == null or std.mem.eql(u8, section.?, "stinger")) {
            // Root or [stinger] section
            if (std.mem.eql(u8, key, "title")) {
                config.title = try self.parseStringValue();
            } else if (std.mem.eql(u8, key, "output") or std.mem.eql(u8, key, "output_dir")) {
                config.output_dir = try self.parseStringValue();
            } else if (std.mem.eql(u8, key, "format")) {
                const fmt = try self.parseStringValue();
                if (std.mem.eql(u8, fmt, "markdown") or std.mem.eql(u8, fmt, "md")) {
                    config.format = .markdown;
                } else if (std.mem.eql(u8, fmt, "mdbook")) {
                    config.format = .mdbook;
                }
            } else if (std.mem.eql(u8, key, "input") or std.mem.eql(u8, key, "inputs")) {
                config.input_patterns = try self.parseArrayValue();
            } else if (std.mem.eql(u8, key, "language") or std.mem.eql(u8, key, "lang")) {
                config.language = try self.parseStringValue();
            } else if (std.mem.eql(u8, key, "generate_intro")) {
                config.generate_intro = try self.parseBoolValue();
            } else if (std.mem.eql(u8, key, "grouping")) {
                const grp = try self.parseStringValue();
                if (std.mem.eql(u8, grp, "by_header") or std.mem.eql(u8, grp, "header")) {
                    config.grouping = .by_header;
                } else if (std.mem.eql(u8, grp, "by_prefix") or std.mem.eql(u8, grp, "prefix")) {
                    config.grouping = .by_prefix;
                } else if (std.mem.eql(u8, grp, "flat")) {
                    config.grouping = .flat;
                }
            } else if (std.mem.eql(u8, key, "authors")) {
                config.authors = try self.parseArrayValue();
            } else {
                // Skip unknown key
                self.skipToEndOfLine();
            }
        } else if (std.mem.eql(u8, section.?, "book")) {
            // [book] section (mdbook compatibility)
            if (std.mem.eql(u8, key, "title")) {
                config.title = try self.parseStringValue();
            } else if (std.mem.eql(u8, key, "authors")) {
                config.authors = try self.parseArrayValue();
            } else if (std.mem.eql(u8, key, "language")) {
                config.language = try self.parseStringValue();
            } else {
                self.skipToEndOfLine();
            }
        } else if (std.mem.eql(u8, section.?, "output")) {
            // [output] section
            if (std.mem.eql(u8, key, "dir") or std.mem.eql(u8, key, "path")) {
                config.output_dir = try self.parseStringValue();
            } else if (std.mem.eql(u8, key, "format")) {
                const fmt = try self.parseStringValue();
                if (std.mem.eql(u8, fmt, "markdown") or std.mem.eql(u8, fmt, "md")) {
                    config.format = .markdown;
                } else if (std.mem.eql(u8, fmt, "mdbook")) {
                    config.format = .mdbook;
                }
            } else {
                self.skipToEndOfLine();
            }
        } else {
            // Unknown section, skip
            self.skipToEndOfLine();
        }
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndNewlines(self: *Self) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                if (c == '\n') self.line += 1;
                self.pos += 1;
            } else if (c == '#') {
                self.skipToEndOfLine();
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndComments(self: *Self) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
            } else if (c == '#') {
                self.skipToEndOfLine();
            } else {
                break;
            }
        }
    }

    fn skipToEndOfLine(self: *Self) void {
        while (self.pos < self.content.len and self.content[self.pos] != '\n') {
            self.pos += 1;
        }
    }
};

/// Loads configuration from a file path
pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !struct { config: Config, parser: *TomlParser } {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Return default config if file doesn't exist
            const parser = try allocator.create(TomlParser);
            parser.* = TomlParser.init(allocator, "");
            return .{ .config = Config{}, .parser = parser };
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max

    const parser = try allocator.create(TomlParser);
    parser.* = TomlParser.init(allocator, content);

    const config = try parser.parse();
    return .{ .config = config, .parser = parser };
}

/// Finds and loads stinger.toml from current directory or parents
pub fn findAndLoad(allocator: std.mem.Allocator) !struct { config: Config, parser: *TomlParser } {
    // Try current directory first
    if (loadFromFile(allocator, "stinger.toml")) |result| {
        return result;
    } else |_| {}

    // Return default config
    const parser = try allocator.create(TomlParser);
    parser.* = TomlParser.init(allocator, "");
    return .{ .config = Config{}, .parser = parser };
}

// Tests
test "parse empty config" {
    var parser = TomlParser.init(std.testing.allocator, "");
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqualStrings("API Reference", config.title);
    try std.testing.expectEqualStrings("docs", config.output_dir);
}

test "parse basic config" {
    const content =
        \\title = "My Library"
        \\output = "api-docs"
        \\format = "mdbook"
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqualStrings("My Library", config.title);
    try std.testing.expectEqualStrings("api-docs", config.output_dir);
    try std.testing.expectEqual(Config.Format.mdbook, config.format);
}

test "parse config with sections" {
    const content =
        \\[stinger]
        \\title = "Test API"
        \\
        \\[output]
        \\dir = "build/docs"
        \\format = "markdown"
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqualStrings("Test API", config.title);
    try std.testing.expectEqualStrings("build/docs", config.output_dir);
    try std.testing.expectEqual(Config.Format.markdown, config.format);
}

test "parse config with comments" {
    const content =
        \\# This is a comment
        \\title = "My API"  # inline comment
        \\# Another comment
        \\output = "docs"
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqualStrings("My API", config.title);
    try std.testing.expectEqualStrings("docs", config.output_dir);
}

test "parse config with array" {
    const content =
        \\inputs = ["src/*.h", "include/**/*.h"]
        \\authors = ["Alice", "Bob"]
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqual(@as(usize, 2), config.input_patterns.len);
    try std.testing.expectEqualStrings("src/*.h", config.input_patterns[0]);
    try std.testing.expectEqualStrings("include/**/*.h", config.input_patterns[1]);
    try std.testing.expectEqual(@as(usize, 2), config.authors.len);
}

test "parse config with boolean" {
    const content =
        \\generate_intro = false
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqual(false, config.generate_intro);
}

test "parse mdbook compatible config" {
    const content =
        \\[book]
        \\title = "My Book"
        \\authors = ["Author One"]
        \\language = "en"
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqualStrings("My Book", config.title);
    try std.testing.expectEqualStrings("en", config.language);
    try std.testing.expectEqual(@as(usize, 1), config.authors.len);
}

test "parse grouping option" {
    const content =
        \\grouping = "flat"
    ;

    var parser = TomlParser.init(std.testing.allocator, content);
    defer parser.deinit();

    const config = try parser.parse();
    try std.testing.expectEqual(Config.Grouping.flat, config.grouping);
}
