const std = @import("std");
const types = @import("model/types.zig");

/// Statistics for a specific entity type
pub const CoverageStats = struct {
    total: usize = 0,
    documented: usize = 0,
    missing_params: usize = 0, // functions with undocumented params
    missing_returns: usize = 0, // non-void functions without @return

    pub fn percentage(self: CoverageStats) f64 {
        if (self.total == 0) return 100.0;
        return @as(f64, @floatFromInt(self.documented)) / @as(f64, @floatFromInt(self.total)) * 100.0;
    }
};

/// Information about a missing documentation item
pub const MissingDoc = struct {
    file: []const u8,
    entity_name: []const u8,
    entity_type: []const u8, // "function", "class", etc.
    issue: []const u8, // "no documentation", "missing @param for 'x'", etc.
    line: u32,
};

/// Complete coverage analysis report
pub const CoverageReport = struct {
    total_entities: usize = 0,
    documented_entities: usize = 0,
    functions: CoverageStats = .{},
    classes: CoverageStats = .{},
    structs: CoverageStats = .{},
    enums: CoverageStats = .{},
    macros: CoverageStats = .{},
    typedefs: CoverageStats = .{},
    type_aliases: CoverageStats = .{},
    concepts: CoverageStats = .{},
    missing_items: std.ArrayList(MissingDoc),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CoverageReport {
        return .{
            .missing_items = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CoverageReport) void {
        // Free allocated issue strings and entity names
        for (self.missing_items.items) |item| {
            if (isAllocatedIssue(item.issue)) {
                self.allocator.free(item.issue);
            }
            if (isAllocatedEntityName(item.entity_name)) {
                self.allocator.free(item.entity_name);
            }
        }
        self.missing_items.deinit(self.allocator);
    }

    fn isAllocatedIssue(issue: []const u8) bool {
        // Check if this is one of the static strings
        const static_strings = [_][]const u8{
            "no documentation",
            "missing @return",
        };
        for (static_strings) |s| {
            if (std.mem.eql(u8, issue, s)) return false;
        }
        // If it starts with "missing @param" or "missing @tparam", it's allocated
        return std.mem.startsWith(u8, issue, "missing @param") or
            std.mem.startsWith(u8, issue, "missing @tparam");
    }

    fn isAllocatedEntityName(name: []const u8) bool {
        // Entity names that contain "::" were allocated (method names like "Class::method")
        return std.mem.indexOf(u8, name, "::") != null;
    }

    pub fn overallPercentage(self: CoverageReport) f64 {
        if (self.total_entities == 0) return 100.0;
        return @as(f64, @floatFromInt(self.documented_entities)) / @as(f64, @floatFromInt(self.total_entities)) * 100.0;
    }
};

/// Configuration for coverage analysis
pub const CoverageConfig = struct {
    min_coverage: u8 = 80,
    require_param_docs: bool = true,
    require_return_docs: bool = true,
    require_tparam_docs: bool = true,
    exclude_patterns: []const []const u8 = &[_][]const u8{},
};

/// Analyzes documentation coverage for the given modules
pub fn analyze(allocator: std.mem.Allocator, modules: []const types.Module, config: CoverageConfig) !CoverageReport {
    var report = CoverageReport.init(allocator);
    errdefer report.deinit();

    for (modules) |module| {
        try analyzeModule(allocator, module, &report, config);
    }

    return report;
}

fn analyzeModule(allocator: std.mem.Allocator, module: types.Module, report: *CoverageReport, config: CoverageConfig) !void {
    const file = module.name;

    // Analyze functions
    for (module.functions) |func| {
        if (shouldExclude(func.name, config.exclude_patterns)) continue;

        report.functions.total += 1;
        report.total_entities += 1;

        if (func.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.functions.documented += 1;
                report.documented_entities += 1;

                // Check for missing param docs
                if (config.require_param_docs) {
                    for (func.params) |param| {
                        if (!hasParamDoc(doc, param.name)) {
                            report.functions.missing_params += 1;
                            const issue = try std.fmt.allocPrint(allocator, "missing @param for '{s}'", .{param.name});
                            try report.missing_items.append(allocator, .{
                                .file = file,
                                .entity_name = func.name,
                                .entity_type = "function",
                                .issue = issue,
                                .line = func.location.line,
                            });
                        }
                    }
                }

                // Check for missing tparam docs
                if (config.require_tparam_docs) {
                    for (func.template_params) |tparam| {
                        if (!hasTparamDoc(doc, tparam.name)) {
                            const issue = try std.fmt.allocPrint(allocator, "missing @tparam for '{s}'", .{tparam.name});
                            try report.missing_items.append(allocator, .{
                                .file = file,
                                .entity_name = func.name,
                                .entity_type = "function",
                                .issue = issue,
                                .line = func.location.line,
                            });
                        }
                    }
                }

                // Check for missing return docs (non-void functions)
                if (config.require_return_docs and !isVoidReturn(func.return_type)) {
                    if (doc.returns == null and doc.retvals.len == 0) {
                        report.functions.missing_returns += 1;
                        try report.missing_items.append(allocator, .{
                            .file = file,
                            .entity_name = func.name,
                            .entity_type = "function",
                            .issue = "missing @return",
                            .line = func.location.line,
                        });
                    }
                }
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = func.name,
                    .entity_type = "function",
                    .issue = "no documentation",
                    .line = func.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = func.name,
                .entity_type = "function",
                .issue = "no documentation",
                .line = func.location.line,
            });
        }
    }

    // Analyze classes
    for (module.classes) |class| {
        if (shouldExclude(class.name, config.exclude_patterns)) continue;
        try analyzeClass(allocator, class, file, report, config);
    }

    // Analyze structs
    for (module.structs) |strct| {
        if (shouldExclude(strct.name, config.exclude_patterns)) continue;

        report.structs.total += 1;
        report.total_entities += 1;

        if (strct.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.structs.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = strct.name,
                    .entity_type = "struct",
                    .issue = "no documentation",
                    .line = strct.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = strct.name,
                .entity_type = "struct",
                .issue = "no documentation",
                .line = strct.location.line,
            });
        }
    }

    // Analyze enums
    for (module.enums) |enm| {
        if (shouldExclude(enm.name, config.exclude_patterns)) continue;

        report.enums.total += 1;
        report.total_entities += 1;

        if (enm.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.enums.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = enm.name,
                    .entity_type = "enum",
                    .issue = "no documentation",
                    .line = enm.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = enm.name,
                .entity_type = "enum",
                .issue = "no documentation",
                .line = enm.location.line,
            });
        }
    }

    // Analyze macros
    for (module.macros) |macro| {
        if (shouldExclude(macro.name, config.exclude_patterns)) continue;

        report.macros.total += 1;
        report.total_entities += 1;

        if (macro.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.macros.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = macro.name,
                    .entity_type = "macro",
                    .issue = "no documentation",
                    .line = macro.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = macro.name,
                .entity_type = "macro",
                .issue = "no documentation",
                .line = macro.location.line,
            });
        }
    }

    // Analyze typedefs
    for (module.typedefs) |td| {
        if (shouldExclude(td.name, config.exclude_patterns)) continue;

        report.typedefs.total += 1;
        report.total_entities += 1;

        if (td.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.typedefs.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = td.name,
                    .entity_type = "typedef",
                    .issue = "no documentation",
                    .line = td.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = td.name,
                .entity_type = "typedef",
                .issue = "no documentation",
                .line = td.location.line,
            });
        }
    }

    // Analyze type aliases
    for (module.type_aliases) |alias| {
        if (shouldExclude(alias.name, config.exclude_patterns)) continue;

        report.type_aliases.total += 1;
        report.total_entities += 1;

        if (alias.docstring) |doc| {
            if (hasDocumentation(doc)) {
                report.type_aliases.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = alias.name,
                    .entity_type = "type_alias",
                    .issue = "no documentation",
                    .line = 0,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = alias.name,
                .entity_type = "type_alias",
                .issue = "no documentation",
                .line = 0,
            });
        }
    }

    // Analyze concepts
    for (module.concepts) |concept| {
        if (shouldExclude(concept.name, config.exclude_patterns)) continue;

        report.concepts.total += 1;
        report.total_entities += 1;

        if (concept.docstring) |doc| {
            if (hasDocumentation(doc)) {
                report.concepts.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = concept.name,
                    .entity_type = "concept",
                    .issue = "no documentation",
                    .line = 0,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = concept.name,
                .entity_type = "concept",
                .issue = "no documentation",
                .line = 0,
            });
        }
    }
}

fn analyzeClass(allocator: std.mem.Allocator, class: types.Class, file: []const u8, report: *CoverageReport, config: CoverageConfig) !void {
    report.classes.total += 1;
    report.total_entities += 1;

    if (class.doc) |doc| {
        if (hasDocumentation(doc)) {
            report.classes.documented += 1;
            report.documented_entities += 1;

            // Check for missing tparam docs on class templates
            if (config.require_tparam_docs) {
                for (class.template_params) |tparam| {
                    if (!hasTparamDoc(doc, tparam.name)) {
                        const issue = try std.fmt.allocPrint(allocator, "missing @tparam for '{s}'", .{tparam.name});
                        try report.missing_items.append(allocator, .{
                            .file = file,
                            .entity_name = class.name,
                            .entity_type = "class",
                            .issue = issue,
                            .line = class.location.line,
                        });
                    }
                }
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = class.name,
                .entity_type = "class",
                .issue = "no documentation",
                .line = class.location.line,
            });
        }
    } else {
        try report.missing_items.append(allocator, .{
            .file = file,
            .entity_name = class.name,
            .entity_type = "class",
            .issue = "no documentation",
            .line = class.location.line,
        });
    }

    // Analyze methods (count as functions)
    for (class.methods) |method| {
        if (shouldExclude(method.name, config.exclude_patterns)) continue;

        // Skip private methods unless specifically requested
        if (method.access == .private) continue;

        report.functions.total += 1;
        report.total_entities += 1;

        const method_name = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ class.name, method.name });
        defer allocator.free(method_name);

        if (method.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.functions.documented += 1;
                report.documented_entities += 1;

                // Check for missing param docs
                if (config.require_param_docs) {
                    for (method.params) |param| {
                        if (!hasParamDoc(doc, param.name)) {
                            report.functions.missing_params += 1;
                            const issue = try std.fmt.allocPrint(allocator, "missing @param for '{s}'", .{param.name});
                            const name_copy = try allocator.dupe(u8, method_name);
                            errdefer allocator.free(name_copy);
                            try report.missing_items.append(allocator, .{
                                .file = file,
                                .entity_name = name_copy,
                                .entity_type = "method",
                                .issue = issue,
                                .line = method.location.line,
                            });
                        }
                    }
                }

                // Check for missing return docs (non-void, non-constructor/destructor)
                if (config.require_return_docs and
                    method.kind != .constructor and
                    method.kind != .destructor and
                    method.kind != .copy_constructor and
                    method.kind != .move_constructor and
                    !isVoidReturn(method.return_type))
                {
                    if (doc.returns == null and doc.retvals.len == 0) {
                        report.functions.missing_returns += 1;
                        const name_copy = try allocator.dupe(u8, method_name);
                        errdefer allocator.free(name_copy);
                        try report.missing_items.append(allocator, .{
                            .file = file,
                            .entity_name = name_copy,
                            .entity_type = "method",
                            .issue = "missing @return",
                            .line = method.location.line,
                        });
                    }
                }
            } else {
                const name_copy = try allocator.dupe(u8, method_name);
                errdefer allocator.free(name_copy);
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = name_copy,
                    .entity_type = "method",
                    .issue = "no documentation",
                    .line = method.location.line,
                });
            }
        } else {
            const name_copy = try allocator.dupe(u8, method_name);
            errdefer allocator.free(name_copy);
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = name_copy,
                .entity_type = "method",
                .issue = "no documentation",
                .line = method.location.line,
            });
        }
    }

    // Analyze nested classes
    for (class.nested_classes) |nested| {
        if (shouldExclude(nested.name, config.exclude_patterns)) continue;
        try analyzeClass(allocator, nested, file, report, config);
    }

    // Analyze nested enums
    for (class.nested_enums) |nested_enum| {
        if (shouldExclude(nested_enum.name, config.exclude_patterns)) continue;

        report.enums.total += 1;
        report.total_entities += 1;

        if (nested_enum.doc) |doc| {
            if (hasDocumentation(doc)) {
                report.enums.documented += 1;
                report.documented_entities += 1;
            } else {
                try report.missing_items.append(allocator, .{
                    .file = file,
                    .entity_name = nested_enum.name,
                    .entity_type = "enum",
                    .issue = "no documentation",
                    .line = nested_enum.location.line,
                });
            }
        } else {
            try report.missing_items.append(allocator, .{
                .file = file,
                .entity_name = nested_enum.name,
                .entity_type = "enum",
                .issue = "no documentation",
                .line = nested_enum.location.line,
            });
        }
    }
}

fn hasDocumentation(doc: types.DocString) bool {
    // Has documentation if brief or details exist
    return doc.brief != null or doc.details != null or doc.raw.len > 0;
}

fn hasParamDoc(doc: types.DocString, param_name: []const u8) bool {
    for (doc.params) |p| {
        if (std.mem.eql(u8, p.name, param_name)) {
            return true;
        }
    }
    return false;
}

fn hasTparamDoc(doc: types.DocString, tparam_name: []const u8) bool {
    for (doc.tparams) |tp| {
        if (std.mem.eql(u8, tp.name, tparam_name)) {
            return true;
        }
    }
    return false;
}

fn isVoidReturn(return_type: []const u8) bool {
    const trimmed = std.mem.trim(u8, return_type, " \t");
    return std.mem.eql(u8, trimmed, "void") or trimmed.len == 0;
}

fn shouldExclude(name: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        if (globMatch(pattern, name)) {
            return true;
        }
    }
    return false;
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

/// Output format for coverage reports
pub const OutputFormat = enum {
    /// Human-readable format with summary
    human,
    /// Compiler-style format: file:line:col: severity: message
    compiler,
    /// JSON format for tooling
    json,
};

/// Prints the coverage report in compiler-style format (file:line:col: severity: message)
/// This format is compatible with most IDEs and CI/CD tools
pub fn printCompilerReport(report: CoverageReport) void {
    for (report.missing_items.items) |item| {
        // Determine severity based on issue type
        const severity = if (std.mem.eql(u8, item.issue, "no documentation"))
            "warning"
        else
            "note";

        // Format: file:line:col: severity: message
        // Use column 1 as default since we don't track columns
        if (item.line > 0) {
            std.debug.print("{s}:{d}:1: {s}: {s} '{s}' ({s})\n", .{
                item.file,
                item.line,
                severity,
                item.issue,
                item.entity_name,
                item.entity_type,
            });
        } else {
            // For items without line info, still output in compiler format
            std.debug.print("{s}:1:1: {s}: {s} '{s}' ({s})\n", .{
                item.file,
                severity,
                item.issue,
                item.entity_name,
                item.entity_type,
            });
        }
    }

    // Print summary at the end
    if (report.missing_items.items.len > 0) {
        std.debug.print("\nstig: {d} documentation issue(s) found\n", .{report.missing_items.items.len});
    }

    // Print coverage percentage
    std.debug.print("stig: coverage {d:.0}% ({d}/{d} entities documented)\n", .{
        report.overallPercentage(),
        report.documented_entities,
        report.total_entities,
    });
}

/// Prints the coverage report in JSON format
pub fn printJsonReport(allocator: std.mem.Allocator, report: CoverageReport) !void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "{\n");
    try output.appendSlice(allocator, "  \"coverage\": {\n");
    try std.fmt.format(output.writer(allocator), "    \"percentage\": {d:.1},\n", .{report.overallPercentage()});
    try std.fmt.format(output.writer(allocator), "    \"documented\": {d},\n", .{report.documented_entities});
    try std.fmt.format(output.writer(allocator), "    \"total\": {d}\n", .{report.total_entities});
    try output.appendSlice(allocator, "  },\n");

    try output.appendSlice(allocator, "  \"issues\": [\n");
    for (report.missing_items.items, 0..) |item, i| {
        try output.appendSlice(allocator, "    {\n");
        try std.fmt.format(output.writer(allocator), "      \"file\": \"{s}\",\n", .{item.file});
        try std.fmt.format(output.writer(allocator), "      \"line\": {d},\n", .{item.line});
        try std.fmt.format(output.writer(allocator), "      \"entity\": \"{s}\",\n", .{item.entity_name});
        try std.fmt.format(output.writer(allocator), "      \"type\": \"{s}\",\n", .{item.entity_type});
        try std.fmt.format(output.writer(allocator), "      \"issue\": \"{s}\"\n", .{item.issue});
        if (i < report.missing_items.items.len - 1) {
            try output.appendSlice(allocator, "    },\n");
        } else {
            try output.appendSlice(allocator, "    }\n");
        }
    }
    try output.appendSlice(allocator, "  ]\n");
    try output.appendSlice(allocator, "}\n");

    std.debug.print("{s}", .{output.items});
}

/// Prints the coverage report to stderr using std.debug.print (human-readable format)
pub fn printReport(report: CoverageReport) void {
    printHumanReport(report);
}

/// Prints the coverage report in human-readable format
pub fn printHumanReport(report: CoverageReport) void {
    std.debug.print("\n", .{});
    std.debug.print("Documentation Coverage Report\n", .{});
    std.debug.print("=============================\n", .{});
    std.debug.print("Overall: {d:.0}% ({d}/{d} entities documented)\n\n", .{
        report.overallPercentage(),
        report.documented_entities,
        report.total_entities,
    });

    std.debug.print("By Type:\n", .{});

    // Only print types that have entities
    if (report.functions.total > 0) {
        std.debug.print("  Functions:    {d:>3.0}% ({d}/{d})", .{
            report.functions.percentage(),
            report.functions.documented,
            report.functions.total,
        });
        if (report.functions.missing_params > 0 or report.functions.missing_returns > 0) {
            std.debug.print(" [", .{});
            var first = true;
            if (report.functions.missing_params > 0) {
                std.debug.print("{d} missing params", .{report.functions.missing_params});
                first = false;
            }
            if (report.functions.missing_returns > 0) {
                if (!first) std.debug.print(", ", .{});
                std.debug.print("{d} missing returns", .{report.functions.missing_returns});
            }
            std.debug.print("]", .{});
        }
        std.debug.print("\n", .{});
    }

    if (report.classes.total > 0) {
        std.debug.print("  Classes:      {d:>3.0}% ({d}/{d})\n", .{
            report.classes.percentage(),
            report.classes.documented,
            report.classes.total,
        });
    }

    if (report.structs.total > 0) {
        std.debug.print("  Structs:      {d:>3.0}% ({d}/{d})\n", .{
            report.structs.percentage(),
            report.structs.documented,
            report.structs.total,
        });
    }

    if (report.enums.total > 0) {
        std.debug.print("  Enums:        {d:>3.0}% ({d}/{d})\n", .{
            report.enums.percentage(),
            report.enums.documented,
            report.enums.total,
        });
    }

    if (report.macros.total > 0) {
        std.debug.print("  Macros:       {d:>3.0}% ({d}/{d})\n", .{
            report.macros.percentage(),
            report.macros.documented,
            report.macros.total,
        });
    }

    if (report.typedefs.total > 0) {
        std.debug.print("  Typedefs:     {d:>3.0}% ({d}/{d})\n", .{
            report.typedefs.percentage(),
            report.typedefs.documented,
            report.typedefs.total,
        });
    }

    if (report.type_aliases.total > 0) {
        std.debug.print("  Type Aliases: {d:>3.0}% ({d}/{d})\n", .{
            report.type_aliases.percentage(),
            report.type_aliases.documented,
            report.type_aliases.total,
        });
    }

    if (report.concepts.total > 0) {
        std.debug.print("  Concepts:     {d:>3.0}% ({d}/{d})\n", .{
            report.concepts.percentage(),
            report.concepts.documented,
            report.concepts.total,
        });
    }

    // Print missing documentation items grouped by file
    if (report.missing_items.items.len > 0) {
        std.debug.print("\nMissing Documentation:\n", .{});

        // Group by file
        var current_file: []const u8 = "";
        for (report.missing_items.items) |item| {
            if (!std.mem.eql(u8, item.file, current_file)) {
                current_file = item.file;
                std.debug.print("  {s}:\n", .{current_file});
            }
            if (item.line > 0) {
                std.debug.print("    - {s}() [line {d}] - {s}\n", .{ item.entity_name, item.line, item.issue });
            } else {
                std.debug.print("    - {s}() - {s}\n", .{ item.entity_name, item.issue });
            }
        }
    }

    std.debug.print("\n", .{});
}

// Tests
test "coverage stats percentage" {
    var stats = CoverageStats{
        .total = 10,
        .documented = 8,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 80.0), stats.percentage(), 0.01);

    stats.total = 0;
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), stats.percentage(), 0.01);
}

test "is void return" {
    try std.testing.expect(isVoidReturn("void"));
    try std.testing.expect(isVoidReturn(" void "));
    try std.testing.expect(isVoidReturn(""));
    try std.testing.expect(!isVoidReturn("int"));
    try std.testing.expect(!isVoidReturn("void*"));
}

test "glob match" {
    try std.testing.expect(globMatch("test_*", "test_foo"));
    try std.testing.expect(globMatch("*_internal", "foo_internal"));
    try std.testing.expect(globMatch("*", "anything"));
    try std.testing.expect(!globMatch("test_*", "foo_test"));
}
