//! Single File Writer
//!
//! Writes all rendered documentation to a single file.
//! Supports different output formats (markdown, HTML in the future).
//!
//! ## Usage
//!
//! ```zig
//! const writer = SingleFileWriter.init(allocator);
//! defer writer.deinit();
//!
//! try writer.write(document_model, "output.md");
//! ```

const std = @import("std");
const schema = @import("../json/schema.zig");
const markdown_renderer = @import("../render/markdown.zig");

pub const WriteError = error{
    CannotCreateFile,
    WriteError,
    OutOfMemory,
};

/// Options for single file output
pub const SingleFileOptions = struct {
    /// Include table of contents at the beginning
    include_toc: bool = true,
    /// Include index at the end
    include_index: bool = true,
    /// Include appendix sections (todos, bugs)
    include_appendix: bool = true,
    /// Title for the document (overrides project title)
    title: ?[]const u8 = null,
    /// Renderer configuration
    render_config: markdown_renderer.MarkdownRenderer.RenderConfig = .{},
};

/// Writes DocumentModel to a single markdown file
pub const SingleFileWriter = struct {
    allocator: std.mem.Allocator,
    options: SingleFileOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .options = .{},
        };
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: SingleFileOptions) Self {
        return Self{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to clean up for now
    }

    /// Write the document model to a file
    pub fn write(self: *Self, model: schema.DocumentModel, path: []const u8) WriteError!void {
        // Generate the content
        const content = self.render(model) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
            };
        };
        defer self.allocator.free(content);

        // Write to file
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

    /// Write the document model to stdout
    pub fn writeToStdout(self: *Self, model: schema.DocumentModel) WriteError!void {
        const content = self.render(model) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
            };
        };
        defer self.allocator.free(content);

        const stdout = std.fs.File.stdout();
        stdout.writeAll(content) catch |err| {
            std.debug.print("Error: Cannot write to stdout: {}\n", .{err});
            return error.WriteError;
        };
    }

    /// Render the complete document to a string
    pub fn render(self: *Self, model: schema.DocumentModel) ![]const u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.allocator);

        var renderer = markdown_renderer.MarkdownRenderer.initWithConfig(self.allocator, self.options.render_config);
        defer renderer.deinit();

        // Title
        const title = self.options.title orelse model.project.title;
        try output.appendSlice(self.allocator, "# ");
        try output.appendSlice(self.allocator, title);
        try output.appendSlice(self.allocator, "\n\n");

        // Project description
        if (model.project.description) |desc| {
            try output.appendSlice(self.allocator, desc);
            try output.appendSlice(self.allocator, "\n\n");
        }

        // Table of contents
        if (self.options.include_toc) {
            try self.renderTableOfContents(&output, model);
        }

        // Modules
        for (model.modules) |module| {
            const module_content = try renderer.renderModule(module);
            try output.appendSlice(self.allocator, module_content);
            try output.appendSlice(self.allocator, "\n");
        }

        // Pages
        for (model.pages) |page| {
            if (page.is_mainpage) continue; // Skip mainpage, handled separately

            try output.appendSlice(self.allocator, "---\n\n");
            const page_content = try renderer.renderPage(page);
            try output.appendSlice(self.allocator, page_content);
        }

        // Appendix
        if (self.options.include_appendix) {
            try self.renderAppendix(&output, model, &renderer);
        }

        // Index
        if (self.options.include_index and model.index.len > 0) {
            try output.appendSlice(self.allocator, "---\n\n");
            const index_content = try renderer.renderIndex(model.index, "Index");
            try output.appendSlice(self.allocator, index_content);
        }

        // Statistics footer
        try self.renderStatisticsFooter(&output, model);

        return try output.toOwnedSlice(self.allocator);
    }

    fn renderTableOfContents(self: *Self, output: *std.ArrayList(u8), model: schema.DocumentModel) !void {
        try output.appendSlice(self.allocator, "## Table of Contents\n\n");

        for (model.modules) |module| {
            const display_name = module.title orelse module.name;
            try output.appendSlice(self.allocator, "- [");
            try output.appendSlice(self.allocator, display_name);
            try output.appendSlice(self.allocator, "](#");
            try output.appendSlice(self.allocator, module.id);
            try output.appendSlice(self.allocator, ")\n");

            // Functions
            if (module.functions.len > 0) {
                try output.appendSlice(self.allocator, "  - Functions\n");
                for (module.functions) |func| {
                    try output.appendSlice(self.allocator, "    - [`");
                    try output.appendSlice(self.allocator, func.name);
                    try output.appendSlice(self.allocator, "`](#");
                    try output.appendSlice(self.allocator, func.anchor);
                    try output.appendSlice(self.allocator, ")\n");
                }
            }

            // Classes
            if (module.classes.len > 0) {
                try output.appendSlice(self.allocator, "  - Classes\n");
                for (module.classes) |class| {
                    try output.appendSlice(self.allocator, "    - [`");
                    try output.appendSlice(self.allocator, class.name);
                    try output.appendSlice(self.allocator, "`](#");
                    try output.appendSlice(self.allocator, class.anchor);
                    try output.appendSlice(self.allocator, ")\n");
                }
            }

            // Structs
            if (module.structs.len > 0) {
                try output.appendSlice(self.allocator, "  - Structures\n");
                for (module.structs) |s| {
                    try output.appendSlice(self.allocator, "    - [`");
                    try output.appendSlice(self.allocator, s.name);
                    try output.appendSlice(self.allocator, "`](#");
                    try output.appendSlice(self.allocator, s.anchor);
                    try output.appendSlice(self.allocator, ")\n");
                }
            }

            // Enums
            if (module.enums.len > 0) {
                try output.appendSlice(self.allocator, "  - Enumerations\n");
                for (module.enums) |e| {
                    try output.appendSlice(self.allocator, "    - [`");
                    try output.appendSlice(self.allocator, e.name);
                    try output.appendSlice(self.allocator, "`](#");
                    try output.appendSlice(self.allocator, e.anchor);
                    try output.appendSlice(self.allocator, ")\n");
                }
            }
        }

        try output.appendSlice(self.allocator, "\n---\n\n");
    }

    fn renderAppendix(self: *Self, output: *std.ArrayList(u8), model: schema.DocumentModel, renderer: *markdown_renderer.MarkdownRenderer) !void {
        const has_todos = model.appendix.todos.len > 0;
        const has_bugs = model.appendix.bugs.len > 0;

        if (!has_todos and !has_bugs) return;

        try output.appendSlice(self.allocator, "---\n\n");
        try output.appendSlice(self.allocator, "## Appendix\n\n");

        if (has_todos) {
            const todo_content = try renderer.renderTodoList(model.appendix.todos);
            try output.appendSlice(self.allocator, todo_content);
            try output.appendSlice(self.allocator, "\n");
        }

        if (has_bugs) {
            const bug_content = try renderer.renderBugList(model.appendix.bugs);
            try output.appendSlice(self.allocator, bug_content);
            try output.appendSlice(self.allocator, "\n");
        }
    }

    fn renderStatisticsFooter(self: *Self, output: *std.ArrayList(u8), model: schema.DocumentModel) !void {
        try output.appendSlice(self.allocator, "\n---\n\n");
        try output.appendSlice(self.allocator, "*Generated by ");
        try output.appendSlice(self.allocator, model.generator.name);
        try output.appendSlice(self.allocator, " ");
        try output.appendSlice(self.allocator, model.generator.version);
        try output.appendSlice(self.allocator, " at ");
        try output.appendSlice(self.allocator, model.generated_at);
        try output.appendSlice(self.allocator, "*\n\n");

        // Coverage
        try output.appendSlice(self.allocator, "*Documentation coverage: ");
        var buf: [16]u8 = undefined;
        const coverage_str = std.fmt.bufPrint(&buf, "{d:.1}", .{model.statistics.coverage_percent}) catch "?";
        try output.appendSlice(self.allocator, coverage_str);
        try output.appendSlice(self.allocator, "%*\n");
    }
};

// ============================================================================
// Tests
// ============================================================================

test "single file writer basic" {
    const allocator = std.testing.allocator;
    var writer = SingleFileWriter.init(allocator);
    defer writer.deinit();

    const model = schema.DocumentModel{
        .generator = .{ .name = "stig", .version = "0.3.0" },
        .generated_at = "2024-01-01T00:00:00Z",
        .project = .{ .title = "Test Project" },
        .config = .{},
        .statistics = .{
            .modules = 1,
            .functions = 2,
            .classes = 0,
            .structs = 0,
            .enums = 0,
            .macros = 0,
            .typedefs = 0,
            .type_aliases = 0,
            .concepts = 0,
            .documented = 2,
            .undocumented = 0,
            .coverage_percent = 100.0,
        },
        .index = &[_]schema.IndexEntry{},
        .modules = &[_]schema.ModuleDoc{},
        .pages = &[_]schema.PageDoc{},
        .appendix = .{},
    };

    const content = try writer.render(model);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "# Test Project") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Generated by stig") != null);
}
