//! Multi File Writer
//!
//! Writes documentation to a directory with multiple files.
//! Primary use case is mdbook structure generation.
//!
//! ## Output Structure (mdbook)
//!
//! ```
//! output/
//! ├── book.toml
//! ├── src/
//! │   ├── SUMMARY.md
//! │   ├── introduction.md
//! │   ├── functions/
//! │   │   ├── module1.md
//! │   │   └── module2.md
//! │   ├── types/
//! │   │   ├── module1.md
//! │   │   └── module2.md
//! │   ├── macros/
//! │   │   └── module1.md
//! │   └── appendix/
//! │       ├── todos.md
//! │       ├── bugs.md
//! │       └── index.md
//! ```

const std = @import("std");
const schema = @import("../json/schema.zig");
const markdown_renderer = @import("../render/markdown.zig");

pub const WriteError = error{
    CannotCreateDirectory,
    CannotCreateFile,
    WriteError,
    OutOfMemory,
};

/// Options for multi-file output
pub const MultiFileOptions = struct {
    /// Book title
    title: []const u8 = "API Reference",
    /// Book authors
    authors: []const []const u8 = &[_][]const u8{},
    /// Language code (e.g., "en")
    language: []const u8 = "en",
    /// Generate introduction page
    generate_intro: bool = true,
    /// Generate index page
    generate_index: bool = true,
    /// Generate appendix (todos, bugs)
    generate_appendix: bool = true,
    /// Grouping strategy
    grouping: GroupingStrategy = .by_header,
    /// Renderer configuration
    render_config: markdown_renderer.MarkdownRenderer.RenderConfig = .{},
};

pub const GroupingStrategy = enum {
    /// Group by source header file
    by_header,
    /// All functions in one file, all types in one file, etc.
    by_kind,
    /// Everything in one file per directory section
    flat,
};

/// Writes DocumentModel to mdbook structure
pub const MultiFileWriter = struct {
    allocator: std.mem.Allocator,
    options: MultiFileOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .options = .{},
        };
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: MultiFileOptions) Self {
        return Self{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Write the document model to a directory
    pub fn write(self: *Self, model: schema.DocumentModel, output_dir: []const u8) WriteError!void {
        // Create directory structure
        try self.createDirectoryStructure(output_dir);

        // Generate book.toml
        try self.generateBookToml(output_dir);

        // Generate SUMMARY.md
        try self.generateSummary(output_dir, model);

        // Generate introduction
        if (self.options.generate_intro) {
            try self.generateIntroduction(output_dir, model);
        }

        // Generate content pages
        try self.generateContentPages(output_dir, model);

        // Generate appendix
        if (self.options.generate_appendix) {
            try self.generateAppendix(output_dir, model);
        }

        // Generate index
        if (self.options.generate_index) {
            try self.generateIndex(output_dir, model);
        }

        // Generate custom pages
        try self.generateCustomPages(output_dir, model);
    }

    fn createDirectoryStructure(self: *Self, output_dir: []const u8) WriteError!void {
        _ = self;
        const cwd = std.fs.cwd();

        // Create main output directory
        cwd.makePath(output_dir) catch |err| {
            if (err != error.PathAlreadyExists) return error.CannotCreateDirectory;
        };

        // Create src subdirectory
        var src_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const src_path = std.fmt.bufPrint(&src_path_buf, "{s}/src", .{output_dir}) catch return error.OutOfMemory;
        cwd.makePath(src_path) catch |err| {
            if (err != error.PathAlreadyExists) return error.CannotCreateDirectory;
        };

        // Create subdirectories
        const subdirs = [_][]const u8{ "functions", "types", "macros", "pages" };
        for (subdirs) |subdir| {
            var subdir_buf: [std.fs.max_path_bytes]u8 = undefined;
            const subdir_path = std.fmt.bufPrint(&subdir_buf, "{s}/src/{s}", .{ output_dir, subdir }) catch return error.OutOfMemory;
            cwd.makePath(subdir_path) catch |err| {
                if (err != error.PathAlreadyExists) return error.CannotCreateDirectory;
            };
        }
    }

    fn generateBookToml(self: *Self, output_dir: []const u8) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        // [book] section
        content.appendSlice(self.allocator, "[book]\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "title = \"") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, self.options.title) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "\"\n") catch return error.OutOfMemory;

        // Authors
        if (self.options.authors.len > 0) {
            content.appendSlice(self.allocator, "authors = [") catch return error.OutOfMemory;
            for (self.options.authors, 0..) |author, i| {
                if (i > 0) content.appendSlice(self.allocator, ", ") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "\"") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, author) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "\"") catch return error.OutOfMemory;
            }
            content.appendSlice(self.allocator, "]\n") catch return error.OutOfMemory;
        }

        content.appendSlice(self.allocator, "language = \"") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, self.options.language) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "\"\n\n") catch return error.OutOfMemory;

        // [build] section
        content.appendSlice(self.allocator, "[build]\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "build-dir = \"book\"\n\n") catch return error.OutOfMemory;

        // [output.html] section
        content.appendSlice(self.allocator, "[output.html]\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "default-theme = \"light\"\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "preferred-dark-theme = \"navy\"\n") catch return error.OutOfMemory;

        // Write file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/book.toml", .{output_dir}) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateSummary(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        content.appendSlice(self.allocator, "# Summary\n\n") catch return error.OutOfMemory;

        // Introduction
        if (self.options.generate_intro) {
            content.appendSlice(self.allocator, "[Introduction](introduction.md)\n\n") catch return error.OutOfMemory;
        }

        // Organize by module
        var has_functions = false;
        var has_types = false;
        var has_macros = false;

        for (model.modules) |module| {
            if (module.functions.len > 0) has_functions = true;
            if (module.classes.len > 0 or module.structs.len > 0 or module.enums.len > 0 or module.typedefs.len > 0 or module.type_aliases.len > 0) has_types = true;
            if (module.macros.len > 0) has_macros = true;
        }

        // Functions section
        if (has_functions) {
            content.appendSlice(self.allocator, "# Functions\n\n") catch return error.OutOfMemory;
            for (model.modules) |module| {
                if (module.functions.len == 0) continue;
                const basename = self.getFileBasename(module.name);
                content.appendSlice(self.allocator, "- [") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "](functions/") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, basename) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, ".md)\n") catch return error.OutOfMemory;
            }
            content.appendSlice(self.allocator, "\n") catch return error.OutOfMemory;
        }

        // Types section
        if (has_types) {
            content.appendSlice(self.allocator, "# Types\n\n") catch return error.OutOfMemory;
            for (model.modules) |module| {
                const has_any_types = module.classes.len > 0 or module.structs.len > 0 or
                    module.enums.len > 0 or module.typedefs.len > 0 or module.type_aliases.len > 0;
                if (!has_any_types) continue;
                const basename = self.getFileBasename(module.name);
                content.appendSlice(self.allocator, "- [") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "](types/") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, basename) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, ".md)\n") catch return error.OutOfMemory;
            }
            content.appendSlice(self.allocator, "\n") catch return error.OutOfMemory;
        }

        // Macros section
        if (has_macros) {
            content.appendSlice(self.allocator, "# Macros\n\n") catch return error.OutOfMemory;
            for (model.modules) |module| {
                if (module.macros.len == 0) continue;
                const basename = self.getFileBasename(module.name);
                content.appendSlice(self.allocator, "- [") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "](macros/") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, basename) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, ".md)\n") catch return error.OutOfMemory;
            }
            content.appendSlice(self.allocator, "\n") catch return error.OutOfMemory;
        }

        // Custom pages
        if (model.pages.len > 0) {
            content.appendSlice(self.allocator, "# Pages\n\n") catch return error.OutOfMemory;
            for (model.pages) |page| {
                if (page.is_mainpage) continue;
                content.appendSlice(self.allocator, "- [") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, page.title) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "](pages/") catch return error.OutOfMemory;
                content.appendSlice(self.allocator, page.id) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, ".md)\n") catch return error.OutOfMemory;
            }
            content.appendSlice(self.allocator, "\n") catch return error.OutOfMemory;
        }

        // Appendix
        if (self.options.generate_appendix or self.options.generate_index) {
            content.appendSlice(self.allocator, "---\n\n") catch return error.OutOfMemory;

            if (model.appendix.todos.len > 0) {
                content.appendSlice(self.allocator, "- [TODO List](TODO.md)\n") catch return error.OutOfMemory;
            }
            if (model.appendix.bugs.len > 0) {
                content.appendSlice(self.allocator, "- [Known Bugs](BUGS.md)\n") catch return error.OutOfMemory;
            }
            if (self.options.generate_index) {
                content.appendSlice(self.allocator, "- [Index](INDEX.md)\n") catch return error.OutOfMemory;
            }
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/SUMMARY.md", .{output_dir}) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateIntroduction(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        content.appendSlice(self.allocator, "# ") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, self.options.title) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "\n\n") catch return error.OutOfMemory;

        // Project description
        if (model.project.description) |desc| {
            content.appendSlice(self.allocator, desc) catch return error.OutOfMemory;
            content.appendSlice(self.allocator, "\n\n") catch return error.OutOfMemory;
        }

        // Main page content
        for (model.pages) |page| {
            if (page.is_mainpage) {
                content.appendSlice(self.allocator, page.content) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "\n\n") catch return error.OutOfMemory;
                break;
            }
        }

        // Statistics
        content.appendSlice(self.allocator, "## Statistics\n\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "| Metric | Count |\n") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, "|--------|-------|\n") catch return error.OutOfMemory;

        var buf: [32]u8 = undefined;

        content.appendSlice(self.allocator, "| Modules | ") catch return error.OutOfMemory;
        const modules_str = std.fmt.bufPrint(&buf, "{d}", .{model.statistics.modules}) catch "?";
        content.appendSlice(self.allocator, modules_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n") catch return error.OutOfMemory;

        content.appendSlice(self.allocator, "| Functions | ") catch return error.OutOfMemory;
        const funcs_str = std.fmt.bufPrint(&buf, "{d}", .{model.statistics.functions}) catch "?";
        content.appendSlice(self.allocator, funcs_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n") catch return error.OutOfMemory;

        content.appendSlice(self.allocator, "| Classes | ") catch return error.OutOfMemory;
        const classes_str = std.fmt.bufPrint(&buf, "{d}", .{model.statistics.classes}) catch "?";
        content.appendSlice(self.allocator, classes_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n") catch return error.OutOfMemory;

        content.appendSlice(self.allocator, "| Structs | ") catch return error.OutOfMemory;
        const structs_str = std.fmt.bufPrint(&buf, "{d}", .{model.statistics.structs}) catch "?";
        content.appendSlice(self.allocator, structs_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n") catch return error.OutOfMemory;

        content.appendSlice(self.allocator, "| Enums | ") catch return error.OutOfMemory;
        const enums_str = std.fmt.bufPrint(&buf, "{d}", .{model.statistics.enums}) catch "?";
        content.appendSlice(self.allocator, enums_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n") catch return error.OutOfMemory;

        content.appendSlice(self.allocator, "| Coverage | ") catch return error.OutOfMemory;
        const coverage_str = std.fmt.bufPrint(&buf, "{d:.1}%", .{model.statistics.coverage_percent}) catch "?";
        content.appendSlice(self.allocator, coverage_str) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " |\n\n") catch return error.OutOfMemory;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/introduction.md", .{output_dir}) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateContentPages(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var renderer = markdown_renderer.MarkdownRenderer.initWithConfig(self.allocator, self.options.render_config);
        defer renderer.deinit();

        for (model.modules) |module| {
            const basename = self.getFileBasename(module.name);

            // Generate functions page if module has functions
            if (module.functions.len > 0) {
                try self.generateFunctionsPage(output_dir, basename, module, &renderer);
            }

            // Generate types page if module has types
            const has_types = module.classes.len > 0 or module.structs.len > 0 or
                module.enums.len > 0 or module.typedefs.len > 0 or module.type_aliases.len > 0;
            if (has_types) {
                try self.generateTypesPage(output_dir, basename, module, &renderer);
            }

            // Generate macros page if module has macros
            if (module.macros.len > 0) {
                try self.generateMacrosPage(output_dir, basename, module, &renderer);
            }
        }
    }

    fn generateFunctionsPage(self: *Self, output_dir: []const u8, basename: []const u8, module: schema.ModuleDoc, renderer: *markdown_renderer.MarkdownRenderer) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        // Title
        content.appendSlice(self.allocator, "# ") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " - Functions\n\n") catch return error.OutOfMemory;

        // File-level documentation
        if (module.file_doc) |doc| {
            if (doc.brief) |brief| {
                content.appendSlice(self.allocator, brief) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, "\n\n") catch return error.OutOfMemory;
            }
        }

        // Functions
        for (module.functions) |func| {
            renderer.reset();
            renderer.renderFunction(func) catch return error.OutOfMemory;
            content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/functions/{s}.md", .{ output_dir, basename }) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateTypesPage(self: *Self, output_dir: []const u8, basename: []const u8, module: schema.ModuleDoc, renderer: *markdown_renderer.MarkdownRenderer) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        // Title
        content.appendSlice(self.allocator, "# ") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " - Types\n\n") catch return error.OutOfMemory;

        // Classes
        if (module.classes.len > 0) {
            content.appendSlice(self.allocator, "## Classes\n\n") catch return error.OutOfMemory;
            for (module.classes) |class| {
                renderer.reset();
                renderer.renderClass(class) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        // Structs
        if (module.structs.len > 0) {
            content.appendSlice(self.allocator, "## Structures\n\n") catch return error.OutOfMemory;
            for (module.structs) |s| {
                renderer.reset();
                renderer.renderStruct(s) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        // Unions
        if (module.unions.len > 0) {
            content.appendSlice(self.allocator, "## Unions\n\n") catch return error.OutOfMemory;
            for (module.unions) |u| {
                renderer.reset();
                renderer.renderUnion(u) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        // Enums
        if (module.enums.len > 0) {
            content.appendSlice(self.allocator, "## Enumerations\n\n") catch return error.OutOfMemory;
            for (module.enums) |e| {
                renderer.reset();
                renderer.renderEnum(e) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        // Typedefs
        if (module.typedefs.len > 0) {
            content.appendSlice(self.allocator, "## Type Definitions\n\n") catch return error.OutOfMemory;
            for (module.typedefs) |td| {
                renderer.reset();
                renderer.renderTypedef(td) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        // Type aliases
        if (module.type_aliases.len > 0) {
            content.appendSlice(self.allocator, "## Type Aliases\n\n") catch return error.OutOfMemory;
            for (module.type_aliases) |ta| {
                renderer.reset();
                renderer.renderTypeAlias(ta) catch return error.OutOfMemory;
                content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
            }
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/types/{s}.md", .{ output_dir, basename }) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateMacrosPage(self: *Self, output_dir: []const u8, basename: []const u8, module: schema.ModuleDoc, renderer: *markdown_renderer.MarkdownRenderer) WriteError!void {
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        // Title
        content.appendSlice(self.allocator, "# ") catch return error.OutOfMemory;
        content.appendSlice(self.allocator, module.title orelse module.name) catch return error.OutOfMemory;
        content.appendSlice(self.allocator, " - Macros\n\n") catch return error.OutOfMemory;

        // Macros
        for (module.macros) |m| {
            renderer.reset();
            renderer.renderMacro(m) catch return error.OutOfMemory;
            content.appendSlice(self.allocator, renderer.buffer.items) catch return error.OutOfMemory;
        }

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/macros/{s}.md", .{ output_dir, basename }) catch return error.OutOfMemory;
        try self.writeFile(path, content.items);
    }

    fn generateAppendix(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var renderer = markdown_renderer.MarkdownRenderer.initWithConfig(self.allocator, self.options.render_config);
        defer renderer.deinit();

        // TODO list
        if (model.appendix.todos.len > 0) {
            const content = renderer.renderTodoList(model.appendix.todos) catch return error.OutOfMemory;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/src/TODO.md", .{output_dir}) catch return error.OutOfMemory;
            try self.writeFile(path, content);
        }

        // Bug list
        if (model.appendix.bugs.len > 0) {
            const content = renderer.renderBugList(model.appendix.bugs) catch return error.OutOfMemory;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/src/BUGS.md", .{output_dir}) catch return error.OutOfMemory;
            try self.writeFile(path, content);
        }
    }

    fn generateIndex(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var renderer = markdown_renderer.MarkdownRenderer.initWithConfig(self.allocator, self.options.render_config);
        defer renderer.deinit();

        const content = renderer.renderIndex(model.index, "Index") catch return error.OutOfMemory;
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/src/INDEX.md", .{output_dir}) catch return error.OutOfMemory;
        try self.writeFile(path, content);
    }

    fn generateCustomPages(self: *Self, output_dir: []const u8, model: schema.DocumentModel) WriteError!void {
        var renderer = markdown_renderer.MarkdownRenderer.initWithConfig(self.allocator, self.options.render_config);
        defer renderer.deinit();

        for (model.pages) |page| {
            if (page.is_mainpage) continue; // Handled in introduction

            const content = renderer.renderPage(page) catch return error.OutOfMemory;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/src/pages/{s}.md", .{ output_dir, page.id }) catch return error.OutOfMemory;
            try self.writeFile(path, content);
        }
    }

    // =========================================================================
    // Utility Functions
    // =========================================================================

    fn getFileBasename(self: *Self, path: []const u8) []const u8 {
        _ = self;
        var result = path;

        // Get filename part (after last /)
        if (std.mem.lastIndexOfScalar(u8, result, '/')) |idx| {
            result = result[idx + 1 ..];
        }

        // Remove extension
        if (std.mem.lastIndexOfScalar(u8, result, '.')) |idx| {
            result = result[0..idx];
        }

        return result;
    }

    fn writeFile(self: *Self, path: []const u8, content: []const u8) WriteError!void {
        _ = self;
        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            std.debug.print("Error: Cannot create file '{s}': {}\n", .{ path, err });
            return error.CannotCreateFile;
        };
        defer file.close();

        file.writeAll(content) catch |err| {
            std.debug.print("Error: Cannot write to file '{s}': {}\n", .{ path, err });
            return error.WriteError;
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "multi file writer basic" {
    const allocator = std.testing.allocator;
    var writer = MultiFileWriter.init(allocator);
    defer writer.deinit();

    // Just test that initialization works
    try std.testing.expectEqualStrings("API Reference", writer.options.title);
}
