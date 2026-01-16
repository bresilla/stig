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
    /// Cached diagnostic metadata for code actions
    diagnostic_metadata: std.ArrayList(DiagnosticMetadata) = .empty,
};

/// Metadata for a diagnostic that enables code action generation
const DiagnosticMetadata = struct {
    /// The diagnostic code (e.g., "W001", "W003")
    code: []const u8,
    /// Line number (0-based)
    line: u32,
    /// Entity name (function, class, etc.)
    entity_name: []const u8,
    /// Entity type
    entity_type: []const u8,
    /// For W003/W004: the missing parameter/tparam name
    missing_name: ?[]const u8 = null,
    /// For E001: the suggested correct name
    suggestion: ?[]const u8 = null,
    /// Function parameters (for generating doc stubs)
    params: []const []const u8 = &[_][]const u8{},
    /// Function return type (for generating doc stubs)
    return_type: ?[]const u8 = null,
    /// Template parameters
    tparams: []const []const u8 = &[_][]const u8{},
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
            entry.value_ptr.diagnostic_metadata.deinit(self.allocator);
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
        } else |err| {
            std.debug.print("LSP: Could not load stig.toml: {}, using defaults\n", .{err});
        }

        // Build test coverage cache if test patterns are configured
        self.buildTestCoverageCache() catch |err| {
            std.debug.print("LSP: Could not build test coverage cache: {}\n", .{err});
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
        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            try self.handleCompletion(id, params);
        } else if (std.mem.eql(u8, method, "textDocument/codeAction")) {
            try self.handleCodeAction(id, params);
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
                    .change = .incremental,
                    .save = .{ .includeText = true },
                },
                .completionProvider = .{
                    .trigger_characters = &[_][]const u8{ "@", "\\" },
                    .resolve_provider = false,
                },
                .codeActionProvider = .{
                    .code_action_kinds = &[_]lsp_types.CodeActionKind{.quickfix},
                },
            },
        };

        var buffer: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        try result.jsonStringify(fbs.writer());

        try self.transport.sendResponse(id, fbs.getWritten());
    }

    /// Handle shutdown request
    fn handleShutdown(self: *Self, id: jsonrpc.JsonId) !void {
        self.shutdown_requested = true;
        try self.transport.sendResponse(id, "null");
    }

    /// Handle textDocument/completion request
    fn handleCompletion(self: *Self, id: jsonrpc.JsonId, params: ?std.json.Value) !void {
        const p = params orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };
        if (p != .object) {
            try self.transport.sendResponse(id, "null");
            return;
        }

        // Get the document URI and position
        const text_doc = p.object.get("textDocument") orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };
        if (text_doc != .object) {
            try self.transport.sendResponse(id, "null");
            return;
        }

        const uri_val = text_doc.object.get("uri") orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };
        if (uri_val != .string) {
            try self.transport.sendResponse(id, "null");
            return;
        }

        // Get document content to check context
        const doc = self.documents.get(uri_val.string) orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };

        // Get position
        const position = p.object.get("position") orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };
        if (position != .object) {
            try self.transport.sendResponse(id, "null");
            return;
        }

        const line_val = position.object.get("line") orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };
        const char_val = position.object.get("character") orelse {
            try self.transport.sendResponse(id, "null");
            return;
        };

        const line: usize = if (line_val == .integer and line_val.integer >= 0) @intCast(line_val.integer) else {
            try self.transport.sendResponse(id, "null");
            return;
        };
        const character: usize = if (char_val == .integer and char_val.integer >= 0) @intCast(char_val.integer) else {
            try self.transport.sendResponse(id, "null");
            return;
        };

        // Check if we're in a documentation comment context
        if (!self.isInDocComment(doc.content, line, character)) {
            try self.transport.sendResponse(id, "null");
            return;
        }

        // Return Doxygen tag completions
        const completion_list = lsp_types.CompletionList{
            .is_incomplete = false,
            .items = &doxygen_completions,
        };

        const json = try completion_list.jsonStringify(self.allocator);
        defer self.allocator.free(json);

        try self.transport.sendResponse(id, json);
    }

    /// Check if the cursor is inside a documentation comment
    fn isInDocComment(self: *Self, content: []const u8, line: usize, character: usize) bool {
        _ = self;
        _ = character;

        // Find the line in content
        var current_line: usize = 0;
        var line_start: usize = 0;

        for (content, 0..) |c, i| {
            if (current_line == line) {
                line_start = i;
                break;
            }
            if (c == '\n') {
                current_line += 1;
            }
        }

        // Find line end
        var line_end = line_start;
        while (line_end < content.len and content[line_end] != '\n') {
            line_end += 1;
        }

        const line_content = content[line_start..line_end];

        // Check if line starts with doc comment markers
        const trimmed = std.mem.trimLeft(u8, line_content, " \t");

        // Doxygen comment styles:
        // /// - C++ triple slash
        // //! - C++ exclamation
        // /** - C-style block start
        // * - Inside C-style block
        // /*! - C-style block with exclamation
        if (std.mem.startsWith(u8, trimmed, "///") or
            std.mem.startsWith(u8, trimmed, "//!") or
            std.mem.startsWith(u8, trimmed, "/**") or
            std.mem.startsWith(u8, trimmed, "/*!") or
            std.mem.startsWith(u8, trimmed, "* ") or
            std.mem.startsWith(u8, trimmed, "*\t") or
            std.mem.eql(u8, trimmed, "*"))
        {
            return true;
        }

        // Also check if we're inside a multi-line block comment
        // by looking backwards for /** or /*!
        var in_block = false;
        var i: usize = line_start;
        while (i > 1) { // Need at least 2 chars to check i-1
            i -= 1;
            if (content[i] == '/' and content[i - 1] == '*') {
                // Found end of block comment before our line
                break;
            }
            if (content[i] == '*' and content[i - 1] == '/') {
                // Found /* - check next char for doc comment indicator
                if (i + 1 < content.len and (content[i + 1] == '!' or content[i + 1] == '*')) {
                    in_block = true;
                }
                break;
            }
            if (i > 1 and content[i] == '*' and content[i - 1] == '*' and content[i - 2] == '/') {
                // Found /** doc comment start
                in_block = true;
                break;
            }
        }

        return in_block;
    }

    /// Handle textDocument/codeAction request
    fn handleCodeAction(self: *Self, id: jsonrpc.JsonId, params: ?std.json.Value) !void {
        const p = params orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        if (p != .object) {
            try self.transport.sendResponse(id, "[]");
            return;
        }

        // Get the document URI
        const text_doc = p.object.get("textDocument") orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        if (text_doc != .object) {
            try self.transport.sendResponse(id, "[]");
            return;
        }

        const uri_val = text_doc.object.get("uri") orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        if (uri_val != .string) {
            try self.transport.sendResponse(id, "[]");
            return;
        }

        // Get the range
        const range_val = p.object.get("range") orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        if (range_val != .object) {
            try self.transport.sendResponse(id, "[]");
            return;
        }

        const start_val = range_val.object.get("start") orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        if (start_val != .object) {
            try self.transport.sendResponse(id, "[]");
            return;
        }

        const line_val = start_val.object.get("line") orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };
        const request_line: u32 = if (line_val == .integer and line_val.integer >= 0 and line_val.integer <= std.math.maxInt(u32)) @intCast(line_val.integer) else {
            try self.transport.sendResponse(id, "[]");
            return;
        };

        // Get document and its diagnostic metadata
        const doc = self.documents.get(uri_val.string) orelse {
            try self.transport.sendResponse(id, "[]");
            return;
        };

        // Find diagnostics that match the requested line
        var actions: std.ArrayList([]const u8) = .empty;
        defer {
            for (actions.items) |a| self.allocator.free(a);
            actions.deinit(self.allocator);
        }

        for (doc.diagnostic_metadata.items) |metadata| {
            // Check if this diagnostic is on or near the requested line
            // LSP lines are 0-based, our lines are 1-based
            const diag_line = if (metadata.line > 0) metadata.line - 1 else 0;
            if (diag_line != request_line) continue;

            // Generate code action based on diagnostic code
            if (try self.generateCodeAction(uri_val.string, doc.content, metadata)) |action_json| {
                try actions.append(self.allocator, action_json);
            }
        }

        // Build response array
        var response: std.ArrayList(u8) = .empty;
        defer response.deinit(self.allocator);

        try response.append(self.allocator, '[');
        for (actions.items, 0..) |action, i| {
            if (i > 0) try response.append(self.allocator, ',');
            try response.appendSlice(self.allocator, action);
        }
        try response.append(self.allocator, ']');

        try self.transport.sendResponse(id, response.items);
    }

    /// Generate a code action for a specific diagnostic
    fn generateCodeAction(self: *Self, uri: []const u8, content: []const u8, metadata: DiagnosticMetadata) !?[]const u8 {
        if (std.mem.eql(u8, metadata.code, "W001")) {
            // No documentation - generate doc stub
            return try self.generateDocStubAction(uri, content, metadata);
        } else if (std.mem.eql(u8, metadata.code, "W003")) {
            // Missing @param - add param tag
            return try self.generateAddParamAction(uri, content, metadata);
        } else if (std.mem.eql(u8, metadata.code, "W005")) {
            // Missing @return - add return tag
            return try self.generateAddReturnAction(uri, content, metadata);
        } else if (std.mem.eql(u8, metadata.code, "E001")) {
            // Wrong param name - suggest fix
            return try self.generateFixParamNameAction(uri, content, metadata);
        }
        return null;
    }

    /// Generate a code action to add a documentation stub
    fn generateDocStubAction(self: *Self, uri: []const u8, content: []const u8, metadata: DiagnosticMetadata) ![]const u8 {
        // Find the line where we need to insert the doc comment
        const insert_line = if (metadata.line > 0) metadata.line - 1 else 0;

        // Find the indentation of the target line
        var line_start: usize = 0;
        var current_line: u32 = 0;
        for (content, 0..) |c, i| {
            if (current_line == insert_line) {
                line_start = i;
                break;
            }
            if (c == '\n') current_line += 1;
        }

        // Get indentation
        var indent_end = line_start;
        while (indent_end < content.len and (content[indent_end] == ' ' or content[indent_end] == '\t')) {
            indent_end += 1;
        }
        const indent = content[line_start..indent_end];

        // Build the doc comment
        var doc_comment: std.ArrayList(u8) = .empty;
        defer doc_comment.deinit(self.allocator);

        try doc_comment.appendSlice(self.allocator, indent);
        try doc_comment.appendSlice(self.allocator, "/// @brief TODO: Add description\n");

        // Add @param for each parameter
        for (metadata.params) |param| {
            try doc_comment.appendSlice(self.allocator, indent);
            try doc_comment.appendSlice(self.allocator, "/// @param ");
            try doc_comment.appendSlice(self.allocator, param);
            try doc_comment.appendSlice(self.allocator, " TODO: Document parameter\n");
        }

        // Add @tparam for each template parameter
        for (metadata.tparams) |tparam| {
            try doc_comment.appendSlice(self.allocator, indent);
            try doc_comment.appendSlice(self.allocator, "/// @tparam ");
            try doc_comment.appendSlice(self.allocator, tparam);
            try doc_comment.appendSlice(self.allocator, " TODO: Document template parameter\n");
        }

        // Add @return if non-void
        if (metadata.return_type) |ret| {
            const trimmed = std.mem.trim(u8, ret, " \t");
            if (!std.mem.eql(u8, trimmed, "void") and trimmed.len > 0) {
                try doc_comment.appendSlice(self.allocator, indent);
                try doc_comment.appendSlice(self.allocator, "/// @return TODO: Document return value\n");
            }
        }

        // Create the text edit
        const edit = lsp_types.TextEdit{
            .range = .{
                .start = .{ .line = insert_line, .character = 0 },
                .end = .{ .line = insert_line, .character = 0 },
            },
            .new_text = doc_comment.items,
        };

        // Create the workspace edit
        const doc_change = lsp_types.WorkspaceEdit.DocumentChange{
            .uri = uri,
            .edits = &[_]lsp_types.TextEdit{edit},
        };

        const workspace_edit = lsp_types.WorkspaceEdit{
            .changes = &[_]lsp_types.WorkspaceEdit.DocumentChange{doc_change},
        };

        // Create the code action
        const action = lsp_types.CodeAction{
            .title = "Add documentation stub",
            .kind = .quickfix,
            .edit = workspace_edit,
            .is_preferred = true,
        };

        return try action.jsonStringify(self.allocator);
    }

    /// Generate a code action to add a missing @param tag
    fn generateAddParamAction(self: *Self, uri: []const u8, content: []const u8, metadata: DiagnosticMetadata) ![]const u8 {
        const param_name = metadata.missing_name orelse return error.MissingParamName;

        // Find the doc comment for this entity and insert after the last @param or @brief
        const insert_pos = try self.findParamInsertPosition(content, metadata.line);

        // Get indentation from the line
        var line_start: usize = 0;
        var current_line: u32 = 0;
        for (content, 0..) |c, i| {
            if (current_line == insert_pos.line) {
                line_start = i;
                break;
            }
            if (c == '\n') current_line += 1;
        }

        var indent_end = line_start;
        while (indent_end < content.len and (content[indent_end] == ' ' or content[indent_end] == '\t')) {
            indent_end += 1;
        }
        const indent = content[line_start..indent_end];

        // Build the new param line
        var new_text: std.ArrayList(u8) = .empty;
        defer new_text.deinit(self.allocator);

        try new_text.appendSlice(self.allocator, "\n");
        try new_text.appendSlice(self.allocator, indent);
        try new_text.appendSlice(self.allocator, "/// @param ");
        try new_text.appendSlice(self.allocator, param_name);
        try new_text.appendSlice(self.allocator, " TODO: Document parameter");

        const edit = lsp_types.TextEdit{
            .range = .{
                .start = .{ .line = insert_pos.line, .character = insert_pos.character },
                .end = .{ .line = insert_pos.line, .character = insert_pos.character },
            },
            .new_text = new_text.items,
        };

        const doc_change = lsp_types.WorkspaceEdit.DocumentChange{
            .uri = uri,
            .edits = &[_]lsp_types.TextEdit{edit},
        };

        const workspace_edit = lsp_types.WorkspaceEdit{
            .changes = &[_]lsp_types.WorkspaceEdit.DocumentChange{doc_change},
        };

        const title = try std.fmt.allocPrint(self.allocator, "Add @param {s}", .{param_name});
        defer self.allocator.free(title);

        const action = lsp_types.CodeAction{
            .title = title,
            .kind = .quickfix,
            .edit = workspace_edit,
        };

        return try action.jsonStringify(self.allocator);
    }

    /// Generate a code action to add a missing @return tag
    fn generateAddReturnAction(self: *Self, uri: []const u8, content: []const u8, metadata: DiagnosticMetadata) ![]const u8 {
        // Find the doc comment for this entity and insert after the last tag
        const insert_pos = try self.findReturnInsertPosition(content, metadata.line);

        // Get indentation from the line
        var line_start: usize = 0;
        var current_line: u32 = 0;
        for (content, 0..) |c, i| {
            if (current_line == insert_pos.line) {
                line_start = i;
                break;
            }
            if (c == '\n') current_line += 1;
        }

        var indent_end = line_start;
        while (indent_end < content.len and (content[indent_end] == ' ' or content[indent_end] == '\t')) {
            indent_end += 1;
        }
        const indent = content[line_start..indent_end];

        // Build the new return line
        var new_text: std.ArrayList(u8) = .empty;
        defer new_text.deinit(self.allocator);

        try new_text.appendSlice(self.allocator, "\n");
        try new_text.appendSlice(self.allocator, indent);
        try new_text.appendSlice(self.allocator, "/// @return TODO: Document return value");

        const edit = lsp_types.TextEdit{
            .range = .{
                .start = .{ .line = insert_pos.line, .character = insert_pos.character },
                .end = .{ .line = insert_pos.line, .character = insert_pos.character },
            },
            .new_text = new_text.items,
        };

        const doc_change = lsp_types.WorkspaceEdit.DocumentChange{
            .uri = uri,
            .edits = &[_]lsp_types.TextEdit{edit},
        };

        const workspace_edit = lsp_types.WorkspaceEdit{
            .changes = &[_]lsp_types.WorkspaceEdit.DocumentChange{doc_change},
        };

        const action = lsp_types.CodeAction{
            .title = "Add @return documentation",
            .kind = .quickfix,
            .edit = workspace_edit,
        };

        return try action.jsonStringify(self.allocator);
    }

    /// Generate a code action to fix a wrong parameter name
    fn generateFixParamNameAction(self: *Self, uri: []const u8, content: []const u8, metadata: DiagnosticMetadata) ![]const u8 {
        const correct_name = metadata.suggestion orelse return error.MissingSuggestion;

        // Extract wrong name from missing_name (set during metadata building) or search in doc
        const wrong_name = metadata.missing_name orelse return error.MissingWrongName;

        const title = try std.fmt.allocPrint(self.allocator, "Change @param {s} to {s}", .{ wrong_name, correct_name });
        defer self.allocator.free(title);

        // Find the wrong parameter name in the doc comment near the diagnostic line
        const search_pattern = try std.fmt.allocPrint(self.allocator, "@param {s}", .{wrong_name});
        defer self.allocator.free(search_pattern);

        // Search for the pattern in lines near the diagnostic
        const diag_line = metadata.line;
        var line_num: u32 = 0;
        var line_start: usize = 0;
        var found_line: ?u32 = null;
        var found_col: u32 = 0;

        for (content, 0..) |c, i| {
            if (c == '\n') {
                // Check if this line is within range of the diagnostic
                if (line_num >= (if (diag_line > 10) diag_line - 10 else 0) and line_num <= diag_line) {
                    const line_content = content[line_start..i];
                    if (std.mem.indexOf(u8, line_content, search_pattern)) |col| {
                        found_line = line_num;
                        // Position at the start of the param name (after "@param ")
                        found_col = @intCast(col + 7);
                    }
                }
                line_num += 1;
                line_start = i + 1;
            }
        }

        if (found_line == null) {
            // Couldn't find exact position - create action without edit
            const action = lsp_types.CodeAction{
                .title = title,
                .kind = .quickfix,
            };
            return try action.jsonStringify(self.allocator);
        }

        // Create text edit to replace the wrong name with correct name
        const edit = lsp_types.TextEdit{
            .range = .{
                .start = .{ .line = found_line.?, .character = found_col },
                .end = .{ .line = found_line.?, .character = found_col + @as(u32, @intCast(wrong_name.len)) },
            },
            .new_text = correct_name,
        };

        const doc_change = lsp_types.WorkspaceEdit.DocumentChange{
            .uri = uri,
            .edits = &[_]lsp_types.TextEdit{edit},
        };

        const workspace_edit = lsp_types.WorkspaceEdit{
            .changes = &[_]lsp_types.WorkspaceEdit.DocumentChange{doc_change},
        };

        const action = lsp_types.CodeAction{
            .title = title,
            .kind = .quickfix,
            .edit = workspace_edit,
        };

        return try action.jsonStringify(self.allocator);
    }

    /// Find the position to insert a new @param tag
    fn findParamInsertPosition(self: *Self, content: []const u8, entity_line: u32) !lsp_types.Position {
        _ = self;
        // Search backwards from entity_line to find the doc comment
        // and find the last @param or @brief line
        var best_line: u32 = if (entity_line > 0) entity_line - 1 else 0;
        var best_char: u32 = 0;

        var current_line: u32 = 0;
        var line_start: usize = 0;

        for (content, 0..) |c, i| {
            if (c == '\n') {
                // Check if this line is a doc comment line before entity_line
                if (current_line < entity_line and current_line >= (if (entity_line > 10) entity_line - 10 else 0)) {
                    const line_content = content[line_start..i];
                    const trimmed = std.mem.trimLeft(u8, line_content, " \t");

                    if (std.mem.startsWith(u8, trimmed, "///") or std.mem.startsWith(u8, trimmed, "*")) {
                        // Check if it's a @param or @brief line
                        if (std.mem.indexOf(u8, trimmed, "@param") != null or
                            std.mem.indexOf(u8, trimmed, "@brief") != null or
                            std.mem.indexOf(u8, trimmed, "@tparam") != null)
                        {
                            best_line = current_line;
                            best_char = @intCast(i - line_start);
                        }
                    }
                }
                current_line += 1;
                line_start = i + 1;
            }
        }

        return .{ .line = best_line, .character = best_char };
    }

    /// Find the position to insert a new @return tag
    fn findReturnInsertPosition(self: *Self, content: []const u8, entity_line: u32) !lsp_types.Position {
        // Similar to findParamInsertPosition but looks for the last doc line
        return self.findParamInsertPosition(content, entity_line);
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
    /// Supports both full and incremental sync modes
    fn handleDidChange(self: *Self, params: ?std.json.Value) !void {
        const p = params orelse return;
        if (p != .object) return;

        const text_doc = p.object.get("textDocument") orelse return;
        if (text_doc != .object) return;

        const uri_val = text_doc.object.get("uri") orelse return;
        if (uri_val != .string) return;

        const changes = p.object.get("contentChanges") orelse return;
        if (changes != .array or changes.array.items.len == 0) return;

        // Get document
        const doc = self.documents.getPtr(uri_val.string) orelse return;

        // Apply each change in order
        for (changes.array.items) |change| {
            if (change != .object) continue;

            const text_val = change.object.get("text") orelse continue;
            if (text_val != .string) continue;

            // Check if this is an incremental change (has range) or full change
            if (change.object.get("range")) |range_val| {
                // Incremental change - apply the edit
                if (range_val != .object) continue;

                const start = range_val.object.get("start") orelse continue;
                const end = range_val.object.get("end") orelse continue;
                if (start != .object or end != .object) continue;

                const start_line = if (start.object.get("line")) |l| (if (l == .integer and l.integer >= 0) @as(usize, @intCast(l.integer)) else continue) else continue;
                const start_char = if (start.object.get("character")) |c| (if (c == .integer and c.integer >= 0) @as(usize, @intCast(c.integer)) else continue) else continue;
                const end_line = if (end.object.get("line")) |l| (if (l == .integer and l.integer >= 0) @as(usize, @intCast(l.integer)) else continue) else continue;
                const end_char = if (end.object.get("character")) |c| (if (c == .integer and c.integer >= 0) @as(usize, @intCast(c.integer)) else continue) else continue;

                // Convert line/character positions to byte offsets
                const start_offset = self.positionToOffset(doc.content, start_line, start_char);
                const end_offset = self.positionToOffset(doc.content, end_line, end_char);

                // Apply the change
                const new_content = try self.applyTextChange(doc.content, start_offset, end_offset, text_val.string);
                self.allocator.free(doc.content);
                doc.content = new_content;
            } else {
                // Full change - replace entire content
                self.allocator.free(doc.content);
                doc.content = try self.allocator.dupe(u8, text_val.string);
            }
        }

        // Run diagnostics on change
        try self.publishDiagnostics(doc.uri, doc.content);
    }

    /// Convert line/character position to byte offset
    fn positionToOffset(self: *Self, content: []const u8, line: usize, character: usize) usize {
        _ = self;
        var current_line: usize = 0;
        var current_char: usize = 0;

        for (content, 0..) |c, i| {
            if (current_line == line and current_char == character) {
                return i;
            }
            if (c == '\n') {
                if (current_line == line) {
                    // Character is beyond end of line, return end of line
                    return i;
                }
                current_line += 1;
                current_char = 0;
            } else {
                current_char += 1;
            }
        }

        // Position is at or beyond end of content
        return content.len;
    }

    /// Apply a text change to content
    fn applyTextChange(self: *Self, content: []const u8, start: usize, end: usize, new_text: []const u8) ![]u8 {
        const before = content[0..@min(start, content.len)];
        const after = if (end < content.len) content[end..] else "";

        const new_len = before.len + new_text.len + after.len;
        const result = try self.allocator.alloc(u8, new_len);

        @memcpy(result[0..before.len], before);
        @memcpy(result[before.len .. before.len + new_text.len], new_text);
        @memcpy(result[before.len + new_text.len ..], after);

        return result;
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
            var metadata = kv.value.diagnostic_metadata;
            metadata.deinit(self.allocator);

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
        var c_parser = self.c_parser orelse {
            std.debug.print("LSP: Parser not initialized, cannot analyze {s}\n", .{file_path});
            return;
        };
        var cpp_parser = self.cpp_parser orelse {
            std.debug.print("LSP: Parser not initialized, cannot analyze {s}\n", .{file_path});
            return;
        };

        const module = if (is_cpp)
            cpp_parser.parse(content, file_path) catch |err| {
                std.debug.print("LSP: Failed to parse C++ file '{s}': {}\n", .{ file_path, err });
                return;
            }
        else
            c_parser.parse(content, file_path) catch |err| {
                std.debug.print("LSP: Failed to parse C file '{s}': {}\n", .{ file_path, err });
                return;
            };

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
            .rules = self.config.lint.rules,
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

        // Build diagnostic metadata for code actions
        try self.buildDiagnosticMetadata(uri, lint_report, &modules);

        // Send diagnostics
        try self.sendDiagnostics(uri, merged);
    }

    /// Build diagnostic metadata from lint report for code action generation
    fn buildDiagnosticMetadata(self: *Self, uri: []const u8, lint_report: lint.LintReport, modules: []const types.Module) !void {
        const doc = self.documents.getPtr(uri) orelse return;

        // Clear existing metadata
        doc.diagnostic_metadata.clearRetainingCapacity();

        // Build a map of entity names to their info for quick lookup
        var entity_info = std.StringHashMap(EntityInfo).init(self.allocator);
        defer entity_info.deinit();

        for (modules) |module| {
            for (module.functions) |func| {
                var param_names: std.ArrayList([]const u8) = .empty;
                for (func.params) |p| {
                    try param_names.append(self.allocator, p.name);
                }
                var tparam_names: std.ArrayList([]const u8) = .empty;
                for (func.template_params) |tp| {
                    try tparam_names.append(self.allocator, tp.name);
                }
                try entity_info.put(func.name, .{
                    .params = param_names.items,
                    .tparams = tparam_names.items,
                    .return_type = func.return_type,
                    .line = func.location.line,
                });
            }
            for (module.classes) |class| {
                for (class.methods) |method| {
                    var param_names: std.ArrayList([]const u8) = .empty;
                    for (method.params) |p| {
                        try param_names.append(self.allocator, p.name);
                    }
                    const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class.name, method.name });
                    try entity_info.put(full_name, .{
                        .params = param_names.items,
                        .tparams = &[_][]const u8{},
                        .return_type = method.return_type,
                        .line = method.location.line,
                    });
                }
            }
        }

        // Convert lint issues to metadata
        for (lint_report.issues.items) |issue| {
            var metadata = DiagnosticMetadata{
                .code = issue.code,
                .line = issue.line,
                .entity_name = issue.entity_name,
                .entity_type = issue.entity_type,
            };

            // Extract additional info based on issue type
            if (std.mem.eql(u8, issue.code, "W003") or std.mem.eql(u8, issue.code, "W004")) {
                // Missing @param or @tparam - extract the name from message
                // Message format: "missing @param for 'name'" or "missing @tparam for 'name'"
                if (std.mem.indexOf(u8, issue.message, "'")) |start| {
                    if (std.mem.indexOfPos(u8, issue.message, start + 1, "'")) |end| {
                        metadata.missing_name = issue.message[start + 1 .. end];
                    }
                }
            } else if (std.mem.eql(u8, issue.code, "E001")) {
                // Wrong param name - extract wrong name from message and suggestion
                // Message format: "@param 'wrong_name' does not match any parameter"
                if (std.mem.indexOf(u8, issue.message, "'")) |start| {
                    if (std.mem.indexOfPos(u8, issue.message, start + 1, "'")) |end| {
                        metadata.missing_name = issue.message[start + 1 .. end];
                    }
                }
                // Suggestion format: "Did you mean 'correct_name'?"
                if (issue.suggestion) |sug| {
                    if (std.mem.indexOf(u8, sug, "'")) |start| {
                        if (std.mem.indexOfPos(u8, sug, start + 1, "'")) |end| {
                            metadata.suggestion = sug[start + 1 .. end];
                        }
                    }
                }
            }

            // Add entity info if available
            if (entity_info.get(issue.entity_name)) |info| {
                metadata.params = info.params;
                metadata.tparams = info.tparams;
                metadata.return_type = info.return_type;
            }

            try doc.diagnostic_metadata.append(self.allocator, metadata);
        }
    }

    const EntityInfo = struct {
        params: []const []const u8,
        tparams: []const []const u8,
        return_type: []const u8,
        line: u32,
    };

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
        var c_parser = self.c_parser orelse {
            std.debug.print("LSP: Parser not initialized, cannot run test coverage analysis\n", .{});
            return;
        };
        var cpp_parser = self.cpp_parser orelse {
            std.debug.print("LSP: Parser not initialized, cannot run test coverage analysis\n", .{});
            return;
        };

        var modules: std.ArrayList(types.Module) = .empty;
        defer modules.deinit(self.allocator);

        for (expanded_sources.items) |input_file| {
            if (!isHeaderFile(input_file)) continue;

            const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
                std.debug.print("LSP: Cannot open '{s}': {}\n", .{ input_file, err });
                continue;
            };
            defer file.close();

            const source = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
                std.debug.print("LSP: Cannot read '{s}': {}\n", .{ input_file, err });
                continue;
            };
            defer self.allocator.free(source);

            const is_cpp = isCppFile(input_file);
            const module = if (is_cpp)
                cpp_parser.parse(source, input_file) catch |err| {
                    std.debug.print("LSP: Cannot parse '{s}': {}\n", .{ input_file, err });
                    continue;
                }
            else
                c_parser.parse(source, input_file) catch |err| {
                    std.debug.print("LSP: Cannot parse '{s}': {}\n", .{ input_file, err });
                    continue;
                };

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

// =============================================================================
// Doxygen Tag Completions
// =============================================================================

/// Doxygen documentation tag completion items
const doxygen_completions = [_]lsp_types.CompletionItem{
    // Brief description
    .{
        .label = "@brief",
        .kind = .keyword,
        .detail = "Brief description",
        .documentation = "Starts a paragraph that serves as a brief description.",
        .insert_text = "@brief ${1:description}",
        .insert_text_format = .snippet,
    },
    // Parameters
    .{
        .label = "@param",
        .kind = .keyword,
        .detail = "Parameter documentation",
        .documentation = "Documents a function parameter.",
        .insert_text = "@param ${1:name} ${2:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@param[in]",
        .kind = .keyword,
        .detail = "Input parameter",
        .documentation = "Documents an input parameter.",
        .insert_text = "@param[in] ${1:name} ${2:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@param[out]",
        .kind = .keyword,
        .detail = "Output parameter",
        .documentation = "Documents an output parameter.",
        .insert_text = "@param[out] ${1:name} ${2:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@param[in,out]",
        .kind = .keyword,
        .detail = "Input/output parameter",
        .documentation = "Documents a parameter used for both input and output.",
        .insert_text = "@param[in,out] ${1:name} ${2:description}",
        .insert_text_format = .snippet,
    },
    // Template parameters
    .{
        .label = "@tparam",
        .kind = .keyword,
        .detail = "Template parameter",
        .documentation = "Documents a template parameter.",
        .insert_text = "@tparam ${1:name} ${2:description}",
        .insert_text_format = .snippet,
    },
    // Return value
    .{
        .label = "@return",
        .kind = .keyword,
        .detail = "Return value",
        .documentation = "Documents the return value of a function.",
        .insert_text = "@return ${1:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@returns",
        .kind = .keyword,
        .detail = "Return value (alias)",
        .documentation = "Documents the return value of a function.",
        .insert_text = "@returns ${1:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@retval",
        .kind = .keyword,
        .detail = "Specific return value",
        .documentation = "Documents a specific return value.",
        .insert_text = "@retval ${1:value} ${2:description}",
        .insert_text_format = .snippet,
    },
    // Exceptions
    .{
        .label = "@throws",
        .kind = .keyword,
        .detail = "Exception documentation",
        .documentation = "Documents an exception that may be thrown.",
        .insert_text = "@throws ${1:exception_type} ${2:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@throw",
        .kind = .keyword,
        .detail = "Exception documentation (alias)",
        .documentation = "Documents an exception that may be thrown.",
        .insert_text = "@throw ${1:exception_type} ${2:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@exception",
        .kind = .keyword,
        .detail = "Exception documentation (alias)",
        .documentation = "Documents an exception that may be thrown.",
        .insert_text = "@exception ${1:exception_type} ${2:description}",
        .insert_text_format = .snippet,
    },
    // Cross-references
    .{
        .label = "@see",
        .kind = .keyword,
        .detail = "See also reference",
        .documentation = "Adds a cross-reference to related documentation.",
        .insert_text = "@see ${1:reference}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@ref",
        .kind = .keyword,
        .detail = "Reference link",
        .documentation = "Creates a reference to another documented entity.",
        .insert_text = "@ref ${1:name}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@copydoc",
        .kind = .keyword,
        .detail = "Copy documentation",
        .documentation = "Copies documentation from another entity.",
        .insert_text = "@copydoc ${1:name}",
        .insert_text_format = .snippet,
    },
    // Notes and warnings
    .{
        .label = "@note",
        .kind = .keyword,
        .detail = "Note block",
        .documentation = "Adds a note paragraph.",
        .insert_text = "@note ${1:text}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@warning",
        .kind = .keyword,
        .detail = "Warning block",
        .documentation = "Adds a warning paragraph.",
        .insert_text = "@warning ${1:text}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@attention",
        .kind = .keyword,
        .detail = "Attention block",
        .documentation = "Adds an attention paragraph.",
        .insert_text = "@attention ${1:text}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@remark",
        .kind = .keyword,
        .detail = "Remark block",
        .documentation = "Adds a remark paragraph.",
        .insert_text = "@remark ${1:text}",
        .insert_text_format = .snippet,
    },
    // Deprecation
    .{
        .label = "@deprecated",
        .kind = .keyword,
        .detail = "Deprecation notice",
        .documentation = "Marks an entity as deprecated.",
        .insert_text = "@deprecated ${1:reason}",
        .insert_text_format = .snippet,
    },
    // Pre/post conditions
    .{
        .label = "@pre",
        .kind = .keyword,
        .detail = "Precondition",
        .documentation = "Documents a precondition.",
        .insert_text = "@pre ${1:condition}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@post",
        .kind = .keyword,
        .detail = "Postcondition",
        .documentation = "Documents a postcondition.",
        .insert_text = "@post ${1:condition}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@invariant",
        .kind = .keyword,
        .detail = "Invariant",
        .documentation = "Documents an invariant condition.",
        .insert_text = "@invariant ${1:condition}",
        .insert_text_format = .snippet,
    },
    // Code examples
    .{
        .label = "@code",
        .kind = .keyword,
        .detail = "Code block start",
        .documentation = "Starts a code block.",
        .insert_text = "@code{.${1:cpp}}\n${2:code}\n@endcode",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@endcode",
        .kind = .keyword,
        .detail = "Code block end",
        .documentation = "Ends a code block.",
        .insert_text = "@endcode",
        .insert_text_format = .plain_text,
    },
    .{
        .label = "@example",
        .kind = .keyword,
        .detail = "Example file",
        .documentation = "References an example file.",
        .insert_text = "@example ${1:filename}",
        .insert_text_format = .snippet,
    },
    // Versioning
    .{
        .label = "@since",
        .kind = .keyword,
        .detail = "Since version",
        .documentation = "Documents when an entity was introduced.",
        .insert_text = "@since ${1:version}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@version",
        .kind = .keyword,
        .detail = "Version info",
        .documentation = "Documents the version.",
        .insert_text = "@version ${1:version}",
        .insert_text_format = .snippet,
    },
    // Authors
    .{
        .label = "@author",
        .kind = .keyword,
        .detail = "Author info",
        .documentation = "Documents the author.",
        .insert_text = "@author ${1:name}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@authors",
        .kind = .keyword,
        .detail = "Authors info",
        .documentation = "Documents multiple authors.",
        .insert_text = "@authors ${1:names}",
        .insert_text_format = .snippet,
    },
    // Grouping
    .{
        .label = "@defgroup",
        .kind = .keyword,
        .detail = "Define group",
        .documentation = "Defines a documentation group.",
        .insert_text = "@defgroup ${1:name} ${2:title}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@addtogroup",
        .kind = .keyword,
        .detail = "Add to group",
        .documentation = "Adds entities to a group.",
        .insert_text = "@addtogroup ${1:name}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@ingroup",
        .kind = .keyword,
        .detail = "In group",
        .documentation = "Marks an entity as belonging to a group.",
        .insert_text = "@ingroup ${1:name}",
        .insert_text_format = .snippet,
    },
    // Other
    .{
        .label = "@details",
        .kind = .keyword,
        .detail = "Detailed description",
        .documentation = "Starts the detailed description.",
        .insert_text = "@details ${1:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@todo",
        .kind = .keyword,
        .detail = "TODO item",
        .documentation = "Adds a TODO item.",
        .insert_text = "@todo ${1:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@bug",
        .kind = .keyword,
        .detail = "Bug description",
        .documentation = "Documents a known bug.",
        .insert_text = "@bug ${1:description}",
        .insert_text_format = .snippet,
    },
    .{
        .label = "@file",
        .kind = .keyword,
        .detail = "File documentation",
        .documentation = "Documents the current file.",
        .insert_text = "@file ${1:filename}",
        .insert_text_format = .snippet,
    },
};
