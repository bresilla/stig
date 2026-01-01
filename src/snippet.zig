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

/// Extracts code snippets from source files based on anchor markers.
/// Supports the format:
/// ```
/// // [anchor_name]
/// code here
/// // [anchor_name]
/// ```
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
    /// The format is:
    /// ```
    /// // [anchor_name]
    /// code to extract
    /// // [anchor_name]
    /// ```
    pub fn extract(self: *Self, ref: types.SnippetRef) SnippetError![]const u8 {
        // Try to find and read the file
        const content = try self.loadFile(ref.file);

        // Build the anchor marker pattern: "// [anchor]"
        const start_marker = std.fmt.allocPrint(self.allocator, "// [{s}]", .{ref.anchor}) catch {
            return SnippetError.OutOfMemory;
        };
        defer self.allocator.free(start_marker);

        // Find first occurrence (start marker)
        const start_idx = std.mem.indexOf(u8, content, start_marker) orelse {
            return SnippetError.AnchorNotFound;
        };

        // Find the newline after start marker to get content start
        const content_start = std.mem.indexOfScalarPos(u8, content, start_idx, '\n') orelse {
            return SnippetError.InvalidSnippetFormat;
        };

        // Find second occurrence (end marker) - same marker text
        const end_idx = std.mem.indexOfPos(u8, content, content_start + 1, start_marker) orelse {
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
