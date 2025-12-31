const std = @import("std");
const toml = @import("toml");

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

/// TOML structure that maps to stinger.toml file format
/// Supports multiple section styles for flexibility
const TomlConfig = struct {
    // Root level fields
    title: ?[]const u8 = null,
    output: ?[]const u8 = null,
    output_dir: ?[]const u8 = null,
    format: ?[]const u8 = null,
    inputs: ?[]const []const u8 = null,
    input: ?[]const []const u8 = null,
    language: ?[]const u8 = null,
    lang: ?[]const u8 = null,
    generate_intro: ?bool = null,
    grouping: ?[]const u8 = null,
    authors: ?[]const []const u8 = null,

    // [stinger] section
    stinger: ?StingerSection = null,

    // [book] section (mdbook compatibility)
    book: ?BookSection = null,

    // Note: [output] section conflicts with 'output' field name
    // We'll handle output_dir and format from root level only

    const StingerSection = struct {
        title: ?[]const u8 = null,
        output: ?[]const u8 = null,
        output_dir: ?[]const u8 = null,
        format: ?[]const u8 = null,
        inputs: ?[]const []const u8 = null,
        input: ?[]const []const u8 = null,
        language: ?[]const u8 = null,
        lang: ?[]const u8 = null,
        generate_intro: ?bool = null,
        grouping: ?[]const u8 = null,
        authors: ?[]const []const u8 = null,
    };

    const BookSection = struct {
        title: ?[]const u8 = null,
        authors: ?[]const []const u8 = null,
        language: ?[]const u8 = null,
    };
};

/// Configuration loader using zig-toml
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,
    parsed: ?toml.Parsed(TomlConfig) = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.parsed) |parsed| {
            parsed.deinit();
        }
    }

    /// Loads configuration from a TOML file
    pub fn loadFile(self: *Self, path: []const u8) !Config {
        // Read file content
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return Config{};
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        return self.loadString(content);
    }

    /// Loads configuration from a TOML string
    pub fn loadString(self: *Self, content: []const u8) !Config {
        var parser = toml.Parser(TomlConfig).init(self.allocator);
        defer parser.deinit();

        self.parsed = parser.parseString(content) catch {
            // On parse error, return default config
            return Config{};
        };

        return self.buildConfig(self.parsed.?.value);
    }

    /// Converts TomlConfig to Config, applying precedence rules
    fn buildConfig(_: *Self, tc: TomlConfig) Config {
        var config = Config{};

        // Title: root > stinger > book
        if (tc.title) |t| {
            config.title = t;
        } else if (tc.stinger) |s| {
            if (s.title) |t| config.title = t;
        } else if (tc.book) |b| {
            if (b.title) |t| config.title = t;
        }

        // Output directory: root > stinger
        if (tc.output) |o| {
            config.output_dir = o;
        } else if (tc.output_dir) |o| {
            config.output_dir = o;
        } else if (tc.stinger) |s| {
            if (s.output) |o| {
                config.output_dir = o;
            } else if (s.output_dir) |o| {
                config.output_dir = o;
            }
        }

        // Format: root > stinger
        const format_str = blk: {
            if (tc.format) |f| break :blk f;
            if (tc.stinger) |s| {
                if (s.format) |f| break :blk f;
            }
            break :blk null;
        };
        if (format_str) |fmt| {
            if (std.mem.eql(u8, fmt, "markdown") or std.mem.eql(u8, fmt, "md")) {
                config.format = .markdown;
            } else if (std.mem.eql(u8, fmt, "mdbook")) {
                config.format = .mdbook;
            }
        }

        // Input patterns: root > stinger
        if (tc.inputs) |i| {
            config.input_patterns = i;
        } else if (tc.input) |i| {
            config.input_patterns = i;
        } else if (tc.stinger) |s| {
            if (s.inputs) |i| {
                config.input_patterns = i;
            } else if (s.input) |i| {
                config.input_patterns = i;
            }
        }

        // Language: root > stinger > book
        if (tc.language) |l| {
            config.language = l;
        } else if (tc.lang) |l| {
            config.language = l;
        } else if (tc.stinger) |s| {
            if (s.language) |l| {
                config.language = l;
            } else if (s.lang) |l| {
                config.language = l;
            }
        } else if (tc.book) |b| {
            if (b.language) |l| config.language = l;
        }

        // Generate intro: root > stinger
        if (tc.generate_intro) |g| {
            config.generate_intro = g;
        } else if (tc.stinger) |s| {
            if (s.generate_intro) |g| config.generate_intro = g;
        }

        // Grouping: root > stinger
        const grouping_str = blk: {
            if (tc.grouping) |g| break :blk g;
            if (tc.stinger) |s| {
                if (s.grouping) |g| break :blk g;
            }
            break :blk null;
        };
        if (grouping_str) |grp| {
            if (std.mem.eql(u8, grp, "by_header") or std.mem.eql(u8, grp, "header")) {
                config.grouping = .by_header;
            } else if (std.mem.eql(u8, grp, "by_prefix") or std.mem.eql(u8, grp, "prefix")) {
                config.grouping = .by_prefix;
            } else if (std.mem.eql(u8, grp, "flat")) {
                config.grouping = .flat;
            }
        }

        // Authors: root > stinger > book
        if (tc.authors) |a| {
            config.authors = a;
        } else if (tc.stinger) |s| {
            if (s.authors) |a| config.authors = a;
        } else if (tc.book) |b| {
            if (b.authors) |a| config.authors = a;
        }

        return config;
    }
};

/// Loads configuration from a file path
pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !struct { config: Config, loader: *ConfigLoader } {
    const loader = try allocator.create(ConfigLoader);
    loader.* = ConfigLoader.init(allocator);

    const config = loader.loadFile(path) catch |err| {
        loader.deinit();
        allocator.destroy(loader);
        return err;
    };

    return .{ .config = config, .loader = loader };
}

/// Finds and loads stinger.toml from current directory
pub fn findAndLoad(allocator: std.mem.Allocator) !struct { config: Config, loader: *ConfigLoader } {
    return loadFromFile(allocator, "stinger.toml");
}

// Tests
test "default config values" {
    const config = Config{};
    try std.testing.expectEqualStrings("API Reference", config.title);
    try std.testing.expectEqualStrings("docs", config.output_dir);
    try std.testing.expectEqual(Config.Format.mdbook, config.format);
}

test "parse basic config" {
    const content =
        \\title = "My Library"
        \\output = "api-docs"
        \\format = "mdbook"
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqualStrings("My Library", config.title);
    try std.testing.expectEqualStrings("api-docs", config.output_dir);
    try std.testing.expectEqual(Config.Format.mdbook, config.format);
}

test "parse config with stinger section" {
    const content =
        \\[stinger]
        \\title = "Test API"
        \\output = "build/docs"
        \\format = "markdown"
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqualStrings("Test API", config.title);
    try std.testing.expectEqualStrings("build/docs", config.output_dir);
    try std.testing.expectEqual(Config.Format.markdown, config.format);
}

test "parse config with book section" {
    const content =
        \\[book]
        \\title = "My Book"
        \\authors = ["Author One"]
        \\language = "en"
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqualStrings("My Book", config.title);
    try std.testing.expectEqualStrings("en", config.language);
    try std.testing.expectEqual(@as(usize, 1), config.authors.len);
}

test "parse config with arrays" {
    const content =
        \\inputs = ["src/*.h", "include/**/*.h"]
        \\authors = ["Alice", "Bob"]
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqual(@as(usize, 2), config.input_patterns.len);
    try std.testing.expectEqualStrings("src/*.h", config.input_patterns[0]);
    try std.testing.expectEqualStrings("include/**/*.h", config.input_patterns[1]);
    try std.testing.expectEqual(@as(usize, 2), config.authors.len);
}

test "parse config with boolean" {
    const content =
        \\generate_intro = false
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqual(false, config.generate_intro);
}

test "parse grouping option" {
    const content =
        \\grouping = "flat"
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqual(Config.Grouping.flat, config.grouping);
}

test "empty config returns defaults" {
    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString("");
    try std.testing.expectEqualStrings("API Reference", config.title);
    try std.testing.expectEqualStrings("docs", config.output_dir);
}
