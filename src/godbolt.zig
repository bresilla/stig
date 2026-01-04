const std = @import("std");

/// Godbolt (Compiler Explorer) URL generator
pub const GodboltUrlGenerator = struct {
    allocator: std.mem.Allocator,
    compiler: []const u8 = "g132", // GCC 13.2
    options: []const u8 = "-O2 -std=c++20",

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Sets the compiler ID (e.g., "g132" for GCC 13.2, "clang1600" for Clang 16)
    pub fn setCompiler(self: *Self, compiler: []const u8) void {
        self.compiler = compiler;
    }

    /// Sets compiler options (e.g., "-O2 -std=c++20")
    pub fn setOptions(self: *Self, options: []const u8) void {
        self.options = options;
    }

    /// Generates a Godbolt URL for the given source code
    /// Returns a URL that opens Compiler Explorer with the code pre-loaded
    pub fn generateUrl(self: *Self, source: []const u8) ![]const u8 {
        // URL encode the source code
        const encoded_source = try self.urlEncode(source);
        defer self.allocator.free(encoded_source);

        // URL encode the compiler options
        const encoded_options = try self.urlEncode(self.options);
        defer self.allocator.free(encoded_options);

        // Build the Godbolt URL
        // Format: https://godbolt.org/#z:...
        // Using the simple format with compiler and source
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://godbolt.org/#g:!((g:!((g:!((h:codeEditor,i:(filename:'1',fontScale:14,fontUsePx:'0',j:1,lang:c%2B%2B,selection:(endColumn:1,endLineNumber:1,positionColumn:1,positionLineNumber:1,selectionStartColumn:1,selectionStartLineNumber:1,startColumn:1,startLineNumber:1),source:'{s}'),l:'5',n:'0',o:'C%2B%2B+source+%231',t:'0')),k:50,l:'4',n:'0',o:'',s:0,t:'0'),(g:!((h:compiler,i:(compiler:{s},filters:(b:'0',binary:'1',binaryObject:'1',commentOnly:'0',debugCalls:'1',demangle:'0',directives:'0',execute:'1',intel:'0',libraryCode:'0',trim:'1'),flagsViewOpen:'1',fontScale:14,fontUsePx:'0',j:1,lang:c%2B%2B,libs:!(),options:'{s}',overrides:!(),selection:(endColumn:1,endLineNumber:1,positionColumn:1,positionLineNumber:1,selectionStartColumn:1,selectionStartLineNumber:1,startColumn:1,startLineNumber:1),source:1),l:'5',n:'0',o:'{s}+(Editor+%231)',t:'0')),k:50,l:'4',n:'0',o:'',s:0,t:'0')),l:'2',n:'0',o:'',t:'0')),version:4",
            .{ encoded_source, self.compiler, encoded_options, self.compiler },
        );

        return url;
    }

    /// URL encodes a string (percent encoding)
    fn urlEncode(self: *Self, input: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        for (input) |c| {
            if (isUnreserved(c)) {
                try result.append(self.allocator, c);
            } else {
                // Percent encode
                try result.append(self.allocator, '%');
                const hex = "0123456789ABCDEF";
                try result.append(self.allocator, hex[c >> 4]);
                try result.append(self.allocator, hex[c & 0x0F]);
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Checks if a character is unreserved (doesn't need encoding)
    fn isUnreserved(c: u8) bool {
        return (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.' or c == '~';
    }

    /// Generates a markdown link to Godbolt
    pub fn generateMarkdownLink(self: *Self, source: []const u8, link_text: ?[]const u8) ![]const u8 {
        const url = try self.generateUrl(source);
        defer self.allocator.free(url);

        const text = link_text orelse "Run on Compiler Explorer";

        return try std.fmt.allocPrint(
            self.allocator,
            "[{s}]({s})",
            .{ text, url },
        );
    }

    /// Generates an HTML link to Godbolt
    pub fn generateHtmlLink(self: *Self, source: []const u8, link_text: ?[]const u8) ![]const u8 {
        const url = try self.generateUrl(source);
        defer self.allocator.free(url);

        const text = link_text orelse "Run on Compiler Explorer";

        return try std.fmt.allocPrint(
            self.allocator,
            "<a href=\"{s}\" target=\"_blank\" class=\"godbolt-link\">{s}</a>",
            .{ url, text },
        );
    }
};

// Tests
test "url encoding" {
    var gen = GodboltUrlGenerator.init(std.testing.allocator);

    const encoded = try gen.urlEncode("int main() { return 0; }");
    defer std.testing.allocator.free(encoded);

    try std.testing.expect(std.mem.indexOf(u8, encoded, "%20") != null); // Space encoded
    try std.testing.expect(std.mem.indexOf(u8, encoded, "%7B") != null); // { encoded
}

test "generate godbolt url" {
    var gen = GodboltUrlGenerator.init(std.testing.allocator);

    const url = try gen.generateUrl("int main() { return 42; }");
    defer std.testing.allocator.free(url);

    try std.testing.expect(std.mem.startsWith(u8, url, "https://godbolt.org/"));
}

test "generate markdown link" {
    var gen = GodboltUrlGenerator.init(std.testing.allocator);

    const link = try gen.generateMarkdownLink("int main() {}", "Try it");
    defer std.testing.allocator.free(link);

    try std.testing.expect(std.mem.startsWith(u8, link, "[Try it]("));
    try std.testing.expect(std.mem.indexOf(u8, link, "godbolt.org") != null);
}
