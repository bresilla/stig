const std = @import("std");
const types = @import("../model/types.zig");
const MarkdownGenerator = @import("markdown.zig").MarkdownGenerator;
const xref = @import("../xref.zig");

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

    pub const GroupingStrategy = enum {
        /// Group by source header file
        by_header,
        /// Group by function/type prefix
        by_prefix,
        /// All in one file
        flat,
    };
};

/// Generates mdbook-compatible documentation structure
pub const MdbookGenerator = struct {
    allocator: std.mem.Allocator,
    config: MdbookConfig,
    markdown_gen: MarkdownGenerator,
    /// Symbol table for cross-reference resolution
    symbol_table: xref.SymbolTable,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = .{},
            .markdown_gen = MarkdownGenerator.init(allocator),
            .symbol_table = xref.SymbolTable.init(allocator),
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: MdbookConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .markdown_gen = MarkdownGenerator.init(allocator),
            .symbol_table = xref.SymbolTable.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.markdown_gen.deinit();
        self.symbol_table.deinit();
    }

    /// Generates the complete mdbook structure to the output directory
    pub fn generate(self: *Self, modules: []const types.Module) !void {
        const output_dir = self.config.output_dir;

        // Build symbol table from all modules for cross-referencing
        try self.symbol_table.buildFromModules(modules);

        // Configure markdown generator with cross-reference support
        self.markdown_gen.setSymbolTable(&self.symbol_table);
        self.markdown_gen.setOutputFormat(.mdbook);

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
        }
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
        const subdirs = [_][]const u8{ "functions", "types", "macros" };
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

        // Collect all functions and types across modules
        var has_functions = false;
        var has_structs = false;
        var has_enums = false;
        var has_typedefs = false;
        var has_macros = false;

        for (modules) |module| {
            if (module.functions.len > 0) has_functions = true;
            if (module.structs.len > 0) has_structs = true;
            if (module.enums.len > 0) has_enums = true;
            if (module.typedefs.len > 0) has_typedefs = true;
            if (module.macros.len > 0) has_macros = true;
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

        // Types section
        if (has_structs or has_enums or has_typedefs) {
            try content.appendSlice(self.allocator, "# Types\n\n");
            for (modules) |module| {
                if (module.structs.len > 0 or module.enums.len > 0 or module.typedefs.len > 0) {
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

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/src/SUMMARY.md", .{output_dir});
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content.items);
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
        var total_enums: usize = 0;
        var total_typedefs: usize = 0;

        for (modules) |module| {
            total_functions += module.functions.len;
            total_structs += module.structs.len;
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

            // Generate types page if there are types
            if (module.structs.len > 0 or module.enums.len > 0 or module.typedefs.len > 0) {
                const types_module = types.Module{
                    .name = module.name,
                    .functions = &[_]types.Function{},
                    .structs = module.structs,
                    .enums = module.enums,
                    .typedefs = module.typedefs,
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

    /// Generates content organized by prefix (placeholder for future implementation)
    fn generateByPrefix(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // For now, fall back to by_header strategy
        // TODO: Implement prefix-based grouping
        try self.generateByHeader(output_dir, modules);
    }

    /// Generates all content in a single flat structure
    fn generateFlat(self: *Self, output_dir: []const u8, modules: []const types.Module) !void {
        // Combine all modules into single pages
        var all_functions: std.ArrayList(types.Function) = .empty;
        defer all_functions.deinit(self.allocator);

        var all_structs: std.ArrayList(types.Struct) = .empty;
        defer all_structs.deinit(self.allocator);

        var all_enums: std.ArrayList(types.Enum) = .empty;
        defer all_enums.deinit(self.allocator);

        var all_typedefs: std.ArrayList(types.Typedef) = .empty;
        defer all_typedefs.deinit(self.allocator);

        for (modules) |module| {
            for (module.functions) |func| {
                try all_functions.append(self.allocator, func);
            }
            for (module.structs) |s| {
                try all_structs.append(self.allocator, s);
            }
            for (module.enums) |e| {
                try all_enums.append(self.allocator, e);
            }
            for (module.typedefs) |td| {
                try all_typedefs.append(self.allocator, td);
            }
        }

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
        if (all_structs.items.len > 0 or all_enums.items.len > 0 or all_typedefs.items.len > 0) {
            const types_module = types.Module{
                .name = "Types",
                .functions = &[_]types.Function{},
                .structs = all_structs.items,
                .enums = all_enums.items,
                .typedefs = all_typedefs.items,
            };

            const markdown = try self.markdown_gen.generate(types_module);

            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/src/types.md", .{output_dir});
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(markdown);
        }
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
