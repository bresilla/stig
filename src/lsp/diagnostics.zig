const std = @import("std");
const lsp_types = @import("types.zig");
const lint = @import("../lint.zig");
const coverage = @import("../coverage.zig");

/// Converts lint issues and coverage reports to LSP diagnostics
pub const DiagnosticConverter = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Convert a LintIssue to an LSP Diagnostic
    pub fn fromLintIssue(self: *Self, issue: lint.LintIssue) lsp_types.Diagnostic {
        _ = self;
        // LSP uses 0-based lines, our lint uses 1-based
        const line: u32 = if (issue.line > 0) issue.line - 1 else 0;

        return lsp_types.Diagnostic{
            .range = .{
                .start = .{ .line = line, .character = 0 },
                .end = .{ .line = line, .character = 999 }, // End of line
            },
            .severity = switch (issue.severity) {
                .@"error" => .@"error",
                .warning => .warning,
                .info => .information,
            },
            .code = issue.code,
            .source = "stig",
            .message = issue.message,
        };
    }

    /// Convert a MissingDoc to an LSP Diagnostic
    pub fn fromMissingDoc(self: *Self, item: coverage.MissingDoc) lsp_types.Diagnostic {
        _ = self;
        // LSP uses 0-based lines, our coverage uses 1-based
        const line: u32 = if (item.line > 0) item.line - 1 else 0;

        // Determine severity based on issue type
        const severity: lsp_types.DiagnosticSeverity = if (std.mem.eql(u8, item.issue, "no documentation"))
            .warning
        else
            .information;

        // Determine code based on issue type
        const code: []const u8 = if (std.mem.eql(u8, item.issue, "no documentation"))
            "W001"
        else if (std.mem.startsWith(u8, item.issue, "missing @param"))
            "W003"
        else if (std.mem.startsWith(u8, item.issue, "missing @tparam"))
            "W004"
        else if (std.mem.eql(u8, item.issue, "missing @return"))
            "W005"
        else
            "W000";

        return lsp_types.Diagnostic{
            .range = .{
                .start = .{ .line = line, .character = 0 },
                .end = .{ .line = line, .character = 999 },
            },
            .severity = severity,
            .code = code,
            .source = "stig",
            .message = item.issue,
        };
    }

    /// Convert all lint issues for a specific file to LSP diagnostics
    pub fn convertLintReport(self: *Self, report: lint.LintReport, file_path: []const u8) ![]lsp_types.Diagnostic {
        var diagnostics: std.ArrayList(lsp_types.Diagnostic) = .empty;
        errdefer diagnostics.deinit(self.allocator);

        for (report.issues.items) |issue| {
            if (std.mem.eql(u8, issue.file, file_path)) {
                try diagnostics.append(self.allocator, self.fromLintIssue(issue));
            }
        }

        return diagnostics.toOwnedSlice(self.allocator);
    }

    /// Convert all coverage issues for a specific file to LSP diagnostics
    pub fn convertCoverageReport(self: *Self, report: coverage.CoverageReport, file_path: []const u8) ![]lsp_types.Diagnostic {
        var diagnostics: std.ArrayList(lsp_types.Diagnostic) = .empty;
        errdefer diagnostics.deinit(self.allocator);

        for (report.missing_items.items) |item| {
            if (std.mem.eql(u8, item.file, file_path)) {
                try diagnostics.append(self.allocator, self.fromMissingDoc(item));
            }
        }

        return diagnostics.toOwnedSlice(self.allocator);
    }

    /// Merge lint and coverage diagnostics, removing duplicates
    pub fn mergeDiagnostics(self: *Self, lint_diags: []const lsp_types.Diagnostic, coverage_diags: []const lsp_types.Diagnostic) ![]lsp_types.Diagnostic {
        var merged: std.ArrayList(lsp_types.Diagnostic) = .empty;
        errdefer merged.deinit(self.allocator);

        // Add all lint diagnostics
        for (lint_diags) |diag| {
            try merged.append(self.allocator, diag);
        }

        // Add coverage diagnostics that aren't duplicates
        outer: for (coverage_diags) |cov_diag| {
            for (lint_diags) |lint_diag| {
                // Consider it a duplicate if same line and similar message
                if (cov_diag.range.start.line == lint_diag.range.start.line) {
                    if (std.mem.eql(u8, cov_diag.message, lint_diag.message)) {
                        continue :outer;
                    }
                }
            }
            try merged.append(self.allocator, cov_diag);
        }

        return merged.toOwnedSlice(self.allocator);
    }

    /// Free diagnostics array
    pub fn freeDiagnostics(self: *Self, diagnostics: []lsp_types.Diagnostic) void {
        self.allocator.free(diagnostics);
    }
};

/// Group diagnostics by file URI
pub fn groupByFile(allocator: std.mem.Allocator, lint_report: lint.LintReport, coverage_report: coverage.CoverageReport) !std.StringHashMap([]lsp_types.Diagnostic) {
    var converter = DiagnosticConverter.init(allocator);
    var result = std.StringHashMap([]lsp_types.Diagnostic).init(allocator);
    errdefer {
        var iter = result.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }

    // Collect all unique files
    var files = std.StringHashMap(void).init(allocator);
    defer files.deinit();

    for (lint_report.issues.items) |issue| {
        try files.put(issue.file, {});
    }
    for (coverage_report.missing_items.items) |item| {
        try files.put(item.file, {});
    }

    // Convert diagnostics for each file
    var file_iter = files.keyIterator();
    while (file_iter.next()) |file_ptr| {
        const file = file_ptr.*;

        const lint_diags = try converter.convertLintReport(lint_report, file);
        defer converter.freeDiagnostics(lint_diags);

        const cov_diags = try converter.convertCoverageReport(coverage_report, file);
        defer converter.freeDiagnostics(cov_diags);

        const merged = try converter.mergeDiagnostics(lint_diags, cov_diags);

        // Convert file path to URI
        const uri = try lsp_types.pathToUri(allocator, file);
        try result.put(uri, merged);
    }

    return result;
}

// Tests
test "convert lint issue to diagnostic" {
    var converter = DiagnosticConverter.init(std.testing.allocator);

    const issue = lint.LintIssue{
        .file = "test.h",
        .line = 10,
        .entity_name = "test_func",
        .entity_type = "function",
        .severity = .warning,
        .code = "W001",
        .message = "no documentation",
    };

    const diag = converter.fromLintIssue(issue);

    try std.testing.expectEqual(@as(u32, 9), diag.range.start.line); // 0-based
    try std.testing.expectEqual(lsp_types.DiagnosticSeverity.warning, diag.severity.?);
    try std.testing.expectEqualStrings("W001", diag.code.?);
    try std.testing.expectEqualStrings("stig", diag.source.?);
}

test "convert missing doc to diagnostic" {
    var converter = DiagnosticConverter.init(std.testing.allocator);

    const item = coverage.MissingDoc{
        .file = "test.h",
        .entity_name = "test_func",
        .entity_type = "function",
        .issue = "no documentation",
        .line = 15,
    };

    const diag = converter.fromMissingDoc(item);

    try std.testing.expectEqual(@as(u32, 14), diag.range.start.line); // 0-based
    try std.testing.expectEqual(lsp_types.DiagnosticSeverity.warning, diag.severity.?);
}
