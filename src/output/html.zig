const std = @import("std");
const types = @import("../model/types.zig");

/// Single-page HTML output generator for Stig documentation
pub const HtmlGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,
    title: []const u8 = "API Documentation",

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        self.title = title;
    }

    /// Generates a single-page HTML document for all modules
    pub fn generate(self: *Self, modules: []const types.Module) ![]const u8 {
        self.buffer.clearRetainingCapacity();

        // HTML header with embedded CSS
        try self.writeHeader();

        // Sidebar with TOC
        try self.writeSidebar(modules);

        // Main content
        try self.writeString("<main>\n");

        for (modules) |module| {
            try self.writeModule(module);
        }

        try self.writeString("</main>\n");

        // Embedded JavaScript for search/theme
        try self.writeScript();

        // Close HTML
        try self.writeString("</body>\n</html>\n");

        return self.buffer.items;
    }

    fn writeHeader(self: *Self) !void {
        try self.writeString(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\<meta charset="UTF-8">
            \\<meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\<title>
        );
        try self.escapeHtml(self.title);
        try self.writeString(
            \\</title>
            \\<style>
        );
        try self.writeCSS();
        try self.writeString(
            \\</style>
            \\</head>
            \\<body>
            \\
        );
    }

    fn writeCSS(self: *Self) !void {
        try self.writeString(
            \\:root {
            \\  --bg-color: #ffffff;
            \\  --text-color: #333333;
            \\  --code-bg: #f5f5f5;
            \\  --link-color: #0066cc;
            \\  --sidebar-bg: #f8f9fa;
            \\  --border-color: #dee2e6;
            \\  --heading-color: #1a1a1a;
            \\  --muted-color: #6c757d;
            \\}
            \\[data-theme="dark"] {
            \\  --bg-color: #1a1a2e;
            \\  --text-color: #eaeaea;
            \\  --code-bg: #16213e;
            \\  --link-color: #4da6ff;
            \\  --sidebar-bg: #0f0f23;
            \\  --border-color: #333;
            \\  --heading-color: #ffffff;
            \\  --muted-color: #a0a0a0;
            \\}
            \\* { box-sizing: border-box; margin: 0; padding: 0; }
            \\body {
            \\  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            \\  background: var(--bg-color);
            \\  color: var(--text-color);
            \\  display: flex;
            \\  line-height: 1.6;
            \\}
            \\nav {
            \\  width: 280px;
            \\  height: 100vh;
            \\  position: fixed;
            \\  overflow-y: auto;
            \\  background: var(--sidebar-bg);
            \\  border-right: 1px solid var(--border-color);
            \\  padding: 1rem;
            \\}
            \\nav h2 {
            \\  font-size: 1.1rem;
            \\  margin-bottom: 0.5rem;
            \\  color: var(--heading-color);
            \\}
            \\main {
            \\  margin-left: 280px;
            \\  padding: 2rem 3rem;
            \\  max-width: 960px;
            \\  width: calc(100% - 280px);
            \\}
            \\h1 {
            \\  font-size: 2rem;
            \\  margin-top: 0;
            \\  margin-bottom: 1.5rem;
            \\  color: var(--heading-color);
            \\  border-bottom: 2px solid var(--border-color);
            \\  padding-bottom: 0.5rem;
            \\}
            \\h2 {
            \\  font-size: 1.5rem;
            \\  margin-top: 2rem;
            \\  margin-bottom: 1rem;
            \\  color: var(--heading-color);
            \\}
            \\h3 {
            \\  font-size: 1.2rem;
            \\  margin-top: 1.5rem;
            \\  margin-bottom: 0.75rem;
            \\  color: var(--heading-color);
            \\}
            \\h3 code {
            \\  font-size: 1.1rem;
            \\  background: var(--code-bg);
            \\  padding: 0.2rem 0.5rem;
            \\  border-radius: 4px;
            \\}
            \\p { margin-bottom: 1rem; }
            \\pre {
            \\  background: var(--code-bg);
            \\  padding: 1rem;
            \\  border-radius: 6px;
            \\  overflow-x: auto;
            \\  margin-bottom: 1rem;
            \\  border: 1px solid var(--border-color);
            \\}
            \\code {
            \\  font-family: 'SF Mono', 'Fira Code', 'Consolas', 'Monaco', monospace;
            \\  font-size: 0.9em;
            \\}
            \\:not(pre) > code {
            \\  background: var(--code-bg);
            \\  padding: 0.15rem 0.4rem;
            \\  border-radius: 3px;
            \\}
            \\a { color: var(--link-color); text-decoration: none; }
            \\a:hover { text-decoration: underline; }
            \\.search-box { margin-bottom: 1rem; }
            \\.search-box input {
            \\  width: 100%;
            \\  padding: 0.5rem 0.75rem;
            \\  border: 1px solid var(--border-color);
            \\  border-radius: 6px;
            \\  background: var(--bg-color);
            \\  color: var(--text-color);
            \\  font-size: 0.9rem;
            \\}
            \\.search-box input:focus {
            \\  outline: none;
            \\  border-color: var(--link-color);
            \\}
            \\.toc { list-style: none; }
            \\.toc li { margin: 0.2rem 0; }
            \\.toc a {
            \\  display: block;
            \\  padding: 0.25rem 0.5rem;
            \\  border-radius: 4px;
            \\  font-size: 0.9rem;
            \\}
            \\.toc a:hover {
            \\  background: var(--code-bg);
            \\  text-decoration: none;
            \\}
            \\.toc-section {
            \\  font-weight: 600;
            \\  color: var(--muted-color);
            \\  font-size: 0.75rem;
            \\  text-transform: uppercase;
            \\  letter-spacing: 0.05em;
            \\  margin-top: 1rem;
            \\  margin-bottom: 0.5rem;
            \\  padding-left: 0.5rem;
            \\}
            \\.theme-toggle {
            \\  cursor: pointer;
            \\  padding: 0.5rem 1rem;
            \\  margin-bottom: 1rem;
            \\  background: var(--code-bg);
            \\  border: 1px solid var(--border-color);
            \\  border-radius: 6px;
            \\  color: var(--text-color);
            \\  font-size: 0.9rem;
            \\  width: 100%;
            \\}
            \\.theme-toggle:hover {
            \\  border-color: var(--link-color);
            \\}
            \\blockquote {
            \\  border-left: 4px solid var(--link-color);
            \\  margin: 1rem 0;
            \\  padding: 0.5rem 1rem;
            \\  background: var(--code-bg);
            \\  border-radius: 0 6px 6px 0;
            \\}
            \\.entity { margin-bottom: 2.5rem; }
            \\hr {
            \\  border: none;
            \\  border-top: 1px solid var(--border-color);
            \\  margin: 2rem 0;
            \\}
            \\.params-list, .fields-list, .values-list {
            \\  list-style: none;
            \\  margin: 0.5rem 0 1rem 0;
            \\}
            \\.params-list li, .fields-list li, .values-list li {
            \\  margin: 0.4rem 0;
            \\  padding-left: 1rem;
            \\}
            \\.label {
            \\  font-weight: 600;
            \\  color: var(--heading-color);
            \\  margin-top: 1rem;
            \\  margin-bottom: 0.5rem;
            \\}
            \\.deprecated {
            \\  background: #fff3cd;
            \\  border: 1px solid #ffc107;
            \\  border-radius: 6px;
            \\  padding: 0.75rem 1rem;
            \\  margin-bottom: 1rem;
            \\}
            \\[data-theme="dark"] .deprecated {
            \\  background: #332701;
            \\  border-color: #665200;
            \\}
            \\.note {
            \\  background: #d1ecf1;
            \\  border: 1px solid #0c5460;
            \\  border-radius: 6px;
            \\  padding: 0.75rem 1rem;
            \\  margin-bottom: 1rem;
            \\}
            \\[data-theme="dark"] .note {
            \\  background: #0a3d47;
            \\  border-color: #17a2b8;
            \\}
            \\.warning {
            \\  background: #f8d7da;
            \\  border: 1px solid #721c24;
            \\  border-radius: 6px;
            \\  padding: 0.75rem 1rem;
            \\  margin-bottom: 1rem;
            \\}
            \\[data-theme="dark"] .warning {
            \\  background: #3d1014;
            \\  border-color: #dc3545;
            \\}
            \\@media (max-width: 768px) {
            \\  nav {
            \\    width: 100%;
            \\    height: auto;
            \\    position: relative;
            \\    border-right: none;
            \\    border-bottom: 1px solid var(--border-color);
            \\  }
            \\  main {
            \\    margin-left: 0;
            \\    width: 100%;
            \\    padding: 1rem;
            \\  }
            \\  body { flex-direction: column; }
            \\}
            \\
        );
    }

    fn writeSidebar(self: *Self, modules: []const types.Module) !void {
        try self.writeString("<nav>\n");
        try self.writeString("<button class=\"theme-toggle\" onclick=\"toggleTheme()\">Toggle Theme</button>\n");
        try self.writeString("<div class=\"search-box\"><input type=\"text\" id=\"search\" placeholder=\"Search...\" onkeyup=\"search()\"></div>\n");
        try self.writeString("<h2>");
        try self.escapeHtml(self.title);
        try self.writeString("</h2>\n");
        try self.writeString("<ul class=\"toc\">\n");

        for (modules) |module| {
            // Module header
            try self.writeString("<li class=\"toc-section\">");
            try self.escapeHtml(module.name);
            try self.writeString("</li>\n");

            // Functions
            if (module.functions.len > 0) {
                for (module.functions) |func| {
                    try self.writeString("<li><a href=\"#fn-");
                    try self.escapeHtml(func.name);
                    try self.writeString("\">");
                    try self.escapeHtml(func.name);
                    try self.writeString("()</a></li>\n");
                }
            }

            // Classes
            if (module.classes.len > 0) {
                for (module.classes) |class| {
                    try self.writeString("<li><a href=\"#class-");
                    try self.escapeHtml(class.name);
                    try self.writeString("\">");
                    try self.escapeHtml(class.name);
                    try self.writeString("</a></li>\n");
                }
            }

            // Structs
            if (module.structs.len > 0) {
                for (module.structs) |s| {
                    try self.writeString("<li><a href=\"#struct-");
                    try self.escapeHtml(s.name);
                    try self.writeString("\">");
                    try self.escapeHtml(s.name);
                    try self.writeString("</a></li>\n");
                }
            }

            // Enums
            if (module.enums.len > 0) {
                for (module.enums) |e| {
                    try self.writeString("<li><a href=\"#enum-");
                    try self.escapeHtml(e.name);
                    try self.writeString("\">");
                    try self.escapeHtml(e.name);
                    try self.writeString("</a></li>\n");
                }
            }

            // Typedefs
            if (module.typedefs.len > 0) {
                for (module.typedefs) |td| {
                    try self.writeString("<li><a href=\"#typedef-");
                    try self.escapeHtml(td.name);
                    try self.writeString("\">");
                    try self.escapeHtml(td.name);
                    try self.writeString("</a></li>\n");
                }
            }

            // Macros
            if (module.macros.len > 0) {
                for (module.macros) |macro| {
                    try self.writeString("<li><a href=\"#macro-");
                    try self.escapeHtml(macro.name);
                    try self.writeString("\">");
                    try self.escapeHtml(macro.name);
                    try self.writeString("</a></li>\n");
                }
            }
        }

        try self.writeString("</ul>\n</nav>\n");
    }

    fn writeModule(self: *Self, module: types.Module) !void {
        try self.writeString("<h1 id=\"module-");
        try self.escapeHtml(module.name);
        try self.writeString("\">");
        try self.escapeHtml(module.name);
        try self.writeString("</h1>\n");

        // File documentation
        if (module.file_doc) |file_doc| {
            if (file_doc.brief) |brief| {
                try self.writeString("<p>");
                try self.escapeHtml(brief);
                try self.writeString("</p>\n");
            }
            if (file_doc.details) |details| {
                try self.writeString("<p>");
                try self.escapeHtml(details);
                try self.writeString("</p>\n");
            }
        }

        // Functions
        if (module.functions.len > 0) {
            try self.writeString("<h2>Functions</h2>\n");
            for (module.functions) |func| {
                try self.writeFunction(func);
            }
        }

        // Classes
        if (module.classes.len > 0) {
            try self.writeString("<h2>Classes</h2>\n");
            for (module.classes) |class| {
                try self.writeClass(class);
            }
        }

        // Structs
        if (module.structs.len > 0) {
            try self.writeString("<h2>Structures</h2>\n");
            for (module.structs) |s| {
                try self.writeStruct(s);
            }
        }

        // Enums
        if (module.enums.len > 0) {
            try self.writeString("<h2>Enumerations</h2>\n");
            for (module.enums) |e| {
                try self.writeEnum(e);
            }
        }

        // Typedefs
        if (module.typedefs.len > 0) {
            try self.writeString("<h2>Type Definitions</h2>\n");
            for (module.typedefs) |td| {
                try self.writeTypedef(td);
            }
        }

        // Macros
        if (module.macros.len > 0) {
            try self.writeString("<h2>Macros</h2>\n");
            for (module.macros) |macro| {
                try self.writeMacro(macro);
            }
        }

        // Type Aliases
        if (module.type_aliases.len > 0) {
            try self.writeString("<h2>Type Aliases</h2>\n");
            for (module.type_aliases) |alias| {
                try self.writeTypeAlias(alias);
            }
        }

        // Concepts
        if (module.concepts.len > 0) {
            try self.writeString("<h2>Concepts</h2>\n");
            for (module.concepts) |concept| {
                try self.writeConcept(concept);
            }
        }
    }

    fn writeFunction(self: *Self, func: types.Function) !void {
        try self.writeString("<div class=\"entity\" id=\"fn-");
        try self.escapeHtml(func.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(func.name);
        try self.writeString("</code></h3>\n");

        // Signature
        try self.writeString("<pre><code>");
        // Template params
        if (func.template_params.len > 0) {
            try self.writeString("template&lt;");
            for (func.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.escapeHtml(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.escapeHtml(param.name);
                if (param.default_value) |default| {
                    try self.writeString(" = ");
                    try self.escapeHtml(default);
                }
            }
            try self.writeString("&gt;\n");
        }
        try self.escapeHtml(func.return_type);
        try self.writeString(" ");
        try self.escapeHtml(func.name);
        try self.writeString("(");
        for (func.params, 0..) |param, i| {
            if (i > 0) try self.writeString(", ");
            try self.escapeHtml(param.type_str);
            try self.writeString(" ");
            try self.escapeHtml(param.name);
        }
        try self.writeString(");</code></pre>\n");

        // Documentation
        if (func.doc) |doc| {
            try self.writeDocString(doc);

            // Parameters
            if (doc.params.len > 0) {
                try self.writeString("<p class=\"label\">Parameters:</p>\n<ul class=\"params-list\">\n");
                for (doc.params) |param| {
                    try self.writeString("<li><code>");
                    try self.escapeHtml(param.name);
                    try self.writeString("</code>: ");
                    try self.escapeHtml(param.description);
                    try self.writeString("</li>\n");
                }
                try self.writeString("</ul>\n");
            }

            // Returns
            if (doc.returns) |ret| {
                try self.writeString("<p class=\"label\">Returns:</p>\n<p>");
                try self.escapeHtml(ret);
                try self.writeString("</p>\n");
            }

            // Exceptions
            if (doc.exceptions.len > 0) {
                try self.writeString("<p class=\"label\">Throws:</p>\n<ul class=\"params-list\">\n");
                for (doc.exceptions) |exc| {
                    try self.writeString("<li><code>");
                    try self.escapeHtml(exc.exception_type);
                    try self.writeString("</code>: ");
                    try self.escapeHtml(exc.description);
                    try self.writeString("</li>\n");
                }
                try self.writeString("</ul>\n");
            }

            // See also
            if (doc.see_also.len > 0) {
                try self.writeString("<p class=\"label\">See also:</p>\n<p>");
                for (doc.see_also, 0..) |ref, i| {
                    if (i > 0) try self.writeString(", ");
                    try self.writeString("<code>");
                    try self.escapeHtml(ref);
                    try self.writeString("</code>");
                }
                try self.writeString("</p>\n");
            }
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeClass(self: *Self, class: types.Class) !void {
        try self.writeString("<div class=\"entity\" id=\"class-");
        try self.escapeHtml(class.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(class.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>");
        if (class.template_params.len > 0) {
            try self.writeString("template&lt;");
            for (class.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.escapeHtml(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.escapeHtml(param.name);
            }
            try self.writeString("&gt;\n");
        }
        try self.writeString("class ");
        try self.escapeHtml(class.name);
        if (class.base_classes.len > 0) {
            try self.writeString(" : ");
            for (class.base_classes, 0..) |base, i| {
                if (i > 0) try self.writeString(", ");
                switch (base.access) {
                    .public => try self.writeString("public "),
                    .protected => try self.writeString("protected "),
                    .private => try self.writeString("private "),
                }
                if (base.is_virtual) try self.writeString("virtual ");
                try self.escapeHtml(base.name);
            }
        }
        try self.writeString(" { ... };</code></pre>\n");

        // Documentation
        if (class.doc) |doc| {
            try self.writeDocString(doc);
        }

        // Public methods
        var has_public_methods = false;
        for (class.methods) |method| {
            if (method.access == .public) {
                has_public_methods = true;
                break;
            }
        }
        if (has_public_methods) {
            try self.writeString("<p class=\"label\">Public Methods:</p>\n<ul class=\"params-list\">\n");
            for (class.methods) |method| {
                if (method.access == .public) {
                    try self.writeString("<li><code>");
                    try self.escapeHtml(method.return_type);
                    try self.writeString(" ");
                    try self.escapeHtml(method.name);
                    try self.writeString("(");
                    for (method.params, 0..) |param, i| {
                        if (i > 0) try self.writeString(", ");
                        try self.escapeHtml(param.type_str);
                    }
                    try self.writeString(")</code>");
                    if (method.doc) |doc| {
                        if (doc.brief) |brief| {
                            try self.writeString(" - ");
                            try self.escapeHtml(brief);
                        }
                    }
                    try self.writeString("</li>\n");
                }
            }
            try self.writeString("</ul>\n");
        }

        // Public fields
        var has_public_fields = false;
        for (class.fields) |field| {
            if (field.access == .public) {
                has_public_fields = true;
                break;
            }
        }
        if (has_public_fields) {
            try self.writeString("<p class=\"label\">Public Fields:</p>\n<ul class=\"fields-list\">\n");
            for (class.fields) |field| {
                if (field.access == .public) {
                    try self.writeString("<li><code>");
                    try self.escapeHtml(field.type_str);
                    try self.writeString(" ");
                    try self.escapeHtml(field.name);
                    try self.writeString("</code>");
                    if (field.doc) |doc| {
                        try self.writeString(" - ");
                        try self.escapeHtml(doc);
                    }
                    try self.writeString("</li>\n");
                }
            }
            try self.writeString("</ul>\n");
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeStruct(self: *Self, s: types.Struct) !void {
        try self.writeString("<div class=\"entity\" id=\"struct-");
        try self.escapeHtml(s.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(s.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>struct ");
        try self.escapeHtml(s.name);
        try self.writeString(" {\n");
        for (s.fields) |field| {
            try self.writeString("    ");
            try self.escapeHtml(field.type_str);
            try self.writeString(" ");
            try self.escapeHtml(field.name);
            try self.writeString(";\n");
        }
        try self.writeString("};</code></pre>\n");

        // Documentation
        if (s.doc) |doc| {
            try self.writeDocString(doc);
        }

        // Fields
        if (s.fields.len > 0) {
            try self.writeString("<p class=\"label\">Fields:</p>\n<ul class=\"fields-list\">\n");
            for (s.fields) |field| {
                try self.writeString("<li><code>");
                try self.escapeHtml(field.name);
                try self.writeString("</code> (<code>");
                try self.escapeHtml(field.type_str);
                try self.writeString("</code>)");
                if (field.doc) |doc| {
                    try self.writeString(": ");
                    try self.escapeHtml(doc);
                }
                try self.writeString("</li>\n");
            }
            try self.writeString("</ul>\n");
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeEnum(self: *Self, e: types.Enum) !void {
        try self.writeString("<div class=\"entity\" id=\"enum-");
        try self.escapeHtml(e.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(e.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>enum ");
        try self.escapeHtml(e.name);
        try self.writeString(" {\n");
        for (e.values) |val| {
            try self.writeString("    ");
            try self.escapeHtml(val.name);
            if (val.value) |v| {
                var buf: [32]u8 = undefined;
                const num_str = std.fmt.bufPrint(&buf, " = {d}", .{v}) catch "";
                try self.writeString(num_str);
            }
            try self.writeString(",\n");
        }
        try self.writeString("};</code></pre>\n");

        // Documentation
        if (e.doc) |doc| {
            try self.writeDocString(doc);
        }

        // Values
        var has_docs = false;
        for (e.values) |val| {
            if (val.doc != null) {
                has_docs = true;
                break;
            }
        }
        if (has_docs) {
            try self.writeString("<p class=\"label\">Values:</p>\n<ul class=\"values-list\">\n");
            for (e.values) |val| {
                try self.writeString("<li><code>");
                try self.escapeHtml(val.name);
                try self.writeString("</code>");
                if (val.doc) |doc| {
                    try self.writeString(": ");
                    try self.escapeHtml(doc);
                }
                try self.writeString("</li>\n");
            }
            try self.writeString("</ul>\n");
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeTypedef(self: *Self, td: types.Typedef) !void {
        try self.writeString("<div class=\"entity\" id=\"typedef-");
        try self.escapeHtml(td.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(td.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>typedef ");
        try self.escapeHtml(td.underlying);
        try self.writeString(" ");
        try self.escapeHtml(td.name);
        try self.writeString(";</code></pre>\n");

        // Documentation
        if (td.doc) |doc| {
            try self.writeDocString(doc);
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeMacro(self: *Self, macro: types.Macro) !void {
        try self.writeString("<div class=\"entity\" id=\"macro-");
        try self.escapeHtml(macro.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(macro.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>#define ");
        try self.escapeHtml(macro.name);
        if (macro.params) |params| {
            try self.writeString("(");
            for (params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.escapeHtml(param);
            }
            try self.writeString(")");
        }
        if (macro.body.len > 0) {
            try self.writeString(" ");
            try self.escapeHtml(macro.body);
        }
        try self.writeString("</code></pre>\n");

        // Documentation
        if (macro.doc) |doc| {
            try self.writeDocString(doc);

            // Parameters
            if (doc.params.len > 0) {
                try self.writeString("<p class=\"label\">Parameters:</p>\n<ul class=\"params-list\">\n");
                for (doc.params) |param| {
                    try self.writeString("<li><code>");
                    try self.escapeHtml(param.name);
                    try self.writeString("</code>: ");
                    try self.escapeHtml(param.description);
                    try self.writeString("</li>\n");
                }
                try self.writeString("</ul>\n");
            }
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeTypeAlias(self: *Self, alias: types.TypeAlias) !void {
        try self.writeString("<div class=\"entity\" id=\"alias-");
        try self.escapeHtml(alias.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(alias.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>");
        if (alias.template_params.len > 0) {
            try self.writeString("template&lt;");
            for (alias.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.escapeHtml(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.escapeHtml(param.name);
            }
            try self.writeString("&gt;\n");
        }
        try self.writeString("using ");
        try self.escapeHtml(alias.name);
        try self.writeString(" = ");
        try self.escapeHtml(alias.underlying_type);
        try self.writeString(";</code></pre>\n");

        // Documentation
        if (alias.docstring) |doc| {
            try self.writeDocString(doc);
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeConcept(self: *Self, concept: types.Concept) !void {
        try self.writeString("<div class=\"entity\" id=\"concept-");
        try self.escapeHtml(concept.name);
        try self.writeString("\">\n");
        try self.writeString("<h3><code>");
        try self.escapeHtml(concept.name);
        try self.writeString("</code></h3>\n");

        // Synopsis
        try self.writeString("<pre><code>");
        if (concept.template_params.len > 0) {
            try self.writeString("template&lt;");
            for (concept.template_params, 0..) |param, i| {
                if (i > 0) try self.writeString(", ");
                try self.escapeHtml(param.kind);
                if (param.is_variadic) try self.writeString("...");
                try self.writeString(" ");
                try self.escapeHtml(param.name);
            }
            try self.writeString("&gt;\n");
        }
        try self.writeString("concept ");
        try self.escapeHtml(concept.name);
        try self.writeString(" = ");
        try self.escapeHtml(concept.constraint);
        try self.writeString(";</code></pre>\n");

        // Documentation
        if (concept.docstring) |doc| {
            try self.writeDocString(doc);
        }

        try self.writeString("<hr>\n</div>\n");
    }

    fn writeDocString(self: *Self, doc: types.DocString) !void {
        // Brief
        if (doc.brief) |brief| {
            try self.writeString("<p>");
            try self.escapeHtml(brief);
            try self.writeString("</p>\n");
        }

        // Details
        if (doc.details) |details| {
            try self.writeString("<p>");
            try self.escapeHtml(details);
            try self.writeString("</p>\n");
        }

        // Deprecated
        if (doc.deprecated) |dep| {
            try self.writeString("<div class=\"deprecated\"><strong>Deprecated:</strong> ");
            try self.escapeHtml(dep);
            try self.writeString("</div>\n");
        }

        // Notes
        for (doc.notes) |note| {
            try self.writeString("<div class=\"note\"><strong>Note:</strong> ");
            try self.escapeHtml(note);
            try self.writeString("</div>\n");
        }

        // Warnings
        for (doc.warnings) |warning| {
            try self.writeString("<div class=\"warning\"><strong>Warning:</strong> ");
            try self.escapeHtml(warning);
            try self.writeString("</div>\n");
        }

        // Since
        if (doc.since) |since| {
            try self.writeString("<p><strong>Since:</strong> ");
            try self.escapeHtml(since);
            try self.writeString("</p>\n");
        }

        // Author
        if (doc.author) |author| {
            try self.writeString("<p><strong>Author:</strong> ");
            try self.escapeHtml(author);
            try self.writeString("</p>\n");
        }

        // Examples
        if (doc.examples.len > 0) {
            try self.writeString("<p class=\"label\">Examples:</p>\n");
            for (doc.examples) |example| {
                try self.writeString("<pre><code>");
                try self.escapeHtml(example);
                try self.writeString("</code></pre>\n");
            }
        }
    }

    fn writeScript(self: *Self) !void {
        try self.writeString(
            \\<script>
            \\function toggleTheme() {
            \\  const html = document.documentElement;
            \\  const current = html.getAttribute('data-theme');
            \\  const newTheme = current === 'dark' ? 'light' : 'dark';
            \\  html.setAttribute('data-theme', newTheme);
            \\  localStorage.setItem('theme', newTheme);
            \\}
            \\function search() {
            \\  const query = document.getElementById('search').value.toLowerCase();
            \\  const items = document.querySelectorAll('.toc li:not(.toc-section)');
            \\  items.forEach(item => {
            \\    const link = item.querySelector('a');
            \\    if (link) {
            \\      const text = link.textContent.toLowerCase();
            \\      item.style.display = text.includes(query) ? '' : 'none';
            \\    }
            \\  });
            \\}
            \\// Load saved theme
            \\(function() {
            \\  const savedTheme = localStorage.getItem('theme');
            \\  if (savedTheme) {
            \\    document.documentElement.setAttribute('data-theme', savedTheme);
            \\  } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            \\    document.documentElement.setAttribute('data-theme', 'dark');
            \\  }
            \\})();
            \\</script>
            \\
        );
    }

    fn writeString(self: *Self, s: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, s);
    }

    fn escapeHtml(self: *Self, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '<' => try self.buffer.appendSlice(self.allocator, "&lt;"),
                '>' => try self.buffer.appendSlice(self.allocator, "&gt;"),
                '&' => try self.buffer.appendSlice(self.allocator, "&amp;"),
                '"' => try self.buffer.appendSlice(self.allocator, "&quot;"),
                '\'' => try self.buffer.appendSlice(self.allocator, "&#39;"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
    }
};

// Tests
test "html generator basic" {
    const allocator = std.testing.allocator;
    var gen = HtmlGenerator.init(allocator);
    defer gen.deinit();

    const modules = [_]types.Module{
        .{
            .name = "test.h",
            .functions = &[_]types.Function{},
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    const output = try gen.generate(&modules);
    try std.testing.expect(std.mem.indexOf(u8, output, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.h") != null);
}

test "html escape" {
    const allocator = std.testing.allocator;
    var gen = HtmlGenerator.init(allocator);
    defer gen.deinit();

    try gen.escapeHtml("<script>alert('xss')</script>");
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;", gen.buffer.items);
}
