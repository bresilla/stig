const std = @import("std");
const types = @import("model/types.zig");
const CParser = @import("parser/c.zig").CParser;
const MarkdownGenerator = @import("output/markdown.zig").MarkdownGenerator;

/// mdbook preprocessor for stig
/// Processes {{#stig ...}} directives in mdbook chapters
pub const Preprocessor = struct {
    allocator: std.mem.Allocator,
    parser: CParser,
    markdown_gen: MarkdownGenerator,
    /// Root directory of the book
    book_root: []const u8 = "",
    /// Cached parsed modules
    modules: std.StringHashMap(types.Module),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .parser = try CParser.init(allocator),
            .markdown_gen = MarkdownGenerator.init(allocator),
            .modules = std.StringHashMap(types.Module).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        self.markdown_gen.deinit();
        self.modules.deinit();
    }

    /// Runs the preprocessor, reading from stdin and writing to stdout
    pub fn run(self: *Self) !void {
        // Read all input from stdin
        const stdin = std.fs.File.stdin();
        var input_buffer: std.ArrayList(u8) = .empty;
        defer input_buffer.deinit(self.allocator);

        // Read until EOF
        var buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stdin.read(&buf) catch |err| {
                std.debug.print("Warning: Error reading stdin: {}\n", .{err});
                break;
            };
            if (bytes_read == 0) break;
            try input_buffer.appendSlice(self.allocator, buf[0..bytes_read]);
        }

        const input = input_buffer.items;

        // mdbook sends [context, book] as a JSON array
        // Find the opening bracket
        const array_start = std.mem.indexOf(u8, input, "[") orelse {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(input);
            return;
        };

        // Find the context object (first element after '[')
        var pos = array_start + 1;
        // Skip whitespace
        while (pos < input.len and (input[pos] == ' ' or input[pos] == '\n' or input[pos] == '\t')) {
            pos += 1;
        }

        const context_start = pos;
        const context_end = self.findJsonEnd(input, context_start) orelse {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(input);
            return;
        };

        // Parse context to get book root
        self.parseContext(input[context_start..context_end]) catch |err| {
            std.debug.print("Warning: Failed to parse mdbook context: {}\n", .{err});
        };

        // Skip comma and whitespace to find book object
        pos = context_end;
        while (pos < input.len and (input[pos] == ' ' or input[pos] == '\n' or input[pos] == '\t' or input[pos] == ',')) {
            pos += 1;
        }

        const book_start = pos;
        const book_end = self.findJsonEnd(input, book_start) orelse {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(input);
            return;
        };

        // Process the book
        const book_json = input[book_start..book_end];
        const processed = try self.processBook(book_json);
        defer self.allocator.free(processed);

        // Write output: just the processed book (mdbook expects only the book object)
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(processed);
    }

    /// Finds the end of a JSON object/array
    fn findJsonEnd(self: *Self, input: []const u8, start: usize) ?usize {
        _ = self;
        if (start >= input.len) return null;

        var depth: i32 = 0;
        var in_string = false;
        var i = start;

        while (i < input.len) : (i += 1) {
            const c = input[i];

            if (in_string) {
                if (c == '\\' and i + 1 < input.len) {
                    i += 1; // Skip escaped char
                } else if (c == '"') {
                    in_string = false;
                }
            } else {
                if (c == '"') {
                    in_string = true;
                } else if (c == '{' or c == '[') {
                    depth += 1;
                } else if (c == '}' or c == ']') {
                    depth -= 1;
                    if (depth == 0) {
                        return i + 1;
                    }
                }
            }
        }

        return null;
    }

    /// Parses the mdbook context to extract book root
    fn parseContext(self: *Self, json: []const u8) !void {
        // Simple extraction of "root" field
        if (std.mem.indexOf(u8, json, "\"root\"")) |idx| {
            const after_key = json[idx + 6 ..];
            if (std.mem.indexOf(u8, after_key, "\"")) |start| {
                const value_start = start + 1;
                if (std.mem.indexOf(u8, after_key[value_start..], "\"")) |end| {
                    self.book_root = after_key[value_start .. value_start + end];
                }
            }
        }
    }

    /// Processes the book JSON, replacing stig directives
    fn processBook(self: *Self, book_json: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.allocator);

        var i: usize = 0;
        while (i < book_json.len) {
            // Look for "content" fields which contain chapter markdown
            if (i + 10 <= book_json.len and std.mem.eql(u8, book_json[i .. i + 10], "\"content\":")) {
                // Copy the key
                try output.appendSlice(self.allocator, "\"content\":");
                i += 10;

                // Skip whitespace
                while (i < book_json.len and (book_json[i] == ' ' or book_json[i] == '\n')) {
                    try output.append(self.allocator, book_json[i]);
                    i += 1;
                }

                // Parse the string value
                if (i < book_json.len and book_json[i] == '"') {
                    const content_start = i + 1;
                    var content_end = content_start;
                    var in_escape = false;

                    while (content_end < book_json.len) {
                        if (in_escape) {
                            in_escape = false;
                        } else if (book_json[content_end] == '\\') {
                            in_escape = true;
                        } else if (book_json[content_end] == '"') {
                            break;
                        }
                        content_end += 1;
                    }

                    // Extract and process content
                    const content = book_json[content_start..content_end];
                    const processed_content = try self.processContent(content);
                    defer self.allocator.free(processed_content);

                    // Write processed content as JSON string
                    try output.append(self.allocator, '"');
                    try output.appendSlice(self.allocator, processed_content);
                    try output.append(self.allocator, '"');

                    i = content_end + 1;
                    continue;
                }
            }

            try output.append(self.allocator, book_json[i]);
            i += 1;
        }

        return output.toOwnedSlice(self.allocator);
    }

    /// Processes chapter content, replacing {{#stig ...}} directives
    fn processContent(self: *Self, content: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.allocator);

        var i: usize = 0;
        while (i < content.len) {
            // Look for {{#stig
            if (i + 8 <= content.len and std.mem.eql(u8, content[i .. i + 8], "{{#stig ")) {
                const directive_start = i;
                i += 8;

                // Find the end }}
                const directive_end = std.mem.indexOf(u8, content[i..], "}}") orelse {
                    try output.appendSlice(self.allocator, content[directive_start..]);
                    break;
                };

                const args = std.mem.trim(u8, content[i .. i + directive_end], " \t\n");
                i += directive_end + 2;

                // Process the directive
                const replacement = try self.processDirective(args);
                defer self.allocator.free(replacement);

                // Escape for JSON
                for (replacement) |c| {
                    switch (c) {
                        '"' => try output.appendSlice(self.allocator, "\\\""),
                        '\\' => try output.appendSlice(self.allocator, "\\\\"),
                        '\n' => try output.appendSlice(self.allocator, "\\n"),
                        '\r' => try output.appendSlice(self.allocator, "\\r"),
                        '\t' => try output.appendSlice(self.allocator, "\\t"),
                        else => try output.append(self.allocator, c),
                    }
                }
            } else {
                try output.append(self.allocator, content[i]);
                i += 1;
            }
        }

        return output.toOwnedSlice(self.allocator);
    }

    /// Processes a single stig directive
    fn processDirective(self: *Self, args: []const u8) ![]u8 {
        // Parse directive: "api path/to/file.h" or "function func_name" or "struct StructName"
        var iter = std.mem.splitScalar(u8, args, ' ');
        const command = iter.next() orelse return try self.allocator.dupe(u8, "");
        const arg = iter.next() orelse return try self.allocator.dupe(u8, "");

        if (std.mem.eql(u8, command, "api") or std.mem.eql(u8, command, "file")) {
            // Generate full API docs for a file
            return try self.generateFileDoc(arg);
        } else if (std.mem.eql(u8, command, "function") or std.mem.eql(u8, command, "func")) {
            // Generate docs for a specific function
            return try self.generateFunctionDoc(arg);
        } else if (std.mem.eql(u8, command, "struct") or std.mem.eql(u8, command, "type")) {
            // Generate docs for a specific struct
            return try self.generateStructDoc(arg);
        } else if (std.mem.eql(u8, command, "enum")) {
            // Generate docs for a specific enum
            return try self.generateEnumDoc(arg);
        } else if (std.mem.eql(u8, command, "macro")) {
            // Generate docs for a specific macro
            return try self.generateMacroDoc(arg);
        }

        // Unknown command, return empty
        return try self.allocator.dupe(u8, "");
    }

    /// Generates documentation for an entire file
    fn generateFileDoc(self: *Self, path: []const u8) ![]u8 {
        const module = try self.getOrParseModule(path);

        // Generate markdown
        const markdown = try self.markdown_gen.generate(module);
        return try self.allocator.dupe(u8, markdown);
    }

    /// Generates documentation for a specific function
    fn generateFunctionDoc(self: *Self, name: []const u8) ![]u8 {
        // Search all cached modules for the function
        var iter = self.modules.valueIterator();
        while (iter.next()) |module| {
            for (module.functions) |func| {
                if (std.mem.eql(u8, func.name, name)) {
                    // Generate just this function's docs
                    const single_module = types.Module{
                        .name = "",
                        .functions = &[_]types.Function{func},
                        .structs = &[_]types.Struct{},
                        .enums = &[_]types.Enum{},
                        .typedefs = &[_]types.Typedef{},
                    };
                    const markdown = try self.markdown_gen.generate(single_module);
                    return try self.allocator.dupe(u8, markdown);
                }
            }
        }

        return try self.allocator.dupe(u8, "<!-- Function not found -->");
    }

    /// Generates documentation for a specific struct
    fn generateStructDoc(self: *Self, name: []const u8) ![]u8 {
        var iter = self.modules.valueIterator();
        while (iter.next()) |module| {
            for (module.structs) |s| {
                if (std.mem.eql(u8, s.name, name)) {
                    const single_module = types.Module{
                        .name = "",
                        .functions = &[_]types.Function{},
                        .structs = &[_]types.Struct{s},
                        .enums = &[_]types.Enum{},
                        .typedefs = &[_]types.Typedef{},
                    };
                    const markdown = try self.markdown_gen.generate(single_module);
                    return try self.allocator.dupe(u8, markdown);
                }
            }
        }

        return try self.allocator.dupe(u8, "<!-- Struct not found -->");
    }

    /// Generates documentation for a specific enum
    fn generateEnumDoc(self: *Self, name: []const u8) ![]u8 {
        var iter = self.modules.valueIterator();
        while (iter.next()) |module| {
            for (module.enums) |e| {
                if (std.mem.eql(u8, e.name, name)) {
                    const single_module = types.Module{
                        .name = "",
                        .functions = &[_]types.Function{},
                        .structs = &[_]types.Struct{},
                        .enums = &[_]types.Enum{e},
                        .typedefs = &[_]types.Typedef{},
                    };
                    const markdown = try self.markdown_gen.generate(single_module);
                    return try self.allocator.dupe(u8, markdown);
                }
            }
        }

        return try self.allocator.dupe(u8, "<!-- Enum not found -->");
    }

    /// Generates documentation for a specific macro
    fn generateMacroDoc(self: *Self, name: []const u8) ![]u8 {
        var iter = self.modules.valueIterator();
        while (iter.next()) |module| {
            for (module.macros) |m| {
                if (std.mem.eql(u8, m.name, name)) {
                    const single_module = types.Module{
                        .name = "",
                        .functions = &[_]types.Function{},
                        .structs = &[_]types.Struct{},
                        .enums = &[_]types.Enum{},
                        .typedefs = &[_]types.Typedef{},
                        .macros = &[_]types.Macro{m},
                    };
                    const markdown = try self.markdown_gen.generate(single_module);
                    return try self.allocator.dupe(u8, markdown);
                }
            }
        }

        return try self.allocator.dupe(u8, "<!-- Macro not found -->");
    }

    /// Gets a cached module or parses the file
    fn getOrParseModule(self: *Self, path: []const u8) !types.Module {
        if (self.modules.get(path)) |module| {
            return module;
        }

        // Resolve path relative to book root
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = if (self.book_root.len > 0)
            try std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ self.book_root, path })
        else
            path;

        // Read and parse file
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            std.debug.print("Error opening {s}: {}\n", .{ full_path, err });
            return types.Module{
                .name = path,
                .functions = &[_]types.Function{},
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
            };
        };
        defer file.close();

        const source = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error reading {s}: {}\n", .{ full_path, err });
            return types.Module{
                .name = path,
                .functions = &[_]types.Function{},
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
            };
        };

        const module = try self.parser.parse(source, path);
        try self.modules.put(path, module);
        return module;
    }
};

/// Entry point for preprocessor mode
pub fn runPreprocessor(allocator: std.mem.Allocator) !void {
    var preprocessor = try Preprocessor.init(allocator);
    defer preprocessor.deinit();
    try preprocessor.run();
}

// Tests
test "find json end" {
    var pp = try Preprocessor.init(std.testing.allocator);
    defer pp.deinit();

    const json1 = "{\"key\": \"value\"}rest";
    try std.testing.expectEqual(@as(?usize, 16), pp.findJsonEnd(json1, 0));

    const json2 = "[1, 2, 3]more";
    try std.testing.expectEqual(@as(?usize, 9), pp.findJsonEnd(json2, 0));

    const json3 = "{\"nested\": {\"a\": 1}}";
    try std.testing.expectEqual(@as(?usize, 20), pp.findJsonEnd(json3, 0));
}

test "process directive - unknown command" {
    var pp = try Preprocessor.init(std.testing.allocator);
    defer pp.deinit();

    const result = try pp.processDirective("unknown arg");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
