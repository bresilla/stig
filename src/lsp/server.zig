const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");
const lsp_types = @import("types.zig");
const diagnostics_mod = @import("diagnostics.zig");
const CParser = @import("../parser/c.zig").CParser;
const CppParser = @import("../parser/cpp.zig").CppParser;
const types = @import("../model/types.zig");
const lint = @import("../lint.zig");
const coverage = @import("../coverage.zig");
const testcov = @import("../testcov.zig");
const xref = @import("../xref.zig");
const config_mod = @import("../config.zig");

/// Document state for open files
const DocumentState = struct {
    uri: []const u8,
    content: []const u8,
    version: i64,
};

/// Cached test coverage data (computed once on startup/config change)
const TestCoverageCache = struct {
    report: ?testcov.TestCoverageReport = null,
    symbol_table: ?*xref.SymbolTable = null,

    pub fn deinit(self: *TestCoverageCache, allocator: std.mem.Allocator) void {
        if (self.report) |*r| r.deinit();
        if (self.symbol_table) |st| {
            st.deinit();
            allocator.destroy(st);
        }
    }
};

/// LSP Server for stig documentation checker
pub const Server = struct {
    allocator: std.mem.Allocator,
    transport: jsonrpc.Transport,
    initialized: bool = false,
    shutdown_requested: bool = false,
    documents: std.StringHashMap(DocumentState),
    config: config_mod.Config,
    c_parser: ?CParser = null,
    cpp_parser: ?CppParser = null,
    test_coverage_cache: TestCoverageCache = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .transport = jsonrpc.Transport.init(allocator),
            .documents = std.StringHashMap(DocumentState).init(allocator),
            .config = config_mod.Config{},
        };
    }

    pub fn deinit(self: *Self) void {
        // Free document states
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.uri);
            self.allocator.free(entry.value_ptr.content);
        }
        self.documents.deinit();

        if (self.c_parser) |*p| p.deinit();
        if (self.cpp_parser) |*p| p.deinit();

        self.test_coverage_cache.deinit(self.allocator);
        self.transport.deinit();
    }

    /// Run the LSP server main loop
    pub fn run(self: *Self) !void {
        // Initialize parsers
        self.c_parser = try CParser.init(self.allocator);
        self.cpp_parser = try CppParser.init(self.allocator);

        // Load config if available
        if (config_mod.loadFromFile(self.allocator, "stig.toml")) |result| {
            self.config = result.config;
            // Note: We're not storing the loader, so config strings are borrowed
        } else |_| {
            // Use defaults
        }

        // Build test coverage cache if test patterns are configured
        self.buildTestCoverageCache() catch {
            // Ignore errors - test coverage is optional
        };

        // Main message loop
        while (!self.shutdown_requested) {
            const msg = self.transport.readMessage() catch |err| {
                if (err == error.EndOfStream) break;
                continue;
            };

            if (msg) |message| {
                var m = message;
                defer self.transport.freeMessage(&m);
                try self.handleMessage(m);
            } else {
                break; // EOF
            }
        }
    }

    /// Handle a single LSP message
    fn handleMessage(self: *Self, msg: jsonrpc.Message) !void {
        const method = msg.method orelse return;

        if (msg.isRequest()) {
            try self.handleRequest(msg.id.?, method, msg.params);
        } else if (msg.isNotification()) {
            try self.handleNotification(method, msg.params);
        }
    }

    /// Handle LSP requests (require response)
    fn handleRequest(self: *Self, id: jsonrpc.JsonId, method: []const u8, params: ?std.json.Value) !void {
        if (std.mem.eql(u8, method, "initialize")) {
            try self.handleInitialize(id, params);
        } else if (std.mem.eql(u8, method, "shutdown")) {
            try self.handleShutdown(id);
        } else {
            // Unknown method
            try self.transport.sendError(id, .method_not_found, "Method not found");
        }
    }

    /// Handle LSP notifications (no response)
    fn handleNotification(self: *Self, method: []const u8, params: ?std.json.Value) !void {
        if (std.mem.eql(u8, method, "initialized")) {
            // Client acknowledged initialization
            self.initialized = true;
        } else if (std.mem.eql(u8, method, "exit")) {
            self.shutdown_requested = true;
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            try self.handleDidOpen(params);
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            try self.handleDidChange(params);
        } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
            try self.handleDidSave(params);
        } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
            try self.handleDidClose(params);
        }
    }

    /// Handle initialize request
    fn handleInitialize(self: *Self, id: jsonrpc.JsonId, params: ?std.json.Value) !void {
        _ = params;

        // Build response
        const result = lsp_types.InitializeResult{
            .capabilities = .{
                .textDocumentSync = .{
                    .openClose = true,
                    .change = .full,
                    .save = .{ .includeText = true },
                },
            },
        };

        var buffer: [500]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        try result.jsonStringify(fbs.writer());

        try self.transport.sendResponse(id, fbs.getWritten());
    }

    /// Handle shutdown request
    fn handleShutdown(self: *Self, id: jsonrpc.JsonId) !void {
        self.shutdown_requested = true;
        try self.transport.sendResponse(id, "null");
    }

    /// Handle textDocument/didOpen notification
    fn handleDidOpen(self: *Self, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        const text_val = text_doc.object.get("text") orelse return;
        const version_val = text_doc.object.get("version") orelse return;

        if (uri_val != .string or text_val != .string) return;

        const uri = try self.allocator.dupe(u8, uri_val.string);
        const content = try self.allocator.dupe(u8, text_val.string);
        const version: i64 = if (version_val == .integer) version_val.integer else 0;

        // Store document
        const key = try self.allocator.dupe(u8, uri);
        try self.documents.put(key, .{
            .uri = uri,
            .content = content,
            .version = version,
        });

        // Run diagnostics
        try self.publishDiagnostics(uri, content);
    }

    /// Handle textDocument/didChange notification
    fn handleDidChange(self: *Self, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        if (uri_val != .string) return;

        const changes = p.object.get("contentChanges") orelse return;
        if (changes != .array or changes.array.items.len == 0) return;

        // Get the full text from the last change (we use full sync)
        const last_change = changes.array.items[changes.array.items.len - 1];
        if (last_change != .object) return;

        const text_val = last_change.object.get("text") orelse return;
        if (text_val != .string) return;

        // Update document
        if (self.documents.getPtr(uri_val.string)) |doc| {
            self.allocator.free(doc.content);
            doc.content = try self.allocator.dupe(u8, text_val.string);

            // Run diagnostics on change
            try self.publishDiagnostics(doc.uri, doc.content);
        }
    }

    /// Handle textDocument/didSave notification
    fn handleDidSave(self: *Self, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        if (uri_val != .string) return;

        // If text is included, update and diagnose
        if (p.object.get("text")) |text_val| {
            if (text_val == .string) {
                if (self.documents.getPtr(uri_val.string)) |doc| {
                    self.allocator.free(doc.content);
                    doc.content = try self.allocator.dupe(u8, text_val.string);
                    try self.publishDiagnostics(doc.uri, doc.content);
                }
            }
        } else {
            // Re-run diagnostics with existing content
            if (self.documents.get(uri_val.string)) |doc| {
                try self.publishDiagnostics(doc.uri, doc.content);
            }
        }
    }

    /// Handle textDocument/didClose notification
    fn handleDidClose(self: *Self, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        if (uri_val != .string) return;

        // Remove document and clear diagnostics
        if (self.documents.fetchRemove(uri_val.string)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.uri);
            self.allocator.free(kv.value.content);

            // Clear diagnostics by publishing empty array
            try self.sendDiagnostics(uri_val.string, &[_]lsp_types.Diagnostic{});
        }
    }

    /// Run analysis and publish diagnostics for a document
    fn publishDiagnostics(self: *Self, uri: []const u8, content: []const u8) !void {
        // Convert URI to file path
        const file_path = try lsp_types.uriToPath(self.allocator, uri);
        defer self.allocator.free(file_path);

        // Only check header files for documentation
        // Implementation files (.cpp, .cc, .cxx) should not have documentation comments
        if (!isHeaderFile(file_path)) {
            // Send empty diagnostics to clear any previous diagnostics
            try self.sendDiagnostics(uri, &[_]lsp_types.Diagnostic{});
            return;
        }

        // Determine if C or C++ file
        const is_cpp = isCppFile(file_path);

        // Parse the file
        var c_parser = self.c_parser orelse return;
        var cpp_parser = self.cpp_parser orelse return;

        const module = if (is_cpp)
            cpp_parser.parse(content, file_path) catch return
        else
            c_parser.parse(content, file_path) catch return;

        const modules = [_]types.Module{module};

        // Run lint checks
        const lint_config = lint.LintConfig{
            .enabled = self.config.lint.enabled,
            .max_brief_length = self.config.lint.max_brief_length,
            .require_brief = self.config.lint.require_brief,
            .require_param_docs = self.config.lint.require_param_docs,
            .require_return_docs = self.config.lint.require_return_docs,
            .require_tparam_docs = self.config.lint.require_tparam_docs,
            .check_cross_references = self.config.lint.check_cross_references,
            .require_brief_period = self.config.lint.require_brief_period,
            .exclude_patterns = self.config.lint.exclude_patterns,
        };

        var linter = lint.Linter.init(self.allocator, lint_config);

        // Build symbol table for cross-reference checking
        var symbol_table = xref.SymbolTable.init(self.allocator);
        defer symbol_table.deinit();
        try symbol_table.buildFromModules(&modules);
        linter.setSymbolTable(&symbol_table);

        var lint_report = try linter.lint(&modules);
        defer lint_report.deinit();

        // Run coverage analysis
        const coverage_config = coverage.CoverageConfig{
            .require_param_docs = self.config.coverage.require_param_docs,
            .require_return_docs = self.config.coverage.require_return_docs,
            .require_tparam_docs = self.config.coverage.require_tparam_docs,
            .exclude_patterns = self.config.coverage.exclude_patterns,
        };

        var coverage_report = try coverage.analyze(self.allocator, &modules, coverage_config);
        defer coverage_report.deinit();

        // Convert to LSP diagnostics
        var converter = diagnostics_mod.DiagnosticConverter.init(self.allocator);

        const lint_diags = try converter.convertLintReport(lint_report, file_path);
        defer converter.freeDiagnostics(lint_diags);

        const cov_diags = try converter.convertCoverageReport(coverage_report, file_path);
        defer converter.freeDiagnostics(cov_diags);

        var merged = try converter.mergeDiagnostics(lint_diags, cov_diags);
        defer converter.freeDiagnostics(merged);

        // Add test coverage diagnostics if available
        if (self.test_coverage_cache.report) |report| {
            const test_diags = try converter.convertTestCoverageReport(report, file_path);
            defer converter.freeDiagnostics(test_diags);

            // Merge test coverage diagnostics
            const all_diags = try converter.mergeDiagnostics(merged, test_diags);
            converter.freeDiagnostics(merged);
            merged = all_diags;
        }

        // Send diagnostics
        try self.sendDiagnostics(uri, merged);
    }

    /// Build test coverage cache by scanning test files
    fn buildTestCoverageCache(self: *Self) !void {
        // Get test file patterns from config
        var test_patterns = self.config.test_coverage.test_patterns;
        if (test_patterns.len == 0) {
            // Try default patterns
            test_patterns = &[_][]const u8{ "test/**/*.cpp", "tests/**/*.cpp" };
        }

        // Get source patterns
        const source_patterns = self.config.input_patterns;
        if (source_patterns.len == 0) {
            // No sources configured, skip test coverage
            return;
        }

        // Expand source patterns and parse headers
        var expanded_sources: std.ArrayList([]const u8) = .empty;
        defer {
            for (expanded_sources.items) |f| self.allocator.free(f);
            expanded_sources.deinit(self.allocator);
        }

        for (source_patterns) |pattern| {
            if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
                try expandGlob(self.allocator, pattern, &expanded_sources);
            } else {
                const path_copy = try self.allocator.dupe(u8, pattern);
                try expanded_sources.append(self.allocator, path_copy);
            }
        }

        if (expanded_sources.items.len == 0) return;

        // Expand test patterns
        var expanded_tests: std.ArrayList([]const u8) = .empty;
        defer {
            for (expanded_tests.items) |f| self.allocator.free(f);
            expanded_tests.deinit(self.allocator);
        }

        for (test_patterns) |pattern| {
            if (std.mem.indexOfAny(u8, pattern, "*?[")) |_| {
                try expandGlob(self.allocator, pattern, &expanded_tests);
            } else {
                const path_copy = try self.allocator.dupe(u8, pattern);
                try expanded_tests.append(self.allocator, path_copy);
            }
        }

        if (expanded_tests.items.len == 0) return;

        // Parse source files
        var c_parser = self.c_parser orelse return;
        var cpp_parser = self.cpp_parser orelse return;

        var modules: std.ArrayList(types.Module) = .empty;
        defer modules.deinit(self.allocator);

        for (expanded_sources.items) |input_file| {
            if (!isHeaderFile(input_file)) continue;

            const file = std.fs.cwd().openFile(input_file, .{}) catch continue;
            defer file.close();

            const source = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch continue;
            defer self.allocator.free(source);

            const is_cpp = isCppFile(input_file);
            const module = if (is_cpp)
                cpp_parser.parse(source, input_file) catch continue
            else
                c_parser.parse(source, input_file) catch continue;

            try modules.append(self.allocator, module);
        }

        if (modules.items.len == 0) return;

        // Build symbol table
        const symbol_table = try self.allocator.create(xref.SymbolTable);
        symbol_table.* = xref.SymbolTable.init(self.allocator);
        try symbol_table.buildFromModules(modules.items);

        // Run test coverage analysis
        var analyzer = testcov.TestCoverageAnalyzer.init(self.allocator, symbol_table);
        defer analyzer.deinit();

        const report = try analyzer.analyzeTestFiles(expanded_tests.items);

        // Store in cache
        self.test_coverage_cache.symbol_table = symbol_table;
        self.test_coverage_cache.report = report;
    }

    /// Send diagnostics notification to client
    fn sendDiagnostics(self: *Self, uri: []const u8, diags: []const lsp_types.Diagnostic) !void {
        const params = lsp_types.PublishDiagnosticsParams{
            .uri = uri,
            .diagnostics = diags,
        };

        const params_json = try params.jsonStringify(self.allocator);
        defer self.allocator.free(params_json);

        try self.transport.sendNotification("textDocument/publishDiagnostics", params_json);
    }
};

/// Check if a file is a C/C++ header file that should be documented
/// Following standardese and doxygen conventions, only header files should
/// contain documentation comments. Implementation files (.cpp, .cc, .cxx) are excluded.
fn isHeaderFile(filename: []const u8) bool {
    // C headers
    if (std.mem.endsWith(u8, filename, ".h")) return true;

    // C++ headers
    const cpp_header_extensions = [_][]const u8{ ".hpp", ".hxx", ".hh", ".H" };
    for (cpp_header_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
}

/// Check if a file is a C++ file (for parser selection)
fn isCppFile(filename: []const u8) bool {
    const cpp_extensions = [_][]const u8{ ".cpp", ".cxx", ".cc", ".hpp", ".hxx", ".hh", ".C", ".H" };
    for (cpp_extensions) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }
    return false;
}

/// Expands a glob pattern to matching file paths
fn expandGlob(allocator: std.mem.Allocator, pattern: []const u8, results: *std.ArrayList([]const u8)) !void {
    // Check for recursive pattern (**)
    if (std.mem.indexOf(u8, pattern, "**")) |double_star_pos| {
        const prefix = if (double_star_pos > 0 and pattern[double_star_pos - 1] == '/')
            pattern[0 .. double_star_pos - 1]
        else if (double_star_pos > 0)
            pattern[0..double_star_pos]
        else
            ".";

        const suffix_start = double_star_pos + 2;
        const suffix = if (suffix_start >= pattern.len)
            "*"
        else if (pattern[suffix_start] == '/')
            pattern[suffix_start + 1 ..]
        else
            pattern[suffix_start..];

        const file_pattern = if (suffix.len > 0 and suffix[0] == '.') blk: {
            var buf: [256]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, "*{s}", .{suffix}) catch suffix;
            break :blk result;
        } else suffix;

        try expandRecursive(allocator, prefix, file_pattern, results);
    } else {
        const last_sep = std.mem.lastIndexOfScalar(u8, pattern, '/');
        const dir_path = if (last_sep) |idx| pattern[0..idx] else ".";
        const file_pattern = if (last_sep) |idx| pattern[idx + 1 ..] else pattern;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            if (globMatch(file_pattern, entry.name)) {
                const full_path = if (last_sep != null)
                    try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name })
                else
                    try allocator.dupe(u8, entry.name);

                try results.append(allocator, full_path);
            }
        }
    }
}

/// Recursively expand directories and match files
fn expandRecursive(allocator: std.mem.Allocator, base_dir: []const u8, file_pattern: []const u8, results: *std.ArrayList([]const u8)) !void {
    var dir = std.fs.cwd().openDir(base_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full_path = if (std.mem.eql(u8, base_dir, "."))
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_dir, entry.name });

        if (entry.kind == .directory) {
            try expandRecursive(allocator, full_path, file_pattern, results);
            allocator.free(full_path);
        } else if (entry.kind == .file) {
            if (globMatch(file_pattern, entry.name)) {
                try results.append(allocator, full_path);
            } else {
                allocator.free(full_path);
            }
        } else {
            allocator.free(full_path);
        }
    }
}

/// Simple glob pattern matching (supports * and ?)
fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_pi: ?usize = null;
    var star_ni: usize = 0;

    while (ni < name.len) {
        if (pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == name[ni])) {
            pi += 1;
            ni += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_pi = pi;
            star_ni = ni;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_ni += 1;
            ni = star_ni;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') {
        pi += 1;
    }

    return pi == pattern.len;
}

/// Entry point for running the LSP server
pub fn runServer(allocator: std.mem.Allocator) !void {
    var server = Server.init(allocator);
    defer server.deinit();
    try server.run();
}
