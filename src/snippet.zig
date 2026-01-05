const std = @import("std");
const types = @import("model/types.zig");

/// Errors that can occur during snippet extraction
pub const SnippetError = error{
    FileNotFound,
    AnchorNotFound,
    InvalidSnippetFormat,
    OutOfMemory,
    ReadError,
};

/// Comment style for different file types
pub const CommentStyle = struct {
    prefix: []const u8,
    suffix: []const u8,

    /// C-style single line comments: // [anchor]
    pub const c_style = CommentStyle{ .prefix = "//", .suffix = "" };
    /// Hash comments: # [anchor]
    pub const hash_style = CommentStyle{ .prefix = "#", .suffix = "" };
    /// CSS/C block comments: /* [anchor] */
    pub const block_style = CommentStyle{ .prefix = "/*", .suffix = "*/" };
    /// HTML comments: <!-- [anchor] -->
    pub const html_style = CommentStyle{ .prefix = "<!--", .suffix = "-->" };
    /// SQL comments: -- [anchor]
    pub const sql_style = CommentStyle{ .prefix = "--", .suffix = "" };
    /// Lua comments: -- [anchor]
    pub const lua_style = CommentStyle{ .prefix = "--", .suffix = "" };
    /// Lisp comments: ; [anchor]
    pub const lisp_style = CommentStyle{ .prefix = ";", .suffix = "" };

    /// Get comment style for a file based on extension
    pub fn fromFilename(filename: []const u8) CommentStyle {
        // Python, Shell, Ruby, Perl, YAML, TOML, Makefile
        if (std.mem.endsWith(u8, filename, ".py") or
            std.mem.endsWith(u8, filename, ".sh") or
            std.mem.endsWith(u8, filename, ".bash") or
            std.mem.endsWith(u8, filename, ".zsh") or
            std.mem.endsWith(u8, filename, ".rb") or
            std.mem.endsWith(u8, filename, ".pl") or
            std.mem.endsWith(u8, filename, ".yaml") or
            std.mem.endsWith(u8, filename, ".yml") or
            std.mem.endsWith(u8, filename, ".toml") or
            std.mem.endsWith(u8, filename, "Makefile") or
            std.mem.endsWith(u8, filename, ".mk") or
            std.mem.endsWith(u8, filename, ".cmake") or
            std.mem.endsWith(u8, filename, ".conf") or
            std.mem.endsWith(u8, filename, ".ini") or
            std.mem.endsWith(u8, filename, ".dockerfile") or
            std.mem.endsWith(u8, filename, "Dockerfile"))
        {
            return hash_style;
        }

        // CSS
        if (std.mem.endsWith(u8, filename, ".css") or
            std.mem.endsWith(u8, filename, ".scss") or
            std.mem.endsWith(u8, filename, ".less"))
        {
            return block_style;
        }

        // HTML, XML, SVG
        if (std.mem.endsWith(u8, filename, ".html") or
            std.mem.endsWith(u8, filename, ".htm") or
            std.mem.endsWith(u8, filename, ".xml") or
            std.mem.endsWith(u8, filename, ".svg") or
            std.mem.endsWith(u8, filename, ".xhtml"))
        {
            return html_style;
        }

        // SQL
        if (std.mem.endsWith(u8, filename, ".sql")) {
            return sql_style;
        }

        // Lua
        if (std.mem.endsWith(u8, filename, ".lua")) {
            return lua_style;
        }

        // Lisp, Scheme, Clojure
        if (std.mem.endsWith(u8, filename, ".lisp") or
            std.mem.endsWith(u8, filename, ".scm") or
            std.mem.endsWith(u8, filename, ".clj") or
            std.mem.endsWith(u8, filename, ".el"))
        {
            return lisp_style;
        }

        // Default: C-style (C, C++, Java, JavaScript, TypeScript, Go, Rust, Zig, etc.)
        return c_style;
    }

    /// Build the anchor marker string
    pub fn buildMarker(self: CommentStyle, allocator: std.mem.Allocator, anchor: []const u8) ![]const u8 {
        if (self.suffix.len > 0) {
            // Block style: /* [anchor] */
            return try std.fmt.allocPrint(allocator, "{s} [{s}] {s}", .{ self.prefix, anchor, self.suffix });
        } else {
            // Line style: // [anchor]
            return try std.fmt.allocPrint(allocator, "{s} [{s}]", .{ self.prefix, anchor });
        }
    }
};

/// Extracts code snippets from source files based on anchor markers.
/// Supports multiple comment styles based on file extension:
/// - C/C++/Zig/Rust/Go/Java/JS/TS: // [anchor]
/// - Python/Shell/Ruby/YAML: # [anchor]
/// - CSS: /* [anchor] */
/// - HTML/XML: <!-- [anchor] -->
/// - SQL/Lua: -- [anchor]
pub const SnippetExtractor = struct {
    allocator: std.mem.Allocator,
    /// Paths to search for snippet files
    base_paths: []const []const u8,
    /// Cache of file contents to avoid re-reading
    cache: std.StringHashMap([]const u8),

    const Self = @This();

    /// Default search paths for snippet files
    const default_paths: []const []const u8 = &[_][]const u8{ ".", "examples/", "test/examples/", "test/fixtures/", "test/fixtures/examples/" };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .base_paths = default_paths,
            .cache = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all cached file contents
        var it = self.cache.valueIterator();
        while (it.next()) |content| {
            self.allocator.free(content.*);
        }
        self.cache.deinit();
    }

    /// Sets custom search paths for snippet files
    pub fn setBasePaths(self: *Self, paths: []const []const u8) void {
        self.base_paths = paths;
    }

    /// Extracts a snippet from a file by anchor name.
    /// Returns the code between [anchor] markers, or error if not found.
    ///
    /// The format depends on file type:
    /// - C/C++: // [anchor_name] ... // [anchor_name]
    /// - Python: # [anchor_name] ... # [anchor_name]
    /// - CSS: /* [anchor_name] */ ... /* [anchor_name] */
    /// - HTML: <!-- [anchor_name] --> ... <!-- [anchor_name] -->
    pub fn extract(self: *Self, ref: types.SnippetRef) SnippetError![]const u8 {
        // Try to find and read the file
        const content = try self.loadFile(ref.file);

        // Get comment style for this file type
        const style = CommentStyle.fromFilename(ref.file);

        // Build the anchor marker pattern based on file type
        const start_marker = style.buildMarker(self.allocator, ref.anchor) catch {
            return SnippetError.OutOfMemory;
        };
        defer self.allocator.free(start_marker);

        // Find first occurrence (start marker)
        var start_idx = std.mem.indexOf(u8, content, start_marker);

        // If not found with file-specific style, try C-style as fallback
        // This allows using // [anchor] in any file for compatibility
        if (start_idx == null and style.prefix.len > 0 and !std.mem.eql(u8, style.prefix, "//")) {
            const c_marker = CommentStyle.c_style.buildMarker(self.allocator, ref.anchor) catch {
                return SnippetError.OutOfMemory;
            };
            defer self.allocator.free(c_marker);
            start_idx = std.mem.indexOf(u8, content, c_marker);
            if (start_idx != null) {
                // Use C-style marker for end as well
                return self.extractWithMarker(content, c_marker);
            }
        }

        if (start_idx == null) {
            return SnippetError.AnchorNotFound;
        }

        return self.extractWithMarker(content, start_marker);
    }

    /// Extract snippet using a specific marker string
    fn extractWithMarker(self: *Self, content: []const u8, marker: []const u8) SnippetError![]const u8 {
        _ = self;

        // Find first occurrence (start marker)
        const start_idx = std.mem.indexOf(u8, content, marker) orelse {
            return SnippetError.AnchorNotFound;
        };

        // Find the newline after start marker to get content start
        const content_start = std.mem.indexOfScalarPos(u8, content, start_idx, '\n') orelse {
            return SnippetError.InvalidSnippetFormat;
        };

        // Find second occurrence (end marker) - same marker text
        const end_idx = std.mem.indexOfPos(u8, content, content_start + 1, marker) orelse {
            return SnippetError.AnchorNotFound;
        };

        // Extract content between markers (exclusive of markers and their newlines)
        const snippet = std.mem.trim(u8, content[content_start + 1 .. end_idx], "\n");
        return snippet;
    }

    /// Loads a file, checking multiple base paths.
    /// Caches file contents to avoid re-reading.
    fn loadFile(self: *Self, filename: []const u8) SnippetError![]const u8 {
        // Check cache first
        if (self.cache.get(filename)) |content| {
            return content;
        }

        // Try each base path
        for (self.base_paths) |base| {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = if (base.len > 0 and !std.mem.eql(u8, base, "."))
                std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ base, filename }) catch {
                    continue;
                }
            else
                filename;

            if (std.fs.cwd().openFile(full_path, .{})) |file| {
                defer file.close();
                const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
                    continue;
                };
                self.cache.put(filename, content) catch {
                    self.allocator.free(content);
                    return SnippetError.OutOfMemory;
                };
                return content;
            } else |_| {
                continue;
            }
        }

        return SnippetError.FileNotFound;
    }

    /// Gets the language for syntax highlighting from file extension.
    /// Returns the explicit language if set, otherwise infers from filename.
    pub fn getLanguage(ref: types.SnippetRef) []const u8 {
        // Use explicit language if provided
        if (ref.language) |lang| return lang;

        // Infer from file extension
        if (std.mem.endsWith(u8, ref.file, ".cpp") or
            std.mem.endsWith(u8, ref.file, ".hpp") or
            std.mem.endsWith(u8, ref.file, ".cc") or
            std.mem.endsWith(u8, ref.file, ".cxx") or
            std.mem.endsWith(u8, ref.file, ".hxx") or
            std.mem.endsWith(u8, ref.file, ".hh"))
        {
            return "cpp";
        }
        if (std.mem.endsWith(u8, ref.file, ".c") or
            std.mem.endsWith(u8, ref.file, ".h"))
        {
            return "c";
        }
        if (std.mem.endsWith(u8, ref.file, ".py")) {
            return "python";
        }
        if (std.mem.endsWith(u8, ref.file, ".rs")) {
            return "rust";
        }
        if (std.mem.endsWith(u8, ref.file, ".zig")) {
            return "zig";
        }
        if (std.mem.endsWith(u8, ref.file, ".js") or
            std.mem.endsWith(u8, ref.file, ".ts"))
        {
            return "javascript";
        }
        // Default to cpp for unknown extensions
        return "cpp";
    }

    /// Returns error description for display
    pub fn errorDescription(err: SnippetError) []const u8 {
        return switch (err) {
            SnippetError.FileNotFound => "File not found",
            SnippetError.AnchorNotFound => "Anchor not found in file",
            SnippetError.InvalidSnippetFormat => "Invalid snippet format",
            SnippetError.OutOfMemory => "Out of memory",
            SnippetError.ReadError => "Error reading file",
        };
    }
};

// Tests
test "get language from file extension" {
    try std.testing.expectEqualStrings("cpp", SnippetExtractor.getLanguage(.{
        .file = "test.cpp",
        .anchor = "test",
    }));
    try std.testing.expectEqualStrings("c", SnippetExtractor.getLanguage(.{
        .file = "test.c",
        .anchor = "test",
    }));
    try std.testing.expectEqualStrings("python", SnippetExtractor.getLanguage(.{
        .file = "test.py",
        .anchor = "test",
    }));
}

test "explicit language overrides extension" {
    try std.testing.expectEqualStrings("rust", SnippetExtractor.getLanguage(.{
        .file = "test.cpp",
        .anchor = "test",
        .language = "rust",
    }));
}

test "snippet extractor init and deinit" {
    var extractor = SnippetExtractor.init(std.testing.allocator);
    defer extractor.deinit();

    try std.testing.expectEqual(@as(usize, 3), extractor.base_paths.len);
}

test "set custom base paths" {
    var extractor = SnippetExtractor.init(std.testing.allocator);
    defer extractor.deinit();

    const custom_paths = &[_][]const u8{ "src/", "lib/" };
    extractor.setBasePaths(custom_paths);
    try std.testing.expectEqual(@as(usize, 2), extractor.base_paths.len);
}

test "comment style from filename - C style" {
    const style = CommentStyle.fromFilename("test.cpp");
    try std.testing.expectEqualStrings("//", style.prefix);
    try std.testing.expectEqualStrings("", style.suffix);

    const style2 = CommentStyle.fromFilename("test.zig");
    try std.testing.expectEqualStrings("//", style2.prefix);

    const style3 = CommentStyle.fromFilename("test.rs");
    try std.testing.expectEqualStrings("//", style3.prefix);
}

test "comment style from filename - hash style" {
    const style = CommentStyle.fromFilename("test.py");
    try std.testing.expectEqualStrings("#", style.prefix);
    try std.testing.expectEqualStrings("", style.suffix);

    const style2 = CommentStyle.fromFilename("test.sh");
    try std.testing.expectEqualStrings("#", style2.prefix);

    const style3 = CommentStyle.fromFilename("Makefile");
    try std.testing.expectEqualStrings("#", style3.prefix);
}

test "comment style from filename - block style" {
    const style = CommentStyle.fromFilename("test.css");
    try std.testing.expectEqualStrings("/*", style.prefix);
    try std.testing.expectEqualStrings("*/", style.suffix);
}

test "comment style from filename - HTML style" {
    const style = CommentStyle.fromFilename("test.html");
    try std.testing.expectEqualStrings("<!--", style.prefix);
    try std.testing.expectEqualStrings("-->", style.suffix);
}

test "comment style from filename - SQL style" {
    const style = CommentStyle.fromFilename("test.sql");
    try std.testing.expectEqualStrings("--", style.prefix);
    try std.testing.expectEqualStrings("", style.suffix);
}

test "build marker - line style" {
    const style = CommentStyle.c_style;
    const marker = try style.buildMarker(std.testing.allocator, "my_anchor");
    defer std.testing.allocator.free(marker);
    try std.testing.expectEqualStrings("// [my_anchor]", marker);
}

test "build marker - hash style" {
    const style = CommentStyle.hash_style;
    const marker = try style.buildMarker(std.testing.allocator, "example");
    defer std.testing.allocator.free(marker);
    try std.testing.expectEqualStrings("# [example]", marker);
}

test "build marker - block style" {
    const style = CommentStyle.block_style;
    const marker = try style.buildMarker(std.testing.allocator, "css_example");
    defer std.testing.allocator.free(marker);
    try std.testing.expectEqualStrings("/* [css_example] */", marker);
}

test "build marker - HTML style" {
    const style = CommentStyle.html_style;
    const marker = try style.buildMarker(std.testing.allocator, "html_snippet");
    defer std.testing.allocator.free(marker);
    try std.testing.expectEqualStrings("<!-- [html_snippet] -->", marker);
}
