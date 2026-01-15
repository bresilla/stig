const std = @import("std");
const types = @import("model/types.zig");
const xref = @import("xref.zig");
const CppParser = @import("parser/cpp.zig").CppParser;
const cli = @import("cli.zig");

/// Test coverage analysis - tracks which documented API entities are tested
/// by parsing test files and cross-referencing with the symbol table.
/// Information about a tested entity
pub const TestedEntity = struct {
    name: []const u8,
    kind: xref.SymbolKind,
    test_file: []const u8,
    test_name: ?[]const u8,
    call_count: usize,
};

/// Information about an untested entity
pub const UntestedEntity = struct {
    name: []const u8,
    kind: xref.SymbolKind,
    source_file: []const u8,
    line: u32,
};

/// Test coverage statistics
pub const CoverageStats = struct {
    total_entities: usize = 0,
    tested_entities: usize = 0,
    functions_total: usize = 0,
    functions_tested: usize = 0,
    classes_total: usize = 0,
    classes_tested: usize = 0,
    methods_total: usize = 0,
    methods_tested: usize = 0,

    pub fn percentage(self: CoverageStats) f64 {
        if (self.total_entities == 0) return 100.0;
        return @as(f64, @floatFromInt(self.tested_entities)) / @as(f64, @floatFromInt(self.total_entities)) * 100.0;
    }

    pub fn functions_percentage(self: CoverageStats) f64 {
        if (self.functions_total == 0) return 100.0;
        return @as(f64, @floatFromInt(self.functions_tested)) / @as(f64, @floatFromInt(self.functions_total)) * 100.0;
    }

    pub fn classes_percentage(self: CoverageStats) f64 {
        if (self.classes_total == 0) return 100.0;
        return @as(f64, @floatFromInt(self.classes_tested)) / @as(f64, @floatFromInt(self.classes_total)) * 100.0;
    }

    pub fn methods_percentage(self: CoverageStats) f64 {
        if (self.methods_total == 0) return 100.0;
        return @as(f64, @floatFromInt(self.methods_tested)) / @as(f64, @floatFromInt(self.methods_total)) * 100.0;
    }
};

/// Complete test coverage report
pub const TestCoverageReport = struct {
    stats: CoverageStats,
    tested: std.ArrayList(TestedEntity),
    untested: std.ArrayList(UntestedEntity),
    test_files_parsed: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestCoverageReport {
        return .{
            .stats = .{},
            .tested = .empty,
            .untested = .empty,
            .test_files_parsed = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestCoverageReport) void {
        self.tested.deinit(self.allocator);
        self.untested.deinit(self.allocator);
    }
};

/// Test coverage analyzer
pub const TestCoverageAnalyzer = struct {
    allocator: std.mem.Allocator,
    symbol_table: *xref.SymbolTable,
    /// Set of entity names that have been called/used in tests
    tested_symbols: std.StringHashMap(TestedInfo),
    /// Current test name being analyzed
    current_test: ?[]const u8,
    /// Current test file being analyzed
    current_file: []const u8,

    const TestedInfo = struct {
        test_file: []const u8,
        test_name: ?[]const u8,
        call_count: usize,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, symbol_table: *xref.SymbolTable) Self {
        return .{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .tested_symbols = std.StringHashMap(TestedInfo).init(allocator),
            .current_test = null,
            .current_file = "",
        };
    }

    pub fn deinit(self: *Self) void {
        self.tested_symbols.deinit();
    }

    /// Analyzes test files to find which API entities are being tested
    pub fn analyzeTestFiles(self: *Self, test_files: []const []const u8) !TestCoverageReport {
        var report = TestCoverageReport.init(self.allocator);
        errdefer report.deinit();

        // Parse each test file and extract function calls
        for (test_files) |test_file| {
            self.current_file = test_file;
            try self.parseTestFile(test_file);
            report.test_files_parsed += 1;
        }

        // Build the report by comparing with symbol table
        try self.buildReport(&report);

        return report;
    }

    /// Parses a test file and extracts function/method calls
    fn parseTestFile(self: *Self, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.debug.print("Warning: Cannot open test file '{s}': {}\n", .{ file_path, err });
            return;
        };
        defer file.close();

        const source = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Warning: Cannot read test file '{s}': {}\n", .{ file_path, err });
            return;
        };
        defer self.allocator.free(source);

        // Simple lexical analysis to find:
        // 1. STIG_TEST(name) declarations
        // 2. Function/method calls
        try self.extractTestCalls(source, file_path);
    }

    /// Extracts test names and function calls from source code
    fn extractTestCalls(self: *Self, source: []const u8, file_path: []const u8) !void {
        var i: usize = 0;
        var in_test: bool = false;
        var brace_depth: usize = 0;

        while (i < source.len) {
            // Skip whitespace
            while (i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == '\n' or source[i] == '\r')) {
                i += 1;
            }
            if (i >= source.len) break;

            // Skip comments
            if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '/') {
                // Single-line comment
                while (i < source.len and source[i] != '\n') i += 1;
                continue;
            }
            if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '*') {
                // Multi-line comment
                i += 2;
                while (i + 1 < source.len and !(source[i] == '*' and source[i + 1] == '/')) i += 1;
                i += 2;
                continue;
            }

            // Check for STIG_TEST macro
            if (i + 9 < source.len and std.mem.eql(u8, source[i .. i + 9], "STIG_TEST")) {
                i += 9;
                // Skip whitespace and find (
                while (i < source.len and source[i] != '(') i += 1;
                i += 1; // skip (
                // Extract test name
                const name_start = i;
                while (i < source.len and source[i] != ')') i += 1;
                const test_name = source[name_start..i];
                self.current_test = test_name;
                in_test = true;
                brace_depth = 0;
                i += 1; // skip )
                continue;
            }

            // Track brace depth for test scope
            if (source[i] == '{') {
                brace_depth += 1;
                i += 1;
                continue;
            }
            if (source[i] == '}') {
                if (brace_depth > 0) brace_depth -= 1;
                if (brace_depth == 0 and in_test) {
                    in_test = false;
                    self.current_test = null;
                }
                i += 1;
                continue;
            }

            // Look for identifiers (potential function calls or type usage)
            if (isIdentifierStart(source[i])) {
                const ident_start = i;
                while (i < source.len and isIdentifierChar(source[i])) i += 1;
                const identifier = source[ident_start..i];

                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) i += 1;

                // Check for :: (method call or namespace)
                var full_name = identifier;
                if (i + 1 < source.len and source[i] == ':' and source[i + 1] == ':') {
                    i += 2;
                    // Get the method/member name
                    while (i < source.len and (source[i] == ' ' or source[i] == '\t')) i += 1;
                    if (i < source.len and isIdentifierStart(source[i])) {
                        const member_start = i;
                        while (i < source.len and isIdentifierChar(source[i])) i += 1;
                        const member = source[member_start..i];

                        // Build qualified name
                        var buf: [512]u8 = undefined;
                        const qualified = std.fmt.bufPrint(&buf, "{s}::{s}", .{ identifier, member }) catch |err| blk: {
                            std.debug.print("Warning: Qualified name too long '{s}::{s}': {}\n", .{ identifier, member, err });
                            break :blk identifier;
                        };
                        full_name = qualified;
                    }
                }

                // Skip whitespace again
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) i += 1;

                // Check if this is a function call (followed by '(') or type instantiation (followed by '<' or '{')
                const is_call = i < source.len and (source[i] == '(' or source[i] == '<' or source[i] == '{');
                const is_member_access = i < source.len and source[i] == '.';

                if (is_call or is_member_access) {
                    // Check if this identifier is in our symbol table
                    try self.recordSymbolUsage(full_name, file_path);

                    // Also check the base identifier (class name for templates)
                    if (!std.mem.eql(u8, full_name, identifier)) {
                        try self.recordSymbolUsage(identifier, file_path);
                    }
                }

                // Handle member access chain (obj.method())
                if (is_member_access) {
                    i += 1; // skip .
                    while (i < source.len and (source[i] == ' ' or source[i] == '\t')) i += 1;
                    if (i < source.len and isIdentifierStart(source[i])) {
                        const method_start = i;
                        while (i < source.len and isIdentifierChar(source[i])) i += 1;
                        const method_name = source[method_start..i];

                        // Try to find this as a method of the type
                        // For now, just record the method name
                        try self.recordSymbolUsage(method_name, file_path);
                    }
                }

                continue;
            }

            i += 1;
        }
    }

    /// Records that a symbol was used in a test
    fn recordSymbolUsage(self: *Self, name: []const u8, file_path: []const u8) !void {
        // Check if this symbol exists in our API
        if (self.symbol_table.lookup(name)) |info| {
            // Use the canonical name from the symbol table (which is stable)
            const canonical_name = info.name;
            const gop = try self.tested_symbols.getOrPut(canonical_name);
            if (gop.found_existing) {
                gop.value_ptr.call_count += 1;
            } else {
                gop.value_ptr.* = .{
                    .test_file = file_path,
                    .test_name = null, // Don't track test name for now (would need allocation)
                    .call_count = 1,
                };
            }
        }
    }

    /// Builds the final report by comparing tested symbols with all symbols
    fn buildReport(self: *Self, report: *TestCoverageReport) !void {
        // Iterate through all symbols in the symbol table
        var iter = self.symbol_table.symbols.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const info = entry.value_ptr.*;

            // Skip short names (duplicates of qualified names)
            if (std.mem.indexOf(u8, name, "::") == null and
                self.symbol_table.symbols.contains(name))
            {
                // Check if there's a qualified version
                var has_qualified = false;
                var check_iter = self.symbol_table.symbols.keyIterator();
                while (check_iter.next()) |key| {
                    if (std.mem.endsWith(u8, key.*, name) and key.*.len > name.len) {
                        has_qualified = true;
                        break;
                    }
                }
                if (has_qualified) continue;
            }

            // Update stats based on kind
            switch (info.kind) {
                .function => {
                    // Check if it's a method (contains ::)
                    if (std.mem.indexOf(u8, name, "::") != null) {
                        report.stats.methods_total += 1;
                    } else {
                        report.stats.functions_total += 1;
                    }
                },
                .class_type => report.stats.classes_total += 1,
                else => {},
            }
            report.stats.total_entities += 1;

            // Check if this symbol was tested
            if (self.tested_symbols.get(name)) |tested_info| {
                report.stats.tested_entities += 1;

                switch (info.kind) {
                    .function => {
                        if (std.mem.indexOf(u8, name, "::") != null) {
                            report.stats.methods_tested += 1;
                        } else {
                            report.stats.functions_tested += 1;
                        }
                    },
                    .class_type => report.stats.classes_tested += 1,
                    else => {},
                }

                try report.tested.append(self.allocator, .{
                    .name = name,
                    .kind = info.kind,
                    .test_file = tested_info.test_file,
                    .test_name = tested_info.test_name,
                    .call_count = tested_info.call_count,
                });
            } else {
                try report.untested.append(self.allocator, .{
                    .name = name,
                    .kind = info.kind,
                    .source_file = info.source_file,
                    .line = 0, // We don't have line info in symbol table
                });
            }
        }
    }
};

fn isIdentifierStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentifierChar(c: u8) bool {
    return isIdentifierStart(c) or (c >= '0' and c <= '9');
}

/// Output format for test coverage reports
pub const OutputFormat = enum {
    human,
    compiler,
    json,
};

/// Prints the test coverage report in human-readable format
pub fn printHumanReport(report: TestCoverageReport) void {
    std.debug.print("\n", .{});
    std.debug.print("Test Coverage Report\n", .{});
    std.debug.print("====================\n", .{});
    std.debug.print("Overall: {d:.0}% ({d}/{d} entities tested)\n\n", .{
        report.stats.percentage(),
        report.stats.tested_entities,
        report.stats.total_entities,
    });

    std.debug.print("By Type:\n", .{});

    if (report.stats.functions_total > 0) {
        std.debug.print("  Functions: {d:>3.0}% ({d}/{d})\n", .{
            report.stats.functions_percentage(),
            report.stats.functions_tested,
            report.stats.functions_total,
        });
    }

    if (report.stats.classes_total > 0) {
        std.debug.print("  Classes:   {d:>3.0}% ({d}/{d})\n", .{
            report.stats.classes_percentage(),
            report.stats.classes_tested,
            report.stats.classes_total,
        });
    }

    if (report.stats.methods_total > 0) {
        std.debug.print("  Methods:   {d:>3.0}% ({d}/{d})\n", .{
            report.stats.methods_percentage(),
            report.stats.methods_tested,
            report.stats.methods_total,
        });
    }

    std.debug.print("\nTest files analyzed: {d}\n", .{report.test_files_parsed});

    // Print tested entities
    if (report.tested.items.len > 0) {
        std.debug.print("\nTested Entities:\n", .{});
        for (report.tested.items) |entity| {
            const kind_str = switch (entity.kind) {
                .function => "function",
                .class_type => "class",
                .struct_type => "struct",
                .enum_type => "enum",
                .typedef => "typedef",
                .macro => "macro",
            };
            if (entity.test_name) |test_name| {
                std.debug.print("  [OK] {s} ({s}) - tested in {s}\n", .{ entity.name, kind_str, test_name });
            } else {
                std.debug.print("  [OK] {s} ({s})\n", .{ entity.name, kind_str });
            }
        }
    }

    // Print untested entities
    if (report.untested.items.len > 0) {
        std.debug.print("\nUntested Entities:\n", .{});
        for (report.untested.items) |entity| {
            const kind_str = switch (entity.kind) {
                .function => "function",
                .class_type => "class",
                .struct_type => "struct",
                .enum_type => "enum",
                .typedef => "typedef",
                .macro => "macro",
            };
            std.debug.print("  [  ] {s} ({s}) - {s}\n", .{ entity.name, kind_str, entity.source_file });
        }
    }

    std.debug.print("\n", .{});
}

/// Prints the test coverage report in compiler-style format
pub fn printCompilerReport(report: TestCoverageReport) void {
    for (report.untested.items) |entity| {
        const kind_str = switch (entity.kind) {
            .function => "function",
            .class_type => "class",
            .struct_type => "struct",
            .enum_type => "enum",
            .typedef => "typedef",
            .macro => "macro",
        };
        std.debug.print("{s}:1:1: warning: {s} '{s}' has no tests\n", .{
            entity.source_file,
            kind_str,
            entity.name,
        });
    }

    std.debug.print("\nstig: test coverage {d:.0}% ({d}/{d} entities tested)\n", .{
        report.stats.percentage(),
        report.stats.tested_entities,
        report.stats.total_entities,
    });
}

/// Prints the test coverage report in JSON format
pub fn printJsonReport(allocator: std.mem.Allocator, report: TestCoverageReport) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "{\n");
    try output.appendSlice(allocator, "  \"coverage\": {\n");
    try std.fmt.format(output.writer(allocator), "    \"percentage\": {d:.1},\n", .{report.stats.percentage()});
    try std.fmt.format(output.writer(allocator), "    \"tested\": {d},\n", .{report.stats.tested_entities});
    try std.fmt.format(output.writer(allocator), "    \"total\": {d}\n", .{report.stats.total_entities});
    try output.appendSlice(allocator, "  },\n");

    try output.appendSlice(allocator, "  \"tested\": [\n");
    for (report.tested.items, 0..) |entity, i| {
        try output.appendSlice(allocator, "    {\n");
        try std.fmt.format(output.writer(allocator), "      \"name\": \"{s}\",\n", .{entity.name});
        try std.fmt.format(output.writer(allocator), "      \"test_file\": \"{s}\",\n", .{entity.test_file});
        try std.fmt.format(output.writer(allocator), "      \"call_count\": {d}\n", .{entity.call_count});
        if (i < report.tested.items.len - 1) {
            try output.appendSlice(allocator, "    },\n");
        } else {
            try output.appendSlice(allocator, "    }\n");
        }
    }
    try output.appendSlice(allocator, "  ],\n");

    try output.appendSlice(allocator, "  \"untested\": [\n");
    for (report.untested.items, 0..) |entity, i| {
        try output.appendSlice(allocator, "    {\n");
        try std.fmt.format(output.writer(allocator), "      \"name\": \"{s}\",\n", .{entity.name});
        try std.fmt.format(output.writer(allocator), "      \"source_file\": \"{s}\"\n", .{entity.source_file});
        if (i < report.untested.items.len - 1) {
            try output.appendSlice(allocator, "    },\n");
        } else {
            try output.appendSlice(allocator, "    }\n");
        }
    }
    try output.appendSlice(allocator, "  ]\n");

    try output.appendSlice(allocator, "}\n");

    std.debug.print("{s}", .{output.items});
}

/// Prints the test coverage report in SARIF format for CI/CD integration
pub fn printSarifReport(allocator: std.mem.Allocator, report: TestCoverageReport) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    // SARIF header
    try output.appendSlice(allocator, "{\n");
    try output.appendSlice(allocator, "  \"$schema\": \"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\n");
    try output.appendSlice(allocator, "  \"version\": \"2.1.0\",\n");
    try output.appendSlice(allocator, "  \"runs\": [{\n");
    try output.appendSlice(allocator, "    \"tool\": {\n");
    try output.appendSlice(allocator, "      \"driver\": {\n");
    try output.appendSlice(allocator, "        \"name\": \"stig\",\n");
    try output.appendSlice(allocator, "        \"version\": \"");
    try output.appendSlice(allocator, cli.VERSION);
    try output.appendSlice(allocator, "\",\n");
    try output.appendSlice(allocator, "        \"informationUri\": \"https://github.com/stig-docs/stig\",\n");
    try output.appendSlice(allocator, "        \"rules\": [{\n");
    try output.appendSlice(allocator, "          \"id\": \"TCOV001\",\n");
    try output.appendSlice(allocator, "          \"name\": \"MissingTestCoverage\",\n");
    try output.appendSlice(allocator, "          \"shortDescription\": {\n");
    try output.appendSlice(allocator, "            \"text\": \"API entity has no test coverage\"\n");
    try output.appendSlice(allocator, "          },\n");
    try output.appendSlice(allocator, "          \"fullDescription\": {\n");
    try output.appendSlice(allocator, "            \"text\": \"A documented API entity (function, class, etc.) is not covered by any test file.\"\n");
    try output.appendSlice(allocator, "          },\n");
    try output.appendSlice(allocator, "          \"defaultConfiguration\": {\n");
    try output.appendSlice(allocator, "            \"level\": \"warning\"\n");
    try output.appendSlice(allocator, "          }\n");
    try output.appendSlice(allocator, "        }]\n");
    try output.appendSlice(allocator, "      }\n");
    try output.appendSlice(allocator, "    },\n");

    // Results array
    try output.appendSlice(allocator, "    \"results\": [\n");

    for (report.untested.items, 0..) |entity, i| {
        try output.appendSlice(allocator, "      {\n");
        try output.appendSlice(allocator, "        \"ruleId\": \"TCOV001\",\n");
        try output.appendSlice(allocator, "        \"level\": \"warning\",\n");
        try output.appendSlice(allocator, "        \"message\": {\n");

        const kind_str = switch (entity.kind) {
            .function => "function",
            .class_type => "class",
            .struct_type => "struct",
            .enum_type => "enum",
            .typedef => "typedef",
            .macro => "macro",
        };

        try std.fmt.format(output.writer(allocator), "          \"text\": \"{s} '{s}' has no test coverage\"\n", .{ kind_str, entity.name });
        try output.appendSlice(allocator, "        },\n");
        try output.appendSlice(allocator, "        \"locations\": [{\n");
        try output.appendSlice(allocator, "          \"physicalLocation\": {\n");
        try output.appendSlice(allocator, "            \"artifactLocation\": {\n");
        try std.fmt.format(output.writer(allocator), "              \"uri\": \"{s}\"\n", .{entity.source_file});
        try output.appendSlice(allocator, "            },\n");
        try output.appendSlice(allocator, "            \"region\": {\n");
        try std.fmt.format(output.writer(allocator), "              \"startLine\": {d}\n", .{entity.line});
        try output.appendSlice(allocator, "            }\n");
        try output.appendSlice(allocator, "          }\n");
        try output.appendSlice(allocator, "        }]\n");

        if (i < report.untested.items.len - 1) {
            try output.appendSlice(allocator, "      },\n");
        } else {
            try output.appendSlice(allocator, "      }\n");
        }
    }

    try output.appendSlice(allocator, "    ]\n");
    try output.appendSlice(allocator, "  }]\n");
    try output.appendSlice(allocator, "}\n");

    const stdout_file = std.fs.File.stdout();
    stdout_file.writeAll(output.items) catch |err| {
        std.debug.print("Error: Failed to write SARIF output: {}\n", .{err});
    };
}

// Tests
test "identifier detection" {
    try std.testing.expect(isIdentifierStart('a'));
    try std.testing.expect(isIdentifierStart('Z'));
    try std.testing.expect(isIdentifierStart('_'));
    try std.testing.expect(!isIdentifierStart('0'));
    try std.testing.expect(!isIdentifierStart(' '));

    try std.testing.expect(isIdentifierChar('a'));
    try std.testing.expect(isIdentifierChar('0'));
    try std.testing.expect(isIdentifierChar('_'));
    try std.testing.expect(!isIdentifierChar(' '));
}
