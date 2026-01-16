const std = @import("std");
const types = @import("../model/types.zig");
const MarkdownGenerator = @import("markdown.zig").MarkdownGenerator;
const xref = @import("../xref.zig");
const snippet = @import("../snippet.zig");
const config_mod = @import("../config.zig");
const diagrams = @import("../diagrams.zig");

/// Configuration for mdbook generation
pub const MdbookConfig = struct {
    /// Book title
    title: []const u8 = "API Reference",
    /// Book authors
    authors: []const []const u8 = &[_][]const u8{},
    /// Output directory
    output_dir: []const u8 = "docs",
    /// Language for syntax highlighting
    language: []const u8 = "en",
    /// Whether to generate introduction page
    generate_intro: bool = true,
    /// Grouping strategy
    grouping: GroupingStrategy = .by_header,
    /// Module configurations for by_module grouping
    module_configs: []const config_mod.ModuleConfig = &[_]config_mod.ModuleConfig{},
    /// External documentation links (e.g., std:: -> cppreference)
    external_docs: []const config_mod.ExternalDocLink = &[_]config_mod.ExternalDocLink{},

    pub const GroupingStrategy = enum {
        /// Group by source header file
        by_header,
        /// Group by function/type prefix
        by_prefix,
        /// All in one file
        flat,
        /// Group by configured modules/packages
        by_module,
    };
};

/// Generates mdbook-compatible documentation structure
pub const MdbookGenerator = struct {
    allocator: std.mem.Allocator,
    config: MdbookConfig,
    markdown_gen: MarkdownGenerator,
    /// Symbol table for cross-reference resolution
    symbol_table: xref.SymbolTable,
    /// Snippet extractor for @snippet tags
    snippet_extractor: snippet.SnippetExtractor,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = .{},
            .markdown_gen = MarkdownGenerator.init(allocator),
            .symbol_table = xref.SymbolTable.init(allocator),
            .snippet_extractor = snippet.SnippetExtractor.init(allocator),
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, mdbook_config: MdbookConfig) Self {
        // Create a config with external_docs for the symbol table
        const xref_config = config_mod.Config{
            .external_docs = mdbook_config.external_docs,
        };
        return Self{
            .allocator = allocator,
            .config = mdbook_config,
            .markdown_gen = MarkdownGenerator.init(allocator),
            .symbol_table = xref.SymbolTable.initWithConfig(allocator, xref_config),
            .snippet_extractor = snippet.SnippetExtractor.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.markdown_gen.deinit();
        self.symbol_table.deinit();
        self.snippet_extractor.deinit();
    }

    /// Generates the complete mdbook structure to the output directory
    pub fn generate(self: *Self, modules: []const types.Module) !void {
        const output_dir = self.config.output_dir;

        // Build symbol table from all modules for cross-referencing
        try self.symbol_table.buildFromModules(modules);

        // Configure markdown generator with cross-reference support
        self.markdown_gen.setSymbolTable(&self.symbol_table);
        self.markdown_gen.setOutputFormat(.mdbook);
        self.markdown_gen.setSnippetExtractor(&self.snippet_extractor);

        // Create output directory structure
        try self.createDirectoryStructure(output_dir);

        // Generate book.toml
        try self.generateBookToml(output_dir);

        // Generate SUMMARY.md
        try self.generateSummary(output_dir, modules);

        // Generate introduction
        if (self.config.generate_intro) {
            try self.generateIntroduction(output_dir, modules);
        }

        // Generate content pages based on grouping strategy
        switch (self.config.grouping) {
            .by_header => try self.generateByHeader(output_dir, modules),
            .by_prefix => try self.generateByPrefix(output_dir, modules),
            .flat => try self.generateFlat(output_dir, modules),
            .by_module => try self.generateByModule(output_dir, modules),
        }

        // Generate TODO.md, BUGS.md, TESTS.md, and INCLUDES.md if there are any
        try self.generateTodoPage(output_dir, modules);
        try self.generateBugsPage(output_dir, modules);
        try self.generateTestsPage(output_dir, modules);
        try self.generateIncludesPage(output_dir, modules);

        // Generate INDEX.md with alphabetical symbol listing
        try self.generateIndex(output_dir, modules);

        // Generate custom pages from @page and @mainpage
        try self.generateCustomPages(output_dir, modules);
    }

    /// Creates the directory structure for mdbook
    fn createDirectoryStructure(self: *Self, output_dir: []const u8) !void {
        const cwd = std.fs.cwd();

        // Create main output directory
        cwd.makePath(output_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Create src subdirectory
        var src_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const src_path = try std.fmt.bufPrint(&src_path_buf, "{s}/src", .{output_dir});
        cwd.makePath(src_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Create subdirectories for organized content
        const subdirs = [_][]const u8{ "functions", "types", "macros", "pages" };
        for (subdirs) |subdir| {
            var subdir_buf: [std.fs.max_path_bytes]u8 = undefined;
            const subdir_path = try std.fmt.bufPrint(&subdir_buf, "{s}/src/{s}", .{ output_dir, subdir });
            cwd.makePath(subdir_path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        _ = self;
    }

    /// Generates book.toml configuration file
    fn generateBookToml(self: *Self, output_dir: []const u8) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        // [book] section
        try content.appendSlice(self.allocator, "[book]\n");
        try content.appendSlice(self.allocator, "title = \"");
        try content.appendSlice(self.allocator, self.config.title);
        try content.appendSlice(self.allocator, "\"\n");

        // Authors
        if (self.config.authors.len > 0) {
            try content.appendSlice(self.allocator, "authors = [");
            for (self.config.authors, 0..) |author, i| {
                if (i > 0) try content.appendSlice(self.allocator, ", ");
                try content.appendSlice(self.allocator, "\"");
                try content.appendSlice(self.allocator, author);
                try content.appendSlice(self.allocator, "\"");
            }
            try content.appendSlice(self.allocator, "]\n");
        }

        try content.appendSlice(self.allocator, "language = \"");
        try content.appendSlice(self.allocator, self.config.language);
        try content.appendSlice(self.allocator, "\"\n\n");

        // [build] section
        try content.appendSlice(self.allocator, "[build]\n");
        try content.appendSlice(self.allocator, "build-dir = \"book\"\n\n");

        // [output.html] section for better code highlighting
        try content.appendSlice(self.allocator, "[output.html]\n");
        try content.appendSlice(self.allocator, "default-theme = \"light\"\n");
        try content.appendSlice(self.allocator, "preferred-dark-theme = \"navy\"\n");

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/book.toml", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates SUMMARY.md table of contents
    fn generateSummary(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# Summary\n\n");

        // Introduction
        if (self.config.generate_intro) {
            try content.appendSlice(self.allocator, "- [Introduction](./introduction.md)\n\n");
        }

        // Handle by_module grouping differently
        if (self.config.grouping == .by_module and self.config.module_configs.len > 0) {
            try self.generateModuleSummary(&content, modules);

            // Write file
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/SUMMARY.md", .{output_dir});
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(content.items);
            return;
        }

        // Collect all functions and types across modules
        var has_functions = false;
        var has_structs = false;
        var has_unions = false;
        var has_enums = false;
        var has_typedefs = false;
        var has_macros = false;
        var has_classes = false;
        var has_concepts = false;

        for (modules) |module| {
            if (module.functions.len > 0) has_functions = true;
            if (module.structs.len > 0) has_structs = true;
            if (module.unions.len > 0) has_unions = true;
            if (module.enums.len > 0) has_enums = true;
            if (module.typedefs.len > 0) has_typedefs = true;
            if (module.macros.len > 0) has_macros = true;
            if (module.classes.len > 0) has_classes = true;
            if (module.concepts.len > 0) has_concepts = true;
        }

        // Functions section
        if (has_functions) {
            try content.appendSlice(self.allocator, "# Functions\n\n");
            for (modules) |module| {
                if (module.functions.len > 0) {
                    const basename = self.getBasename(module.name);
                    try content.appendSlice(self.allocator, "- [");
                    try content.appendSlice(self.allocator, basename);
                    try content.appendSlice(self.allocator, "](./functions/");
                    try content.appendSlice(self.allocator, self.sanitizeFilename(basename));
                    try content.appendSlice(self.allocator, ".md)\n");
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Types section (includes structs, unions, enums, typedefs, classes, and concepts)
        if (has_structs or has_unions or has_enums or has_typedefs or has_classes or has_concepts) {
            try content.appendSlice(self.allocator, "# Types\n\n");
            for (modules) |module| {
                if (module.structs.len > 0 or module.unions.len > 0 or module.enums.len > 0 or module.typedefs.len > 0 or module.classes.len > 0 or module.concepts.len > 0) {
                    const basename = self.getBasename(module.name);
                    try content.appendSlice(self.allocator, "- [");
                    try content.appendSlice(self.allocator, basename);
                    try content.appendSlice(self.allocator, "](./types/");
                    try content.appendSlice(self.allocator, self.sanitizeFilename(basename));
                    try content.appendSlice(self.allocator, ".md)\n");
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Macros section
        if (has_macros) {
            try content.appendSlice(self.allocator, "# Macros\n\n");
            for (modules) |module| {
                if (module.macros.len > 0) {
                    const basename = self.getBasename(module.name);
                    try content.appendSlice(self.allocator, "- [");
                    try content.appendSlice(self.allocator, basename);
                    try content.appendSlice(self.allocator, "](./macros/");
                    try content.appendSlice(self.allocator, self.sanitizeFilename(basename));
                    try content.appendSlice(self.allocator, ".md)\n");
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Custom Pages section (non-mainpage pages from @page)
        var has_pages = false;
        for (modules) |module| {
            for (module.pages) |page| {
                if (!page.is_mainpage) {
                    has_pages = true;
                    break;
                }
            }
            if (has_pages) break;
        }

        if (has_pages) {
            try content.appendSlice(self.allocator, "# Pages\n\n");
            for (modules) |module| {
                for (module.pages) |page| {
                    if (!page.is_mainpage) {
                        try content.appendSlice(self.allocator, "- [");
                        try content.appendSlice(self.allocator, page.title);
                        try content.appendSlice(self.allocator, "](./pages/");
                        try content.appendSlice(self.allocator, page.id);
                        try content.appendSlice(self.allocator, ".md)\n");
                    }
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Reference section for Symbol Index
        try content.appendSlice(self.allocator, "# Reference\n\n");
        try content.appendSlice(self.allocator, "- [Symbol Index](./INDEX.md)\n\n");

        // Appendix section for TODOs, Bugs, Tests, and Includes
        const has_todos = self.hasTodos(modules);
        const has_bugs = self.hasBugs(modules);
        const has_tests = self.hasTests(modules);
        const has_includes = self.hasIncludes(modules);

        if (has_todos or has_bugs or has_tests or has_includes) {
            try content.appendSlice(self.allocator, "# Appendix\n\n");
            if (has_todos) {
                try content.appendSlice(self.allocator, "- [TODO List](./TODO.md)\n");
            }
            if (has_bugs) {
                try content.appendSlice(self.allocator, "- [Known Bugs](./BUGS.md)\n");
            }
            if (has_tests) {
                try content.appendSlice(self.allocator, "- [Test Coverage](./TESTS.md)\n");
            }
            if (has_includes) {
                try content.appendSlice(self.allocator, "- [Include Dependencies](./INCLUDES.md)\n");
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/SUMMARY.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates SUMMARY.md for by_module grouping
    fn generateModuleSummary(self: *Self, content: *std.ArrayList(u8), modules: []const types.Module) !void {
        const module_configs = self.config.module_configs;

        // Group modules by their assigned module config
        var module_groups = std.StringHashMap(std.ArrayList(types.Module)).init(self.allocator);
        defer {
            var it = module_groups.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.allocator);
            }
            module_groups.deinit();
        }

        var unassigned: std.ArrayList(types.Module) = .empty;
        defer unassigned.deinit(self.allocator);

        // Assign each module to a group based on pattern matching
        for (modules) |mod| {
            var matched = false;
            for (module_configs) |mod_config| {
                for (mod_config.patterns) |pattern| {
                    if (globMatch(pattern, mod.name)) {
                        const gop = try module_groups.getOrPut(mod_config.name);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = .empty;
                        }
                        try gop.value_ptr.append(self.allocator, mod);
                        matched = true;
                        break;
                    }
                }
                if (matched) break;
            }
            if (!matched) {
                try unassigned.append(self.allocator, mod);
            }
        }

        // Generate module sections
        for (module_configs) |mod_config| {
            if (module_groups.get(mod_config.name)) |group_modules| {
                if (group_modules.items.len > 0) {
                    // Module header
                    try content.appendSlice(self.allocator, "# ");
                    try content.appendSlice(self.allocator, mod_config.title);
                    try content.appendSlice(self.allocator, "\n\n");

                    // Module README
                    try content.appendSlice(self.allocator, "- [Overview](./");
                    try content.appendSlice(self.allocator, mod_config.name);
                    try content.appendSlice(self.allocator, "/README.md)\n");

                    // Check what content exists in this module
                    var has_functions = false;
                    var has_types = false;
                    var has_macros = false;

                    for (group_modules.items) |mod| {
                        if (mod.functions.len > 0) has_functions = true;
                        if (mod.structs.len > 0 or mod.unions.len > 0 or mod.enums.len > 0 or mod.typedefs.len > 0 or mod.classes.len > 0 or mod.concepts.len > 0) has_types = true;
                        if (mod.macros.len > 0) has_macros = true;
                    }

                    // Add links to module content
                    if (has_functions) {
                        try content.appendSlice(self.allocator, "- [Functions](./");
                        try content.appendSlice(self.allocator, mod_config.name);
                        try content.appendSlice(self.allocator, "/functions.md)\n");
                    }
                    if (has_types) {
                        try content.appendSlice(self.allocator, "- [Types](./");
                        try content.appendSlice(self.allocator, mod_config.name);
                        try content.appendSlice(self.allocator, "/types.md)\n");
                    }
                    if (has_macros) {
                        try content.appendSlice(self.allocator, "- [Macros](./");
                        try content.appendSlice(self.allocator, mod_config.name);
                        try content.appendSlice(self.allocator, "/macros.md)\n");
                    }

                    try content.appendSlice(self.allocator, "\n");
                }
            }
        }

        // Handle unassigned files (if any)
        if (unassigned.items.len > 0) {
            try content.appendSlice(self.allocator, "# Other\n\n");
            for (unassigned.items) |mod| {
                if (mod.functions.len > 0) {
                    const basename = self.getBasename(mod.name);
                    try content.appendSlice(self.allocator, "- [");
                    try content.appendSlice(self.allocator, basename);
                    try content.appendSlice(self.allocator, " (Functions)](./functions/");
                    try content.appendSlice(self.allocator, self.sanitizeFilename(basename));
                    try content.appendSlice(self.allocator, ".md)\n");
                }
                if (mod.structs.len > 0 or mod.unions.len > 0 or mod.enums.len > 0 or mod.typedefs.len > 0 or mod.classes.len > 0 or mod.concepts.len > 0) {
                    const basename = self.getBasename(mod.name);
                    try content.appendSlice(self.allocator, "- [");
                    try content.appendSlice(self.allocator, basename);
                    try content.appendSlice(self.allocator, " (Types)](./types/");
                    try content.appendSlice(self.allocator, self.sanitizeFilename(basename));
                    try content.appendSlice(self.allocator, ".md)\n");
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Reference section for Symbol Index
        try content.appendSlice(self.allocator, "# Reference\n\n");
        try content.appendSlice(self.allocator, "- [Symbol Index](./INDEX.md)\n\n");

        // Appendix section for TODOs, Bugs, Tests, and Includes
        const has_todos = self.hasTodos(modules);
        const has_bugs = self.hasBugs(modules);
        const has_tests = self.hasTests(modules);
        const has_includes = self.hasIncludes(modules);

        if (has_todos or has_bugs or has_tests or has_includes) {
            try content.appendSlice(self.allocator, "# Appendix\n\n");
            if (has_todos) {
                try content.appendSlice(self.allocator, "- [TODO List](./TODO.md)\n");
            }
            if (has_bugs) {
                try content.appendSlice(self.allocator, "- [Known Bugs](./BUGS.md)\n");
            }
            if (has_tests) {
                try content.appendSlice(self.allocator, "- [Test Coverage](./TESTS.md)\n");
            }
            if (has_includes) {
                try content.appendSlice(self.allocator, "- [Include Dependencies](./INCLUDES.md)\n");
            }
            try content.appendSlice(self.allocator, "\n");
        }
    }

    /// Generates introduction page
    fn generateIntroduction(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# ");
        try content.appendSlice(self.allocator, self.config.title);
        try content.appendSlice(self.allocator, "\n\n");

        try content.appendSlice(self.allocator, "Welcome to the API documentation.\n\n");

        // Statistics
        var total_functions: usize = 0;
        var total_structs: usize = 0;
        var total_unions: usize = 0;
        var total_enums: usize = 0;
        var total_typedefs: usize = 0;

        for (modules) |module| {
            total_functions += module.functions.len;
            total_structs += module.structs.len;
            total_unions += module.unions.len;
            total_enums += module.enums.len;
            total_typedefs += module.typedefs.len;
        }

        try content.appendSlice(self.allocator, "## Overview\n\n");
        try content.appendSlice(self.allocator, "This documentation covers:\n\n");

        var buf: [64]u8 = undefined;

        if (total_functions > 0) {
            const num = try std.fmt.bufPrint(&buf, "- **{d}** functions\n", .{total_functions});
            try content.appendSlice(self.allocator, num);
        }
        if (total_structs > 0) {
            const num = try std.fmt.bufPrint(&buf, "- **{d}** structures\n", .{total_structs});
            try content.appendSlice(self.allocator, num);
        }
        if (total_unions > 0) {
            const num = try std.fmt.bufPrint(&buf, "- **{d}** unions\n", .{total_unions});
            try content.appendSlice(self.allocator, num);
        }
        if (total_enums > 0) {
            const num = try std.fmt.bufPrint(&buf, "- **{d}** enumerations\n", .{total_enums});
            try content.appendSlice(self.allocator, num);
        }
        if (total_typedefs > 0) {
            const num = try std.fmt.bufPrint(&buf, "- **{d}** type definitions\n", .{total_typedefs});
            try content.appendSlice(self.allocator, num);
        }

        try content.appendSlice(self.allocator, "\n## Source Files\n\n");
        for (modules) |module| {
            try content.appendSlice(self.allocator, "- `");
            try content.appendSlice(self.allocator, module.name);
            try content.appendSlice(self.allocator, "`\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/introduction.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates content organized by header file
    fn generateByHeader(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // Collect all classes from all modules for inheritance diagrams
        var all_classes: std.ArrayList(types.Class) = .empty;
        defer all_classes.deinit(self.allocator);
        for (modules) |mod| {
            for (mod.classes) |class| {
                try all_classes.append(self.allocator, class);
            }
        }
        self.markdown_gen.setAllClasses(all_classes.items);

        for (modules) |module| {
            const basename = self.getBasename(module.name);
            const safe_name = self.sanitizeFilename(basename);

            // Generate functions page if there are functions
            if (module.functions.len > 0) {
                const func_module = types.Module{
                    .name = module.name,
                    .functions = module.functions,
                    .structs = &[_]types.Struct{},
                    .enums = &[_]types.Enum{},
                    .typedefs = &[_]types.Typedef{},
                };

                // Set current file context for relative link generation
                self.markdown_gen.setCurrentFile(module.name);
                const markdown = try self.markdown_gen.generate(func_module);

                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buf, "{s}/src/functions/{s}.md", .{ output_dir, safe_name });
                const file = try std.fs.cwd().createFile(path, .{});
                defer file.close();
                try file.writeAll(markdown);
            }

            // Generate types page if there are types (structs, unions, enums, typedefs, classes, or concepts)
            if (module.structs.len > 0 or module.unions.len > 0 or module.enums.len > 0 or module.typedefs.len > 0 or module.classes.len > 0 or module.concepts.len > 0) {
                const types_module = types.Module{
                    .name = module.name,
                    .functions = &[_]types.Function{},
                    .structs = module.structs,
                    .unions = module.unions,
                    .enums = module.enums,
                    .typedefs = module.typedefs,
                    .classes = module.classes,
                    .concepts = module.concepts,
                };

                // Set current file context for relative link generation
                self.markdown_gen.setCurrentFile(module.name);
                const markdown = try self.markdown_gen.generate(types_module);

                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buf, "{s}/src/types/{s}.md", .{ output_dir, safe_name });
                const file = try std.fs.cwd().createFile(path, .{});
                defer file.close();
                try file.writeAll(markdown);
            }

            // Generate macros page if there are macros
            if (module.macros.len > 0) {
                const macros_module = types.Module{
                    .name = module.name,
                    .functions = &[_]types.Function{},
                    .structs = &[_]types.Struct{},
                    .enums = &[_]types.Enum{},
                    .typedefs = &[_]types.Typedef{},
                    .macros = module.macros,
                };

                // Set current file context for relative link generation
                self.markdown_gen.setCurrentFile(module.name);
                const markdown = try self.markdown_gen.generate(macros_module);

                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buf, "{s}/src/macros/{s}.md", .{ output_dir, safe_name });
                const file = try std.fs.cwd().createFile(path, .{});
                defer file.close();
                try file.writeAll(markdown);
            }
        }
    }

    /// Generates content organized by prefix (e.g., vec_add, vec_sub grouped under "vec")
    fn generateByPrefix(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // Collect all symbols by prefix
        var prefix_groups = std.StringHashMap(PrefixGroup).init(self.allocator);
        defer {
            var iter = prefix_groups.valueIterator();
            while (iter.next()) |group| {
                group.functions.deinit(self.allocator);
                group.structs.deinit(self.allocator);
                group.unions.deinit(self.allocator);
                group.enums.deinit(self.allocator);
                group.typedefs.deinit(self.allocator);
                group.classes.deinit(self.allocator);
                group.macros.deinit(self.allocator);
            }
            prefix_groups.deinit();
        }

        // Group all items by prefix
        for (modules) |module| {
            for (module.functions) |func| {
                const prefix = extractPrefix(func.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .function = func });
            }
            for (module.structs) |s| {
                const prefix = extractPrefix(s.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .@"struct" = s });
            }
            for (module.unions) |u| {
                const prefix = extractPrefix(u.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .@"union" = u });
            }
            for (module.enums) |e| {
                const prefix = extractPrefix(e.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .@"enum" = e });
            }
            for (module.typedefs) |t| {
                const prefix = extractPrefix(t.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .typedef = t });
            }
            for (module.classes) |c| {
                const prefix = extractPrefix(c.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .class = c });
            }
            for (module.macros) |m| {
                const prefix = extractPrefix(m.name);
                try self.addToGroup(&prefix_groups, prefix, .{ .macro = m });
            }
        }

        // Create src directory
        var src_buf: [std.fs.max_path_bytes]u8 = undefined;
        const src_path = try std.fmt.bufPrint(&src_buf, "{s}/src", .{output_dir});
        std.fs.cwd().makeDir(src_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Generate a file for each prefix
        var group_iter = prefix_groups.iterator();
        while (group_iter.next()) |entry| {
            const prefix = entry.key_ptr.*;
            const group = entry.value_ptr.*;

            // Build a synthetic module for this prefix group
            const prefix_module = types.Module{
                .name = prefix,
                .functions = group.functions.items,
                .structs = group.structs.items,
                .unions = group.unions.items,
                .enums = group.enums.items,
                .typedefs = group.typedefs.items,
                .classes = group.classes.items,
                .macros = group.macros.items,
            };

            self.markdown_gen.setCurrentFile(prefix);
            const markdown = try self.markdown_gen.generate(prefix_module);

            // Sanitize prefix for filename
            const safe_name = self.sanitizeFilename(prefix);

            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/{s}.md", .{ output_dir, safe_name });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(markdown);
        }
    }

    const PrefixGroup = struct {
        functions: std.ArrayList(types.Function),
        structs: std.ArrayList(types.Struct),
        unions: std.ArrayList(types.Union),
        enums: std.ArrayList(types.Enum),
        typedefs: std.ArrayList(types.Typedef),
        classes: std.ArrayList(types.Class),
        macros: std.ArrayList(types.Macro),
    };

    const GroupItem = union(enum) {
        function: types.Function,
        @"struct": types.Struct,
        @"union": types.Union,
        @"enum": types.Enum,
        typedef: types.Typedef,
        class: types.Class,
        macro: types.Macro,
    };

    fn addToGroup(self: *Self, groups: *std.StringHashMap(PrefixGroup), prefix: []const u8, item: GroupItem) !void {
        const gop = try groups.getOrPut(prefix);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .functions = .empty,
                .structs = .empty,
                .unions = .empty,
                .enums = .empty,
                .typedefs = .empty,
                .classes = .empty,
                .macros = .empty,
            };
        }

        switch (item) {
            .function => |f| try gop.value_ptr.functions.append(self.allocator, f),
            .@"struct" => |s| try gop.value_ptr.structs.append(self.allocator, s),
            .@"union" => |u| try gop.value_ptr.unions.append(self.allocator, u),
            .@"enum" => |e| try gop.value_ptr.enums.append(self.allocator, e),
            .typedef => |t| try gop.value_ptr.typedefs.append(self.allocator, t),
            .class => |c| try gop.value_ptr.classes.append(self.allocator, c),
            .macro => |m| try gop.value_ptr.macros.append(self.allocator, m),
        }
    }

    /// Extracts prefix from a name (text before first underscore)
    /// Returns "misc" if no underscore found or prefix is too short
    fn extractPrefix(name: []const u8) []const u8 {
        if (std.mem.indexOf(u8, name, "_")) |idx| {
            if (idx >= 2) { // Minimum 2-char prefix
                return name[0..idx];
            }
        }
        // No underscore or too short prefix - use "misc" category
        return "misc";
    }

    /// Generates all content in a single flat structure
    fn generateFlat(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // Combine all modules into single pages
        var all_functions: std.ArrayList(types.Function) = .empty;
        defer all_functions.deinit(self.allocator);

        var all_structs: std.ArrayList(types.Struct) = .empty;
        defer all_structs.deinit(self.allocator);

        var all_unions: std.ArrayList(types.Union) = .empty;
        defer all_unions.deinit(self.allocator);

        var all_enums: std.ArrayList(types.Enum) = .empty;
        defer all_enums.deinit(self.allocator);

        var all_typedefs: std.ArrayList(types.Typedef) = .empty;
        defer all_typedefs.deinit(self.allocator);

        var all_classes: std.ArrayList(types.Class) = .empty;
        defer all_classes.deinit(self.allocator);

        for (modules) |module| {
            for (module.functions) |func| {
                try all_functions.append(self.allocator, func);
            }
            for (module.structs) |s| {
                try all_structs.append(self.allocator, s);
            }
            for (module.unions) |u| {
                try all_unions.append(self.allocator, u);
            }
            for (module.enums) |e| {
                try all_enums.append(self.allocator, e);
            }
            for (module.typedefs) |td| {
                try all_typedefs.append(self.allocator, td);
            }
            for (module.classes) |class| {
                try all_classes.append(self.allocator, class);
            }
        }

        // Set all classes for inheritance diagrams
        self.markdown_gen.setAllClasses(all_classes.items);

        // Generate functions page
        if (all_functions.items.len > 0) {
            const func_module = types.Module{
                .name = "Functions",
                .functions = all_functions.items,
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
            };

            const markdown = try self.markdown_gen.generate(func_module);

            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/functions.md", .{output_dir});
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(markdown);
        }

        // Generate types page
        if (all_structs.items.len > 0 or all_unions.items.len > 0 or all_enums.items.len > 0 or all_typedefs.items.len > 0 or all_classes.items.len > 0) {
            const types_module = types.Module{
                .name = "Types",
                .functions = &[_]types.Function{},
                .structs = all_structs.items,
                .unions = all_unions.items,
                .enums = all_enums.items,
                .typedefs = all_typedefs.items,
                .classes = all_classes.items,
            };

            const markdown = try self.markdown_gen.generate(types_module);

            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/types.md", .{output_dir});
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(markdown);
        }
    }

    /// Generates content organized by configured modules/packages
    fn generateByModule(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        const module_configs = self.config.module_configs;

        // If no modules configured, fall back to by_header
        if (module_configs.len == 0) {
            try self.generateByHeader(output_dir, modules);
            return;
        }

        // Collect all classes for inheritance diagrams
        var all_classes: std.ArrayList(types.Class) = .empty;
        defer all_classes.deinit(self.allocator);
        for (modules) |mod| {
            for (mod.classes) |class| {
                try all_classes.append(self.allocator, class);
            }
        }
        self.markdown_gen.setAllClasses(all_classes.items);

        // Group modules by their assigned module config
        var module_groups = std.StringHashMap(std.ArrayList(types.Module)).init(self.allocator);
        defer {
            var it = module_groups.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.allocator);
            }
            module_groups.deinit();
        }

        var unassigned: std.ArrayList(types.Module) = .empty;
        defer unassigned.deinit(self.allocator);

        // Assign each module to a group based on pattern matching
        for (modules) |mod| {
            var matched = false;
            for (module_configs) |mod_config| {
                for (mod_config.patterns) |pattern| {
                    if (globMatch(pattern, mod.name)) {
                        const gop = try module_groups.getOrPut(mod_config.name);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = .empty;
                        }
                        try gop.value_ptr.append(self.allocator, mod);
                        matched = true;
                        break;
                    }
                }
                if (matched) break;
            }
            if (!matched) {
                try unassigned.append(self.allocator, mod);
            }
        }

        // Generate each module's directory and files
        for (module_configs) |mod_config| {
            if (module_groups.get(mod_config.name)) |group_modules| {
                if (group_modules.items.len > 0) {
                    try self.generateModuleSection(output_dir, mod_config, group_modules.items);
                }
            }
        }

        // Handle unassigned files
        if (unassigned.items.len > 0) {
            try self.generateByHeader(output_dir, unassigned.items);
        }
    }

    /// Generates a module section with its own directory
    fn generateModuleSection(
        self: *Self,
        output_dir: []const u8,
        mod_config: config_mod.ModuleConfig,
        modules: []const types.Module,
    ) !void {
        // Create module directory
        var mod_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const mod_dir = try std.fmt.bufPrint(&mod_dir_buf, "{s}/src/{s}", .{ output_dir, mod_config.name });
        std.fs.cwd().makePath(mod_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Generate README.md for the module
        try self.generateModuleReadme(output_dir, mod_config, modules);

        // Aggregate all content from modules in this group
        var all_functions: std.ArrayList(types.Function) = .empty;
        defer all_functions.deinit(self.allocator);
        var all_structs: std.ArrayList(types.Struct) = .empty;
        defer all_structs.deinit(self.allocator);
        var all_unions: std.ArrayList(types.Union) = .empty;
        defer all_unions.deinit(self.allocator);
        var all_enums: std.ArrayList(types.Enum) = .empty;
        defer all_enums.deinit(self.allocator);
        var all_typedefs: std.ArrayList(types.Typedef) = .empty;
        defer all_typedefs.deinit(self.allocator);
        var all_classes_in_mod: std.ArrayList(types.Class) = .empty;
        defer all_classes_in_mod.deinit(self.allocator);
        var all_concepts: std.ArrayList(types.Concept) = .empty;
        defer all_concepts.deinit(self.allocator);
        var all_macros: std.ArrayList(types.Macro) = .empty;
        defer all_macros.deinit(self.allocator);

        for (modules) |module| {
            for (module.functions) |f| try all_functions.append(self.allocator, f);
            for (module.structs) |s| try all_structs.append(self.allocator, s);
            for (module.unions) |u| try all_unions.append(self.allocator, u);
            for (module.enums) |e| try all_enums.append(self.allocator, e);
            for (module.typedefs) |t| try all_typedefs.append(self.allocator, t);
            for (module.classes) |c| try all_classes_in_mod.append(self.allocator, c);
            for (module.concepts) |c| try all_concepts.append(self.allocator, c);
            for (module.macros) |m| try all_macros.append(self.allocator, m);
        }

        // Generate functions.md
        if (all_functions.items.len > 0) {
            const func_mod = types.Module{
                .name = mod_config.title,
                .functions = all_functions.items,
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
            };
            self.markdown_gen.setCurrentFile(mod_config.name);
            const md = try self.markdown_gen.generate(func_mod);
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/{s}/functions.md", .{ output_dir, mod_config.name });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(md);
        }

        // Generate types.md
        if (all_structs.items.len > 0 or all_unions.items.len > 0 or all_enums.items.len > 0 or all_typedefs.items.len > 0 or all_classes_in_mod.items.len > 0 or all_concepts.items.len > 0) {
            const types_mod = types.Module{
                .name = mod_config.title,
                .functions = &[_]types.Function{},
                .structs = all_structs.items,
                .unions = all_unions.items,
                .enums = all_enums.items,
                .typedefs = all_typedefs.items,
                .classes = all_classes_in_mod.items,
                .concepts = all_concepts.items,
            };
            self.markdown_gen.setCurrentFile(mod_config.name);
            const md = try self.markdown_gen.generate(types_mod);
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/{s}/types.md", .{ output_dir, mod_config.name });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(md);
        }

        // Generate macros.md
        if (all_macros.items.len > 0) {
            const macros_mod = types.Module{
                .name = mod_config.title,
                .functions = &[_]types.Function{},
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
                .macros = all_macros.items,
            };
            self.markdown_gen.setCurrentFile(mod_config.name);
            const md = try self.markdown_gen.generate(macros_mod);
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/{s}/macros.md", .{ output_dir, mod_config.name });
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(md);
        }
    }

    /// Generates README.md for a module section
    fn generateModuleReadme(
        self: *Self,
        output_dir: []const u8,
        mod_config: config_mod.ModuleConfig,
        modules: []const types.Module,
    ) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# ");
        try content.appendSlice(self.allocator, mod_config.title);
        try content.appendSlice(self.allocator, "\n\n");

        if (mod_config.description) |desc| {
            try content.appendSlice(self.allocator, desc);
            try content.appendSlice(self.allocator, "\n\n");
        }

        try content.appendSlice(self.allocator, "## Headers\n\n");
        for (modules) |mod| {
            try content.appendSlice(self.allocator, "- `");
            try content.appendSlice(self.allocator, mod.name);
            try content.appendSlice(self.allocator, "`\n");
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/{s}/README.md", .{ output_dir, mod_config.name });
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Extracts basename from a path (e.g., "include/foo.h" -> "foo.h")
    fn getBasename(self: *Self, path: []const u8) []const u8 {
        _ = self;
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
            return path[idx + 1 ..];
        }
        return path;
    }

    /// Sanitizes a filename for use in paths (removes extension, replaces special chars)
    fn sanitizeFilename(self: *Self, name: []const u8) []const u8 {
        _ = self;
        // Remove .h or .hpp extension
        if (std.mem.endsWith(u8, name, ".h")) {
            return name[0 .. name.len - 2];
        }
        if (std.mem.endsWith(u8, name, ".hpp")) {
            return name[0 .. name.len - 4];
        }
        return name;
    }

    /// Simple glob matching with * (any chars) and ? (single char)
    fn globMatch(pattern: []const u8, text: []const u8) bool {
        var pi: usize = 0;
        var ti: usize = 0;
        var star_pi: ?usize = null;
        var star_ti: usize = 0;

        while (ti < text.len) {
            if (pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == text[ti])) {
                pi += 1;
                ti += 1;
            } else if (pi < pattern.len and pattern[pi] == '*') {
                star_pi = pi;
                star_ti = ti;
                pi += 1;
            } else if (star_pi) |sp| {
                pi = sp + 1;
                star_ti += 1;
                ti = star_ti;
            } else {
                return false;
            }
        }

        while (pi < pattern.len and pattern[pi] == '*') {
            pi += 1;
        }

        return pi == pattern.len;
    }

    /// Collected TODO item with filled-in metadata
    const CollectedTodo = struct {
        description: []const u8,
        source_file: []const u8,
        line: u32,
        entity_name: []const u8,
    };

    /// Collected Bug item with filled-in metadata
    const CollectedBug = struct {
        description: []const u8,
        source_file: []const u8,
        line: u32,
        entity_name: []const u8,
    };

    /// Collected Test item with filled-in metadata
    const CollectedTest = struct {
        name: []const u8,
        file: ?[]const u8,
        source_file: []const u8,
        line: u32,
        entity_name: []const u8,
    };

    /// Collects all TODO items from all modules
    fn collectTodos(self: *Self, modules: []const types.Module) ![]CollectedTodo {
        var all_todos: std.ArrayList(CollectedTodo) = .empty;
        errdefer all_todos.deinit(self.allocator);

        for (modules) |module| {
            // Collect from functions
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    for (doc.todos) |todo| {
                        try all_todos.append(self.allocator, CollectedTodo{
                            .description = todo.description,
                            .source_file = module.name,
                            .line = func.location.line,
                            .entity_name = func.name,
                        });
                    }
                }
            }
            // Collect from classes
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    for (doc.todos) |todo| {
                        try all_todos.append(self.allocator, CollectedTodo{
                            .description = todo.description,
                            .source_file = module.name,
                            .line = class.location.line,
                            .entity_name = class.name,
                        });
                    }
                }
                // Collect from methods
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        for (doc.todos) |todo| {
                            try all_todos.append(self.allocator, CollectedTodo{
                                .description = todo.description,
                                .source_file = module.name,
                                .line = 0, // Methods don't have location
                                .entity_name = method.name,
                            });
                        }
                    }
                }
            }
            // Collect from structs
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    for (doc.todos) |todo| {
                        try all_todos.append(self.allocator, CollectedTodo{
                            .description = todo.description,
                            .source_file = module.name,
                            .line = s.location.line,
                            .entity_name = s.name,
                        });
                    }
                }
            }
            // Collect from macros
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    for (doc.todos) |todo| {
                        try all_todos.append(self.allocator, CollectedTodo{
                            .description = todo.description,
                            .source_file = module.name,
                            .line = macro.location.line,
                            .entity_name = macro.name,
                        });
                    }
                }
            }
        }
        return try all_todos.toOwnedSlice(self.allocator);
    }

    /// Collects all Bug items from all modules
    fn collectBugs(self: *Self, modules: []const types.Module) ![]CollectedBug {
        var all_bugs: std.ArrayList(CollectedBug) = .empty;
        errdefer all_bugs.deinit(self.allocator);

        for (modules) |module| {
            // Collect from functions
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    for (doc.bugs) |bug| {
                        try all_bugs.append(self.allocator, CollectedBug{
                            .description = bug.description,
                            .source_file = module.name,
                            .line = func.location.line,
                            .entity_name = func.name,
                        });
                    }
                }
            }
            // Collect from classes
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    for (doc.bugs) |bug| {
                        try all_bugs.append(self.allocator, CollectedBug{
                            .description = bug.description,
                            .source_file = module.name,
                            .line = class.location.line,
                            .entity_name = class.name,
                        });
                    }
                }
                // Collect from methods
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        for (doc.bugs) |bug| {
                            try all_bugs.append(self.allocator, CollectedBug{
                                .description = bug.description,
                                .source_file = module.name,
                                .line = 0, // Methods don't have location
                                .entity_name = method.name,
                            });
                        }
                    }
                }
            }
            // Collect from structs
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    for (doc.bugs) |bug| {
                        try all_bugs.append(self.allocator, CollectedBug{
                            .description = bug.description,
                            .source_file = module.name,
                            .line = s.location.line,
                            .entity_name = s.name,
                        });
                    }
                }
            }
            // Collect from macros
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    for (doc.bugs) |bug| {
                        try all_bugs.append(self.allocator, CollectedBug{
                            .description = bug.description,
                            .source_file = module.name,
                            .line = macro.location.line,
                            .entity_name = macro.name,
                        });
                    }
                }
            }
        }
        return try all_bugs.toOwnedSlice(self.allocator);
    }

    /// Collects all Test items from all modules
    fn collectTests(self: *Self, modules: []const types.Module) ![]CollectedTest {
        var all_tests: std.ArrayList(CollectedTest) = .empty;
        errdefer all_tests.deinit(self.allocator);

        for (modules) |module| {
            // Collect from functions
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    for (doc.tests) |t| {
                        try all_tests.append(self.allocator, CollectedTest{
                            .name = t.name,
                            .file = t.file,
                            .source_file = module.name,
                            .line = func.location.line,
                            .entity_name = func.name,
                        });
                    }
                }
            }
            // Collect from classes
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    for (doc.tests) |t| {
                        try all_tests.append(self.allocator, CollectedTest{
                            .name = t.name,
                            .file = t.file,
                            .source_file = module.name,
                            .line = class.location.line,
                            .entity_name = class.name,
                        });
                    }
                }
                // Collect from methods
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        for (doc.tests) |t| {
                            try all_tests.append(self.allocator, CollectedTest{
                                .name = t.name,
                                .file = t.file,
                                .source_file = module.name,
                                .line = 0, // Methods don't have location
                                .entity_name = method.name,
                            });
                        }
                    }
                }
            }
            // Collect from structs
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    for (doc.tests) |t| {
                        try all_tests.append(self.allocator, CollectedTest{
                            .name = t.name,
                            .file = t.file,
                            .source_file = module.name,
                            .line = s.location.line,
                            .entity_name = s.name,
                        });
                    }
                }
            }
            // Collect from macros
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    for (doc.tests) |t| {
                        try all_tests.append(self.allocator, CollectedTest{
                            .name = t.name,
                            .file = t.file,
                            .source_file = module.name,
                            .line = macro.location.line,
                            .entity_name = macro.name,
                        });
                    }
                }
            }
        }
        return try all_tests.toOwnedSlice(self.allocator);
    }

    /// Generates TODO.md page
    fn generateTodoPage(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        const todos = try self.collectTodos(modules);
        defer self.allocator.free(todos);

        if (todos.len == 0) return;

        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# TODO List\n\n");
        try content.appendSlice(self.allocator, "This page lists all TODO items found in the codebase.\n\n");

        // Group by source file
        var current_file: []const u8 = "";
        var current_entity: []const u8 = "";

        for (todos) |todo| {
            // New file section
            if (!std.mem.eql(u8, todo.source_file, current_file)) {
                current_file = todo.source_file;
                current_entity = "";
                try content.appendSlice(self.allocator, "## ");
                try content.appendSlice(self.allocator, self.getBasename(current_file));
                try content.appendSlice(self.allocator, "\n\n");
            }

            // New entity section
            if (!std.mem.eql(u8, todo.entity_name, current_entity)) {
                current_entity = todo.entity_name;
                try content.appendSlice(self.allocator, "### `");
                try content.appendSlice(self.allocator, current_entity);
                try content.appendSlice(self.allocator, "()`");
                if (todo.line > 0) {
                    try content.appendSlice(self.allocator, " (line ");
                    var line_buf: [16]u8 = undefined;
                    const line_str = try std.fmt.bufPrint(&line_buf, "{d}", .{todo.line});
                    try content.appendSlice(self.allocator, line_str);
                    try content.appendSlice(self.allocator, ")");
                }
                try content.appendSlice(self.allocator, "\n\n");
            }

            // TODO item as checkbox
            try content.appendSlice(self.allocator, "- [ ] ");
            try content.appendSlice(self.allocator, todo.description);
            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/TODO.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates BUGS.md page
    fn generateBugsPage(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        const bugs = try self.collectBugs(modules);
        defer self.allocator.free(bugs);

        if (bugs.len == 0) return;

        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# Known Bugs\n\n");
        try content.appendSlice(self.allocator, "This page lists all known bugs found in the codebase.\n\n");

        // Group by source file
        var current_file: []const u8 = "";
        var current_entity: []const u8 = "";

        for (bugs) |bug| {
            // New file section
            if (!std.mem.eql(u8, bug.source_file, current_file)) {
                current_file = bug.source_file;
                current_entity = "";
                try content.appendSlice(self.allocator, "## ");
                try content.appendSlice(self.allocator, self.getBasename(current_file));
                try content.appendSlice(self.allocator, "\n\n");
            }

            // New entity section
            if (!std.mem.eql(u8, bug.entity_name, current_entity)) {
                current_entity = bug.entity_name;
                try content.appendSlice(self.allocator, "### `");
                try content.appendSlice(self.allocator, current_entity);
                try content.appendSlice(self.allocator, "()`");
                if (bug.line > 0) {
                    try content.appendSlice(self.allocator, " (line ");
                    var line_buf: [16]u8 = undefined;
                    const line_str = try std.fmt.bufPrint(&line_buf, "{d}", .{bug.line});
                    try content.appendSlice(self.allocator, line_str);
                    try content.appendSlice(self.allocator, ")");
                }
                try content.appendSlice(self.allocator, "\n\n");
            }

            // Bug item
            try content.appendSlice(self.allocator, "- ");
            try content.appendSlice(self.allocator, bug.description);
            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/BUGS.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates TESTS.md page
    fn generateTestsPage(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        const tests = try self.collectTests(modules);
        defer self.allocator.free(tests);

        if (tests.len == 0) return;

        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# Test Coverage\n\n");
        try content.appendSlice(self.allocator, "This page lists all test references found in the codebase.\n\n");

        // Group by source file
        var current_file: []const u8 = "";
        var current_entity: []const u8 = "";

        for (tests) |t| {
            // New file section
            if (!std.mem.eql(u8, t.source_file, current_file)) {
                current_file = t.source_file;
                current_entity = "";
                try content.appendSlice(self.allocator, "## ");
                try content.appendSlice(self.allocator, self.getBasename(current_file));
                try content.appendSlice(self.allocator, "\n\n");
            }

            // New entity section
            if (!std.mem.eql(u8, t.entity_name, current_entity)) {
                current_entity = t.entity_name;
                try content.appendSlice(self.allocator, "### `");
                try content.appendSlice(self.allocator, current_entity);
                try content.appendSlice(self.allocator, "()`");
                if (t.line > 0) {
                    try content.appendSlice(self.allocator, " (line ");
                    var line_buf: [16]u8 = undefined;
                    const line_str = try std.fmt.bufPrint(&line_buf, "{d}", .{t.line});
                    try content.appendSlice(self.allocator, line_str);
                    try content.appendSlice(self.allocator, ")");
                }
                try content.appendSlice(self.allocator, "\n\n");
            }

            // Test item
            try content.appendSlice(self.allocator, "- `");
            try content.appendSlice(self.allocator, t.name);
            try content.appendSlice(self.allocator, "`");
            if (t.file) |file_path| {
                try content.appendSlice(self.allocator, " - *");
                try content.appendSlice(self.allocator, file_path);
                try content.appendSlice(self.allocator, "*");
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/TESTS.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates INCLUDES.md page with include dependency graph
    fn generateIncludesPage(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // Check if there are any includes
        var has_includes = false;
        for (modules) |module| {
            if (module.includes.len > 0) {
                has_includes = true;
                break;
            }
        }

        if (!has_includes) return;

        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# Include Dependencies\n\n");
        try content.appendSlice(self.allocator, "This page shows the include dependency graph for the project.\n\n");

        // Generate Mermaid diagram
        try content.appendSlice(self.allocator, "## Dependency Graph\n\n");
        var graph = diagrams.IncludeGraph.init(self.allocator);
        const mermaid = try graph.generateMermaid(modules, false); // Don't show system includes
        defer self.allocator.free(mermaid);
        try content.appendSlice(self.allocator, mermaid);
        try content.appendSlice(self.allocator, "\n");

        // Generate per-file include lists
        try content.appendSlice(self.allocator, "## Per-File Includes\n\n");

        for (modules) |module| {
            if (module.includes.len == 0) continue;

            const basename = self.getBasename(module.name);
            try content.appendSlice(self.allocator, "### `");
            try content.appendSlice(self.allocator, basename);
            try content.appendSlice(self.allocator, "`\n\n");

            // Local includes
            var has_local = false;
            for (module.includes) |inc| {
                if (!inc.is_system) {
                    if (!has_local) {
                        try content.appendSlice(self.allocator, "**Local includes:**\n\n");
                        has_local = true;
                    }
                    try content.appendSlice(self.allocator, "- `\"");
                    try content.appendSlice(self.allocator, inc.path);
                    try content.appendSlice(self.allocator, "\"` (line ");
                    var line_buf: [16]u8 = undefined;
                    const line_str = try std.fmt.bufPrint(&line_buf, "{d}", .{inc.line});
                    try content.appendSlice(self.allocator, line_str);
                    try content.appendSlice(self.allocator, ")\n");
                }
            }

            if (has_local) {
                try content.appendSlice(self.allocator, "\n");
            }

            // System includes
            var has_system = false;
            for (module.includes) |inc| {
                if (inc.is_system) {
                    if (!has_system) {
                        try content.appendSlice(self.allocator, "**System includes:**\n\n");
                        has_system = true;
                    }
                    try content.appendSlice(self.allocator, "- `<");
                    try content.appendSlice(self.allocator, inc.path);
                    try content.appendSlice(self.allocator, ">` (line ");
                    var line_buf: [16]u8 = undefined;
                    const line_str = try std.fmt.bufPrint(&line_buf, "{d}", .{inc.line});
                    try content.appendSlice(self.allocator, line_str);
                    try content.appendSlice(self.allocator, ")\n");
                }
            }

            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/INCLUDES.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Checks if modules have any todos
    fn hasTodos(self: *Self, modules: []const types.Module) bool {
        _ = self;
        for (modules) |module| {
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    if (doc.todos.len > 0) return true;
                }
            }
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    if (doc.todos.len > 0) return true;
                }
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        if (doc.todos.len > 0) return true;
                    }
                }
            }
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    if (doc.todos.len > 0) return true;
                }
            }
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    if (doc.todos.len > 0) return true;
                }
            }
        }
        return false;
    }

    /// Checks if modules have any bugs
    fn hasBugs(self: *Self, modules: []const types.Module) bool {
        _ = self;
        for (modules) |module| {
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    if (doc.bugs.len > 0) return true;
                }
            }
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    if (doc.bugs.len > 0) return true;
                }
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        if (doc.bugs.len > 0) return true;
                    }
                }
            }
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    if (doc.bugs.len > 0) return true;
                }
            }
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    if (doc.bugs.len > 0) return true;
                }
            }
        }
        return false;
    }

    /// Checks if modules have any test references
    fn hasTests(self: *Self, modules: []const types.Module) bool {
        _ = self;
        for (modules) |module| {
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    if (doc.tests.len > 0) return true;
                }
            }
            for (module.classes) |class| {
                if (class.doc) |doc| {
                    if (doc.tests.len > 0) return true;
                }
                for (class.methods) |method| {
                    if (method.doc) |doc| {
                        if (doc.tests.len > 0) return true;
                    }
                }
            }
            for (module.structs) |s| {
                if (s.doc) |doc| {
                    if (doc.tests.len > 0) return true;
                }
            }
            for (module.macros) |macro| {
                if (macro.doc) |doc| {
                    if (doc.tests.len > 0) return true;
                }
            }
        }
        return false;
    }

    /// Checks if modules have any includes
    fn hasIncludes(self: *Self, modules: []const types.Module) bool {
        _ = self;
        for (modules) |module| {
            if (module.includes.len > 0) return true;
        }
        return false;
    }

    /// Index entry for a symbol
    const IndexEntry = struct {
        name: []const u8,
        qualified_name: []const u8,
        kind: []const u8,
        brief: ?[]const u8,
        link: []const u8,
        sort_key: u8,
    };

    /// Generates an alphabetical index of all symbols
    fn generateIndex(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        var entries: std.ArrayList(IndexEntry) = .empty;
        defer entries.deinit(self.allocator);

        for (modules) |module| {
            const basename = self.getBasename(module.name);
            const safe_name = self.sanitizeFilename(basename);

            // Functions
            for (module.functions) |func| {
                if (func.name.len == 0) continue;
                const brief = if (func.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(func.name);
                const link = try std.fmt.allocPrint(self.allocator, "functions/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(func.name[0]);
                try entries.append(self.allocator, .{
                    .name = func.name,
                    .qualified_name = func.name,
                    .kind = "function",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }

            // Classes
            for (module.classes) |class| {
                if (class.name.len == 0) continue;
                const brief = if (class.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(class.name);
                const link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(class.name[0]);
                try entries.append(self.allocator, .{
                    .name = class.name,
                    .qualified_name = class.name,
                    .kind = "class",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });

                // Class methods (public only)
                for (class.methods) |method| {
                    if (method.access != .public) continue;
                    if (method.name.len == 0) continue;
                    const method_brief = if (method.doc) |doc| doc.brief else null;
                    const qualified = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class.name, method.name });
                    const class_anchor = try self.toAnchor(class.name);
                    const method_link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, class_anchor });
                    const method_sort_key = std.ascii.toUpper(method.name[0]);
                    try entries.append(self.allocator, .{
                        .name = method.name,
                        .qualified_name = qualified,
                        .kind = "method",
                        .brief = method_brief,
                        .link = method_link,
                        .sort_key = method_sort_key,
                    });
                }
            }

            // Structs
            for (module.structs) |s| {
                if (s.name.len == 0) continue;
                const brief = if (s.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(s.name);
                const link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(s.name[0]);
                try entries.append(self.allocator, .{
                    .name = s.name,
                    .qualified_name = s.name,
                    .kind = "struct",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }

            // Enums
            for (module.enums) |e| {
                if (e.name.len == 0) continue;
                const brief = if (e.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(e.name);
                const link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(e.name[0]);
                try entries.append(self.allocator, .{
                    .name = e.name,
                    .qualified_name = e.name,
                    .kind = "enum",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }

            // Macros
            for (module.macros) |macro| {
                if (macro.name.len == 0) continue;
                const brief = if (macro.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(macro.name);
                const link = try std.fmt.allocPrint(self.allocator, "macros/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(macro.name[0]);
                try entries.append(self.allocator, .{
                    .name = macro.name,
                    .qualified_name = macro.name,
                    .kind = "macro",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }

            // Typedefs
            for (module.typedefs) |td| {
                if (td.name.len == 0) continue;
                const brief = if (td.doc) |doc| doc.brief else null;
                const anchor = try self.toAnchor(td.name);
                const link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(td.name[0]);
                try entries.append(self.allocator, .{
                    .name = td.name,
                    .qualified_name = td.name,
                    .kind = "typedef",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }

            // Concepts
            for (module.concepts) |concept| {
                if (concept.name.len == 0) continue;
                const brief = if (concept.docstring) |doc| doc.brief else null;
                const anchor = try self.toAnchor(concept.name);
                const link = try std.fmt.allocPrint(self.allocator, "types/{s}.md#{s}", .{ safe_name, anchor });
                const sort_key = std.ascii.toUpper(concept.name[0]);
                try entries.append(self.allocator, .{
                    .name = concept.name,
                    .qualified_name = concept.name,
                    .kind = "concept",
                    .brief = brief,
                    .link = link,
                    .sort_key = sort_key,
                });
            }
        }

        // Sort entries by sort_key then by qualified_name
        std.mem.sort(IndexEntry, entries.items, {}, struct {
            fn lessThan(_: void, a: IndexEntry, b: IndexEntry) bool {
                if (a.sort_key != b.sort_key) return a.sort_key < b.sort_key;
                return std.mem.lessThan(u8, a.qualified_name, b.qualified_name);
            }
        }.lessThan);

        // Generate markdown content
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# Symbol Index\n\n");
        try content.appendSlice(self.allocator, "This page lists all documented symbols alphabetically.\n\n");

        var current_letter: u8 = 0;
        for (entries.items) |entry| {
            if (entry.sort_key != current_letter) {
                current_letter = entry.sort_key;
                try content.appendSlice(self.allocator, "\n## ");
                try content.append(self.allocator, current_letter);
                try content.appendSlice(self.allocator, "\n\n");
            }

            // Format: - [name](link) *(kind)* - brief
            try content.appendSlice(self.allocator, "- [");
            try content.appendSlice(self.allocator, entry.qualified_name);
            try content.appendSlice(self.allocator, "](");
            try content.appendSlice(self.allocator, entry.link);
            try content.appendSlice(self.allocator, ") *");
            try content.appendSlice(self.allocator, entry.kind);
            try content.appendSlice(self.allocator, "*");
            if (entry.brief) |brief| {
                try content.appendSlice(self.allocator, " - ");
                const max_len = 60;
                if (brief.len > max_len) {
                    try content.appendSlice(self.allocator, brief[0..max_len]);
                    try content.appendSlice(self.allocator, "...");
                } else {
                    try content.appendSlice(self.allocator, brief);
                }
            }
            try content.appendSlice(self.allocator, "\n");
        }

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/INDEX.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Converts a name to an anchor (lowercase for mdbook compatibility)
    fn toAnchor(self: *Self, name: []const u8) ![]const u8 {
        var result = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return result;
    }

    /// Generates custom pages from @page and @mainpage tags
    fn generateCustomPages(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        for (modules) |module| {
            for (module.pages) |page| {
                if (page.is_mainpage) {
                    // Mainpage replaces introduction.md
                    try self.generateMainpage(output_dir, page);
                } else {
                    // Regular page goes to pages/
                    try self.generatePage(output_dir, page);
                }
            }
        }
    }

    /// Generates the mainpage (replaces introduction.md)
    fn generateMainpage(self: *Self, output_dir: []const u8, page: types.Page) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# ");
        try content.appendSlice(self.allocator, page.title);
        try content.appendSlice(self.allocator, "\n\n");
        try content.appendSlice(self.allocator, page.content);
        try content.appendSlice(self.allocator, "\n");

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/introduction.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates a custom page from @page tag
    fn generatePage(self: *Self, output_dir: []const u8, page: types.Page) !void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "# ");
        try content.appendSlice(self.allocator, page.title);
        try content.appendSlice(self.allocator, "\n\n");
        try content.appendSlice(self.allocator, page.content);
        try content.appendSlice(self.allocator, "\n");

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/pages/{s}.md", .{ output_dir, page.id });
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
    }

    /// Generates mdbook structure and returns the output directory path
    pub fn generateToString(self: *Self, modules: []const types.Module) ![]const u8 {
        try self.generate(modules);
        return self.config.output_dir;
    }
};

// Tests
test "create mdbook generator" {
    var gen = MdbookGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try std.testing.expectEqualStrings("API Reference", gen.config.title);
    try std.testing.expectEqualStrings("docs", gen.config.output_dir);
}

test "create mdbook generator with config" {
    const config = MdbookConfig{
        .title = "My Library",
        .output_dir = "api-docs",
        .language = "en",
    };

    var gen = MdbookGenerator.initWithConfig(std.testing.allocator, config);
    defer gen.deinit();

    try std.testing.expectEqualStrings("My Library", gen.config.title);
    try std.testing.expectEqualStrings("api-docs", gen.config.output_dir);
}

test "get basename from path" {
    var gen = MdbookGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try std.testing.expectEqualStrings("foo.h", gen.getBasename("include/foo.h"));
    try std.testing.expectEqualStrings("bar.h", gen.getBasename("src/include/bar.h"));
    try std.testing.expectEqualStrings("baz.h", gen.getBasename("baz.h"));
}

test "sanitize filename" {
    var gen = MdbookGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try std.testing.expectEqualStrings("foo", gen.sanitizeFilename("foo.h"));
    try std.testing.expectEqualStrings("bar", gen.sanitizeFilename("bar.hpp"));
    try std.testing.expectEqualStrings("baz", gen.sanitizeFilename("baz"));
}
