const std = @import("std");
const toml = @import("toml");

/// External documentation link configuration
pub const ExternalDocLink = struct {
    /// Prefix to match (e.g., "std::")
    prefix: []const u8,
    /// URL template with $$ for symbol substitution
    url_template: []const u8,
};

/// Module configuration for grouping headers into logical packages
pub const ModuleConfig = struct {
    /// Module identifier (used for directory name)
    name: []const u8,
    /// Glob patterns for matching files (e.g., "include/core/*.hpp")
    patterns: []const []const u8,
    /// Display title for the module
    title: []const u8,
    /// Optional description of the module
    description: ?[]const u8 = null,
};

/// Stig configuration loaded from stig.toml
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
    /// External documentation links
    external_docs: []const ExternalDocLink = &[_]ExternalDocLink{
        // Default: std:: links to cppreference
        .{ .prefix = "std::", .url_template = "https://en.cppreference.com/w/cpp/$$" },
    },
    /// Blacklisted namespace names (entities in these namespaces are excluded)
    blacklist_namespace: []const []const u8 = &[_][]const u8{ "detail", "internal", "impl" },
    /// Blacklisted entity name patterns (glob patterns: * and ?)
    blacklist_pattern: []const []const u8 = &[_][]const u8{},
    /// Whether to extract private members (default: false)
    extract_private: bool = false,
    /// Whether to extract protected members (default: true)
    extract_protected: bool = true,
    /// Custom section names for localization/style
    section_names: SectionNames = .{},
    /// Output customization options
    output_options: OutputOptions = .{},
    /// Coverage analysis options
    coverage: CoverageOptions = .{},
    /// Lint options
    lint: LintOptions = .{},
    /// Godbolt (Compiler Explorer) integration options
    godbolt: GodboltOptions = .{},
    /// Test coverage options
    test_coverage: TestCoverageOptions = .{},
    /// Module definitions for organizing documentation into packages
    modules: []const ModuleConfig = &[_]ModuleConfig{},
    /// Watch mode options
    watch: WatchOptions = .{},

    /// Rule severity override for per-rule configuration
    pub const RuleSeverity = enum {
        /// Ignore this rule completely
        ignore,
        /// Report as info
        info,
        /// Report as warning
        warning,
        /// Report as error
        @"error",

        pub fn fromString(s: []const u8) ?RuleSeverity {
            if (std.mem.eql(u8, s, "ignore") or std.mem.eql(u8, s, "off")) return .ignore;
            if (std.mem.eql(u8, s, "info")) return .info;
            if (std.mem.eql(u8, s, "warning") or std.mem.eql(u8, s, "warn")) return .warning;
            if (std.mem.eql(u8, s, "error")) return .@"error";
            return null;
        }
    };

    /// Per-rule configuration entry
    pub const RuleConfig = struct {
        code: []const u8,
        severity: RuleSeverity,
    };

    /// Lint options for --lint mode
    pub const LintOptions = struct {
        /// Enable linting
        enabled: bool = true,
        /// Treat warnings as errors
        treat_warnings_as_errors: bool = false,
        /// Maximum length for @brief descriptions
        max_brief_length: u32 = 80,
        /// Require @brief for all documented entities
        require_brief: bool = true,
        /// Require @param for all parameters
        require_param_docs: bool = true,
        /// Require @return for non-void functions
        require_return_docs: bool = true,
        /// Require @tparam for template parameters
        require_tparam_docs: bool = true,
        /// Check cross-references (@see, @copydoc)
        check_cross_references: bool = true,
        /// Require period at end of @brief
        require_brief_period: bool = false,
        /// Patterns to exclude from linting
        exclude_patterns: []const []const u8 = &[_][]const u8{},
        /// Per-rule severity overrides
        rules: []const RuleConfig = &[_]RuleConfig{},

        /// Get the severity override for a rule, or null if not configured
        pub fn getRuleSeverity(self: LintOptions, code: []const u8) ?RuleSeverity {
            for (self.rules) |rule| {
                if (std.mem.eql(u8, rule.code, code)) {
                    return rule.severity;
                }
            }
            return null;
        }
    };

    /// Coverage analysis options for --coverage mode (documentation coverage)
    pub const CoverageOptions = struct {
        /// Minimum coverage percentage threshold (0-100)
        min_coverage: u8 = 80,
        /// Patterns to exclude from coverage analysis (glob patterns)
        exclude_patterns: []const []const u8 = &[_][]const u8{},
        /// Require @param documentation for all parameters
        require_param_docs: bool = true,
        /// Require @return documentation for non-void functions
        require_return_docs: bool = true,
        /// Require @tparam documentation for template parameters
        require_tparam_docs: bool = true,
    };

    /// Test coverage options for `stig coverage` command
    pub const TestCoverageOptions = struct {
        /// Minimum test coverage percentage threshold (0-100)
        min_coverage: u8 = 0,
        /// Test file patterns (glob patterns)
        test_patterns: []const []const u8 = &[_][]const u8{},
        /// Patterns to exclude from test coverage analysis
        exclude_patterns: []const []const u8 = &[_][]const u8{},
    };

    /// Watch mode options
    pub const WatchOptions = struct {
        /// Debounce time in milliseconds
        debounce_ms: u32 = 100,
        /// Patterns to ignore (glob patterns)
        /// Default ignores common build artifacts and VCS directories
        ignore_patterns: []const []const u8 = &[_][]const u8{
            ".git/**",
            ".git",
            "node_modules/**",
            "build/**",
            "zig-out/**",
            "zig-cache/**",
            ".zig-cache/**",
            "*.o",
            "*.obj",
            "*.a",
            "*.so",
            "*.dylib",
        },
    };

    /// Output formatting options
    pub const OutputOptions = struct {
        /// Show source file and line number in documentation
        show_source_location: bool = true,
        /// Show access specifiers (public/private/protected)
        show_access_specifiers: bool = true,
        /// Show group section comments in output
        show_group_output_section: bool = true,
        /// Language for code blocks
        code_language: []const u8 = "cpp",
        /// Synopsis style: full, compact, or minimal
        synopsis_style: SynopsisStyle = .full,
    };

    /// Godbolt (Compiler Explorer) integration options
    pub const GodboltOptions = struct {
        /// Enable Godbolt links for code examples
        enabled: bool = false,
        /// Compiler ID (e.g., "g132" for GCC 13.2, "clang1600" for Clang 16)
        compiler: []const u8 = "g132",
        /// Compiler options (e.g., "-O2 -std=c++20")
        options: []const u8 = "-O2 -std=c++20",
        /// Link text
        link_text: []const u8 = "Run on Compiler Explorer",
    };

    /// Synopsis rendering style
    pub const SynopsisStyle = enum {
        /// Complete signature with all qualifiers
        full,
        /// Simplified signature
        compact,
        /// Just name and parameters
        minimal,
    };

    /// Customizable section names for documentation output
    pub const SectionNames = struct {
        parameters: []const u8 = "Parameters",
        returns: []const u8 = "Returns",
        throws: []const u8 = "Throws",
        effects: []const u8 = "Effects",
        requires: []const u8 = "Requires",
        see_also: []const u8 = "See Also",
        deprecated: []const u8 = "Deprecated",
        notes: []const u8 = "Notes",
        warnings: []const u8 = "Warnings",
        template_parameters: []const u8 = "Template Parameters",
        return_values: []const u8 = "Return Values",
        preconditions: []const u8 = "Preconditions",
        postconditions: []const u8 = "Postconditions",
        complexity: []const u8 = "Complexity",
        remarks: []const u8 = "Remarks",
        thread_safety: []const u8 = "Thread Safety",
        invariants: []const u8 = "Invariants",
    };

    pub const Format = enum {
        markdown,
        mdbook,
        json,
    };

    pub const Grouping = enum {
        by_header,
        by_prefix,
        flat,
        by_module,
    };
};

/// TOML structure for [[modules]] array entries
const TomlModuleEntry = struct {
    name: ?[]const u8 = null,
    patterns: ?[]const []const u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

/// TOML structure that maps to stig.toml file format
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
    // Filtering options
    blacklist_namespace: ?[]const []const u8 = null,
    blacklist_pattern: ?[]const []const u8 = null,
    extract_private: ?bool = null,
    extract_protected: ?bool = null,

    // [[modules]] array for package organization
    modules: ?[]const TomlModuleEntry = null,

    // [stig] section
    stig: ?StigSection = null,

    // [book] section (mdbook compatibility)
    book: ?BookSection = null,

    // [lint] section for lint configuration
    lint: ?LintSection = null,

    // [watch] section for watch mode configuration
    watch: ?WatchSection = null,

    // Note: [output] section conflicts with 'output' field name
    // We'll handle output_dir and format from root level only

    const StigSection = struct {
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
        // Filtering options
        blacklist_namespace: ?[]const []const u8 = null,
        blacklist_pattern: ?[]const []const u8 = null,
        extract_private: ?bool = null,
        extract_protected: ?bool = null,
    };

    const BookSection = struct {
        title: ?[]const u8 = null,
        authors: ?[]const []const u8 = null,
        language: ?[]const u8 = null,
    };

    const LintSection = struct {
        enabled: ?bool = null,
        treat_warnings_as_errors: ?bool = null,
        max_brief_length: ?i64 = null,
        require_brief: ?bool = null,
        require_param_docs: ?bool = null,
        require_return_docs: ?bool = null,
        require_tparam_docs: ?bool = null,
        check_cross_references: ?bool = null,
        require_brief_period: ?bool = null,
        exclude_patterns: ?[]const []const u8 = null,
        /// [lint.rules] section - maps rule codes to severity strings
        rules: ?toml.HashMap([]const u8) = null,
    };

    const WatchSection = struct {
        debounce_ms: ?i64 = null,
        ignore_patterns: ?[]const []const u8 = null,
    };
};

/// Configuration loader using zig-toml
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,
    parsed: ?toml.Parsed(TomlConfig) = null,
    /// Owned slice for converted module configs
    module_configs: ?[]ModuleConfig = null,
    /// Owned slice for converted rule configs
    rule_configs: ?[]Config.RuleConfig = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.module_configs) |mods| {
            self.allocator.free(mods);
        }
        if (self.rule_configs) |rules| {
            self.allocator.free(rules);
        }
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
    fn buildConfig(self: *Self, tc: TomlConfig) Config {
        var config = Config{};

        // Title: root > stinger > book
        if (tc.title) |t| {
            config.title = t;
        } else if (tc.stig) |s| {
            if (s.title) |t| config.title = t;
        } else if (tc.book) |b| {
            if (b.title) |t| config.title = t;
        }

        // Output directory: root > stinger
        if (tc.output) |o| {
            config.output_dir = o;
        } else if (tc.output_dir) |o| {
            config.output_dir = o;
        } else if (tc.stig) |s| {
            if (s.output) |o| {
                config.output_dir = o;
            } else if (s.output_dir) |o| {
                config.output_dir = o;
            }
        }

        // Format: root > stinger
        const format_str = blk: {
            if (tc.format) |f| break :blk f;
            if (tc.stig) |s| {
                if (s.format) |f| break :blk f;
            }
            break :blk null;
        };
        if (format_str) |fmt| {
            if (std.mem.eql(u8, fmt, "markdown") or std.mem.eql(u8, fmt, "md")) {
                config.format = .markdown;
            } else if (std.mem.eql(u8, fmt, "mdbook")) {
                config.format = .mdbook;
            } else if (std.mem.eql(u8, fmt, "json")) {
                config.format = .json;
            }
        }

        // Input patterns: root > stinger
        if (tc.inputs) |i| {
            config.input_patterns = i;
        } else if (tc.input) |i| {
            config.input_patterns = i;
        } else if (tc.stig) |s| {
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
        } else if (tc.stig) |s| {
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
        } else if (tc.stig) |s| {
            if (s.generate_intro) |g| config.generate_intro = g;
        }

        // Grouping: root > stinger
        const grouping_str = blk: {
            if (tc.grouping) |g| break :blk g;
            if (tc.stig) |s| {
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
            } else if (std.mem.eql(u8, grp, "by_module") or std.mem.eql(u8, grp, "module")) {
                config.grouping = .by_module;
            }
        }

        // Authors: root > stinger > book
        if (tc.authors) |a| {
            config.authors = a;
        } else if (tc.stig) |s| {
            if (s.authors) |a| config.authors = a;
        } else if (tc.book) |b| {
            if (b.authors) |a| config.authors = a;
        }

        // Blacklist namespace: root > stinger
        if (tc.blacklist_namespace) |bl| {
            config.blacklist_namespace = bl;
        } else if (tc.stig) |s| {
            if (s.blacklist_namespace) |bl| config.blacklist_namespace = bl;
        }

        // Blacklist pattern: root > stinger
        if (tc.blacklist_pattern) |bl| {
            config.blacklist_pattern = bl;
        } else if (tc.stig) |s| {
            if (s.blacklist_pattern) |bl| config.blacklist_pattern = bl;
        }

        // Extract private: root > stinger
        if (tc.extract_private) |ep| {
            config.extract_private = ep;
        } else if (tc.stig) |s| {
            if (s.extract_private) |ep| config.extract_private = ep;
        }

        // Extract protected: root > stinger
        if (tc.extract_protected) |ep| {
            config.extract_protected = ep;
        } else if (tc.stig) |s| {
            if (s.extract_protected) |ep| config.extract_protected = ep;
        }

        // Modules: convert from TomlModuleEntry to ModuleConfig
        if (tc.modules) |toml_modules| {
            if (toml_modules.len > 0) {
                // Count valid modules
                var valid_count: usize = 0;
                for (toml_modules) |entry| {
                    if (entry.name != null and entry.patterns != null and entry.title != null) {
                        valid_count += 1;
                    }
                }

                if (valid_count > 0) {
                    const mods = self.allocator.alloc(ModuleConfig, valid_count) catch {
                        return config;
                    };
                    var idx: usize = 0;
                    for (toml_modules) |entry| {
                        if (entry.name != null and entry.patterns != null and entry.title != null) {
                            mods[idx] = ModuleConfig{
                                .name = entry.name.?,
                                .patterns = entry.patterns.?,
                                .title = entry.title.?,
                                .description = entry.description,
                            };
                            idx += 1;
                        }
                    }
                    self.module_configs = mods;
                    config.modules = mods;
                }
            }
        }

        // Lint section
        if (tc.lint) |lint_section| {
            if (lint_section.enabled) |e| config.lint.enabled = e;
            if (lint_section.treat_warnings_as_errors) |t| config.lint.treat_warnings_as_errors = t;
            if (lint_section.max_brief_length) |m| config.lint.max_brief_length = @intCast(m);
            if (lint_section.require_brief) |r| config.lint.require_brief = r;
            if (lint_section.require_param_docs) |r| config.lint.require_param_docs = r;
            if (lint_section.require_return_docs) |r| config.lint.require_return_docs = r;
            if (lint_section.require_tparam_docs) |r| config.lint.require_tparam_docs = r;
            if (lint_section.check_cross_references) |c| config.lint.check_cross_references = c;
            if (lint_section.require_brief_period) |r| config.lint.require_brief_period = r;
            if (lint_section.exclude_patterns) |e| config.lint.exclude_patterns = e;

            // Parse [lint.rules] section
            if (lint_section.rules) |rules_map| {
                const count = rules_map.map.count();
                if (count > 0) {
                    const rules = self.allocator.alloc(Config.RuleConfig, count) catch {
                        return config;
                    };
                    var idx: usize = 0;
                    var it = rules_map.map.iterator();
                    while (it.next()) |entry| {
                        if (Config.RuleSeverity.fromString(entry.value_ptr.*)) |severity| {
                            rules[idx] = Config.RuleConfig{
                                .code = entry.key_ptr.*,
                                .severity = severity,
                            };
                            idx += 1;
                        }
                    }
                    // Shrink to actual size if some entries were invalid
                    if (idx < count) {
                        const shrunk = self.allocator.realloc(rules, idx) catch rules;
                        self.rule_configs = shrunk;
                        config.lint.rules = shrunk;
                    } else {
                        self.rule_configs = rules;
                        config.lint.rules = rules;
                    }
                }
            }
        }

        // Watch section
        if (tc.watch) |watch_section| {
            if (watch_section.debounce_ms) |d| config.watch.debounce_ms = @intCast(d);
            if (watch_section.ignore_patterns) |p| config.watch.ignore_patterns = p;
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

/// Finds and loads stig.toml from current directory
pub fn findAndLoad(allocator: std.mem.Allocator) !struct { config: Config, loader: *ConfigLoader } {
    return loadFromFile(allocator, "stig.toml");
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

test "parse config with stig section" {
    const content =
        \\[stig]
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

test "parse lint section with rules" {
    const content =
        \\[lint]
        \\enabled = true
        \\require_brief = false
        \\max_brief_length = 100
        \\
        \\[lint.rules]
        \\W001 = "ignore"
        \\W003 = "error"
        \\E001 = "warning"
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqual(true, config.lint.enabled);
    try std.testing.expectEqual(false, config.lint.require_brief);
    try std.testing.expectEqual(@as(u32, 100), config.lint.max_brief_length);

    // Check rules were parsed
    try std.testing.expectEqual(@as(usize, 3), config.lint.rules.len);

    // Check individual rules (order may vary due to HashMap)
    var found_w001 = false;
    var found_w003 = false;
    var found_e001 = false;
    for (config.lint.rules) |rule| {
        if (std.mem.eql(u8, rule.code, "W001")) {
            try std.testing.expectEqual(Config.RuleSeverity.ignore, rule.severity);
            found_w001 = true;
        } else if (std.mem.eql(u8, rule.code, "W003")) {
            try std.testing.expectEqual(Config.RuleSeverity.@"error", rule.severity);
            found_w003 = true;
        } else if (std.mem.eql(u8, rule.code, "E001")) {
            try std.testing.expectEqual(Config.RuleSeverity.warning, rule.severity);
            found_e001 = true;
        }
    }
    try std.testing.expect(found_w001);
    try std.testing.expect(found_w003);
    try std.testing.expect(found_e001);
}

test "RuleSeverity.fromString" {
    try std.testing.expectEqual(Config.RuleSeverity.ignore, Config.RuleSeverity.fromString("ignore"));
    try std.testing.expectEqual(Config.RuleSeverity.ignore, Config.RuleSeverity.fromString("off"));
    try std.testing.expectEqual(Config.RuleSeverity.info, Config.RuleSeverity.fromString("info"));
    try std.testing.expectEqual(Config.RuleSeverity.warning, Config.RuleSeverity.fromString("warning"));
    try std.testing.expectEqual(Config.RuleSeverity.warning, Config.RuleSeverity.fromString("warn"));
    try std.testing.expectEqual(Config.RuleSeverity.@"error", Config.RuleSeverity.fromString("error"));
    try std.testing.expectEqual(@as(?Config.RuleSeverity, null), Config.RuleSeverity.fromString("invalid"));
}

test "parse watch section" {
    const content =
        \\[watch]
        \\debounce_ms = 200
        \\ignore_patterns = [".git/**", "build/**", "*.tmp"]
    ;

    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadString(content);
    try std.testing.expectEqual(@as(u32, 200), config.watch.debounce_ms);
    try std.testing.expectEqual(@as(usize, 3), config.watch.ignore_patterns.len);
    try std.testing.expectEqualStrings(".git/**", config.watch.ignore_patterns[0]);
    try std.testing.expectEqualStrings("build/**", config.watch.ignore_patterns[1]);
    try std.testing.expectEqualStrings("*.tmp", config.watch.ignore_patterns[2]);
}

test "default watch ignore patterns" {
    const config = Config{};
    // Check that defaults include common patterns
    try std.testing.expect(config.watch.ignore_patterns.len > 0);
    // Default debounce is 100ms
    try std.testing.expectEqual(@as(u32, 100), config.watch.debounce_ms);
}
