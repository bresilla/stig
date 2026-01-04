const std = @import("std");
const ts = @import("tree-sitter");
const types = @import("../model/types.zig");
const DocstringExtractor = @import("../docstring/extractor.zig").DocstringExtractor;

/// Common utilities shared between C and C++ parsers
/// Gets the text content of a node from source
pub fn getNodeText(source: []const u8, node: ts.Node) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < source.len and end <= source.len and start < end) {
        return source[start..end];
    }
    return "";
}

/// Strips delimiters from trailing comments (///<, /**<, ///, /**, //, etc.)
pub fn stripTrailingCommentDelimiters(text: []const u8) []const u8 {
    var result = text;

    // Strip leading delimiters
    if (std.mem.startsWith(u8, result, "///<")) {
        result = result[4..];
    } else if (std.mem.startsWith(u8, result, "/**<")) {
        result = result[4..];
    } else if (std.mem.startsWith(u8, result, "///")) {
        result = result[3..];
    } else if (std.mem.startsWith(u8, result, "/**")) {
        result = result[3..];
    } else if (std.mem.startsWith(u8, result, "//")) {
        result = result[2..];
    }

    // Strip trailing */
    if (std.mem.endsWith(u8, result, "*/")) {
        result = result[0 .. result.len - 2];
    }

    return std.mem.trim(u8, result, " \t");
}

/// Extracts include directive information
/// Handles both #include <...> and #include "..."
pub fn extractInclude(source: []const u8, node: ts.Node) ?types.IncludeInfo {
    var path: ?[]const u8 = null;
    var is_system = false;

    var i: u32 = 0;
    while (i < node.childCount()) : (i += 1) {
        if (node.child(i)) |child| {
            const child_kind = child.kind();
            if (std.mem.eql(u8, child_kind, "system_lib_string")) {
                // #include <...>
                const text = getNodeText(source, child);
                // Remove < and >
                if (text.len >= 2) {
                    path = text[1 .. text.len - 1];
                    is_system = true;
                }
            } else if (std.mem.eql(u8, child_kind, "string_literal")) {
                // #include "..."
                const text = getNodeText(source, child);
                // Remove quotes
                if (text.len >= 2) {
                    path = text[1 .. text.len - 1];
                    is_system = false;
                }
            }
        }
    }

    if (path == null) return null;

    const start = node.startPoint();
    return types.IncludeInfo{
        .path = path.?,
        .is_system = is_system,
        .line = start.row + 1,
    };
}

/// Extracts custom pages from standalone doc comments containing @page or @mainpage
pub fn extractPages(
    allocator: std.mem.Allocator,
    source: []const u8,
    root: ts.Node,
    pages: *std.ArrayList(types.Page),
    docstring_extractor: *DocstringExtractor,
) !void {
    var i: u32 = 0;
    while (i < root.childCount()) : (i += 1) {
        if (root.child(i)) |child| {
            const child_kind = child.kind();

            if (std.mem.eql(u8, child_kind, "comment")) {
                const text = getNodeText(source, child);

                // Only process doc comments (/** or ///)
                if (!std.mem.startsWith(u8, text, "/**") and !std.mem.startsWith(u8, text, "///")) {
                    continue;
                }

                // Strip comment delimiters
                var stripped = text;
                if (std.mem.startsWith(u8, stripped, "/**")) {
                    stripped = stripped[3..];
                } else if (std.mem.startsWith(u8, stripped, "///")) {
                    stripped = stripped[3..];
                }
                if (std.mem.endsWith(u8, stripped, "*/")) {
                    stripped = stripped[0 .. stripped.len - 2];
                }
                stripped = std.mem.trim(u8, stripped, " \t\n\r");

                // Check if this comment contains @page or @mainpage
                if (docstring_extractor.containsPageCommand(stripped)) {
                    // Check if this comment is NOT attached to a declaration
                    // (standalone page comments should not be followed by a declaration)
                    const next = child.nextSibling();
                    const is_standalone = next == null or
                        std.mem.eql(u8, next.?.kind(), "comment") or
                        std.mem.eql(u8, next.?.kind(), "preproc_ifdef") or
                        std.mem.eql(u8, next.?.kind(), "preproc_ifndef") or
                        std.mem.eql(u8, next.?.kind(), "preproc_endif");

                    if (is_standalone) {
                        if (try docstring_extractor.parsePage(stripped)) |page| {
                            try pages.append(allocator, page);
                        }
                    }
                }
            }
        }
    }
}

// Tests
test "getNodeText empty source" {
    const source = "";
    // Create a mock node scenario - in practice this would need a real tree-sitter node
    // For now, just test the bounds checking logic
    _ = source;
}

test "stripTrailingCommentDelimiters" {
    try std.testing.expectEqualStrings("X coordinate", stripTrailingCommentDelimiters("/**< X coordinate */"));
    try std.testing.expectEqualStrings("Y coordinate", stripTrailingCommentDelimiters("///< Y coordinate"));
    try std.testing.expectEqualStrings("Description", stripTrailingCommentDelimiters("/// Description"));
    try std.testing.expectEqualStrings("Doc", stripTrailingCommentDelimiters("/** Doc */"));
    try std.testing.expectEqualStrings("Comment", stripTrailingCommentDelimiters("// Comment"));
}
