const std = @import("std");
const types = @import("model/types.zig");
const xref = @import("xref.zig");

/// Severity level for lint issues
pub const Severity = enum {
    /// Informational - style suggestions
    info,
    /// Warning - potential issues
    warning,
    /// Error - definite problems
    @"error",

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .info => "info",
            .warning => "warning",
            .@"error" => "error",
        };
    }
};

/// A single lint issue found in the documentation
pub const LintIssue = struct {
    /// File where the issue was found
    file: []const u8,
    /// Line number (0 if unknown)
    line: u32,
    /// Entity name (function, class, etc.)
    entity_name: []const u8,
    /// Entity type (function, class, struct, etc.)
    entity_type: []const u8,
    /// Issue severity
    severity: Severity,
    /// Issue code (e.g., "E001", "W002")
    code: []const u8,
    /// Human-readable message
    message: []const u8,
    /// Optional suggestion for fixing
    suggestion: ?[]const u8 = null,
};

/// Lint report containing all issues found
pub const LintReport = struct {
    issues: std.ArrayList(LintIssue),
    allocator: std.mem.Allocator,
    error_count: usize = 0,
    warning_count: usize = 0,
    info_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LintReport {
        return .{
            .issues = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LintReport) void {
        // Free allocated strings
        for (self.issues.items) |issue| {
            if (isAllocatedString(issue.message)) {
                self.allocator.free(issue.message);
            }
            if (issue.suggestion) |sug| {
                if (isAllocatedString(sug)) {
                    self.allocator.free(sug);
                }
            }
        }
        self.issues.deinit(self.allocator);
    }

    fn isAllocatedString(s: []const u8) bool {
        // Static strings we use
        const static_strings = [_][]const u8{
            "no documentation",
            "missing @return for non-void function",
            "@return present for void function",
            "empty @brief description",
            "@brief missing period at end",
        };
        for (static_strings) |ss| {
            if (std.mem.eql(u8, s, ss)) return false;
        }
        // If it starts with certain patterns, it's likely allocated
        return std.mem.startsWith(u8, s, "@param '") or
            std.mem.startsWith(u8, s, "@tparam '") or
            std.mem.startsWith(u8, s, "@see '") or
            std.mem.startsWith(u8, s, "@copydoc '") or
            std.mem.startsWith(u8, s, "@brief exceeds") or
            std.mem.startsWith(u8, s, "missing @param") or
            std.mem.startsWith(u8, s, "missing @tparam") or
            std.mem.startsWith(u8, s, "duplicate @param") or
            std.mem.startsWith(u8, s, "duplicate @tparam") or
            std.mem.startsWith(u8, s, "empty @param") or
            std.mem.startsWith(u8, s, "empty @tparam") or
            std.mem.startsWith(u8, s, "Did you mean");
    }

    pub fn addIssue(self: *LintReport, issue: LintIssue) !void {
        try self.issues.append(self.allocator, issue);
        switch (issue.severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            .info => self.info_count += 1,
        }
    }

    pub fn hasErrors(self: LintReport) bool {
        return self.error_count > 0;
    }

    pub fn hasWarnings(self: LintReport) bool {
        return self.warning_count > 0;
    }
};

const config_mod = @import("config.zig");

/// Configuration for lint checks (re-export from config module)
pub const LintConfig = struct {
    /// Enable linting
    enabled: bool = true,
    /// Treat warnings as errors
    treat_warnings_as_errors: bool = false,
    /// Maximum length for @brief descriptions
    max_brief_length: u32 = 80,
    /// Require @brief for all documented entities
    require_brief: bool = true,
    /// Require @param for all parameters
    require_param_docs: bool = true,
    /// Require @return for non-void functions
    require_return_docs: bool = true,
    /// Require @tparam for template parameters
    require_tparam_docs: bool = true,
    /// Check cross-references (@see, @copydoc)
    check_cross_references: bool = true,
    /// Require period at end of @brief
    require_brief_period: bool = false,
    /// Patterns to exclude from linting
    exclude_patterns: []const []const u8 = &[_][]const u8{},
    /// Per-rule severity overrides
    rules: []const config_mod.Config.RuleConfig = &[_]config_mod.Config.RuleConfig{},

    /// Get the severity override for a rule, or null if not configured
    pub fn getRuleSeverity(self: LintConfig, code: []const u8) ?config_mod.Config.RuleSeverity {
        for (self.rules) |rule| {
            if (std.mem.eql(u8, rule.code, code)) {
                return rule.severity;
            }
        }
        return null;
    }
};

/// Documentation linter
pub const Linter = struct {
    allocator: std.mem.Allocator,
    config: LintConfig,
    symbol_table: ?*xref.SymbolTable = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: LintConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Sets the symbol table for cross-reference validation
    pub fn setSymbolTable(self: *Self, table: *xref.SymbolTable) void {
        self.symbol_table = table;
    }

    /// Adds an issue to the report, respecting per-rule severity configuration
    /// Returns true if the issue was added, false if the rule is ignored
    fn addIssueWithRuleCheck(self: *Self, report: *LintReport, issue: LintIssue) !bool {
        // Check if there's a severity override for this rule
        if (self.config.getRuleSeverity(issue.code)) |override| {
            switch (override) {
                .ignore => return false, // Skip this issue entirely
                .info => {
                    var modified_issue = issue;
                    modified_issue.severity = .info;
                    try report.addIssue(modified_issue);
                },
                .warning => {
                    var modified_issue = issue;
                    modified_issue.severity = .warning;
                    try report.addIssue(modified_issue);
                },
                .@"error" => {
                    var modified_issue = issue;
                    modified_issue.severity = .@"error";
                    try report.addIssue(modified_issue);
                },
            }
        } else {
            // No override, use default severity
            try report.addIssue(issue);
        }
        return true;
    }

    /// Runs lint checks on the given modules
    pub fn lint(self: *Self, modules: []const types.Module) !LintReport {
        var report = LintReport.init(self.allocator);
        errdefer report.deinit();

        for (modules) |module| {
            try self.lintModule(module, &report);
        }

        return report;
    }

    fn lintModule(self: *Self, module: types.Module, report: *LintReport) !void {
        const file = module.name;

        // Lint functions
        for (module.functions) |func| {
            if (self.shouldExclude(func.name)) continue;
            try self.lintFunction(func, file, report);
        }

        // Lint classes
        for (module.classes) |class| {
            if (self.shouldExclude(class.name)) continue;
            try self.lintClass(class, file, report);
        }

        // Lint structs
        for (module.structs) |strct| {
            if (self.shouldExclude(strct.name)) continue;
            try self.lintStruct(strct, file, report);
        }

        // Lint enums
        for (module.enums) |enm| {
            if (self.shouldExclude(enm.name)) continue;
            try self.lintEnum(enm, file, report);
        }

        // Lint macros
        for (module.macros) |macro| {
            if (self.shouldExclude(macro.name)) continue;
            try self.lintMacro(macro, file, report);
        }

        // Lint typedefs
        for (module.typedefs) |td| {
            if (self.shouldExclude(td.name)) continue;
            try self.lintTypedef(td, file, report);
        }

        // Lint type aliases
        for (module.type_aliases) |alias| {
            if (self.shouldExclude(alias.name)) continue;
            try self.lintTypeAlias(alias, file, report);
        }

        // Lint concepts
        for (module.concepts) |concept| {
            if (self.shouldExclude(concept.name)) continue;
            try self.lintConcept(concept, file, report);
        }
    }

    fn lintFunction(self: *Self, func: types.Function, file: []const u8, report: *LintReport) !void {
        if (func.doc) |doc| {
            // Check brief
            try self.checkBrief(doc, func.name, "function", file, func.location.line, report);

            // Check parameters
            if (self.config.require_param_docs) {
                try self.checkParams(doc, func.params, func.name, "function", file, func.location.line, report);
            }

            // Check template parameters
            if (self.config.require_tparam_docs) {
                try self.checkTparams(doc, func.template_params, func.name, "function", file, func.location.line, report);
            }

            // Check return documentation
            if (self.config.require_return_docs) {
                try self.checkReturn(doc, func.return_type, func.name, "function", file, func.location.line, report);
            }

            // Check cross-references
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, func.name, "function", file, func.location.line, report);
            }
        } else {
            // No documentation at all
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = func.location.line,
                .entity_name = func.name,
                .entity_type = "function",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintClass(self: *Self, class: types.Class, file: []const u8, report: *LintReport) !void {
        if (class.doc) |doc| {
            // Check brief
            try self.checkBrief(doc, class.name, "class", file, class.location.line, report);

            // Check template parameters
            if (self.config.require_tparam_docs) {
                try self.checkTparams(doc, class.template_params, class.name, "class", file, class.location.line, report);
            }

            // Check cross-references
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, class.name, "class", file, class.location.line, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = class.location.line,
                .entity_name = class.name,
                .entity_type = "class",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }

        // Lint methods
        for (class.methods) |method| {
            // Skip private methods
            if (method.access == .private) continue;
            try self.lintMethod(method, class.name, file, report);
        }

        // Lint nested classes
        for (class.nested_classes) |nested| {
            try self.lintClass(nested, file, report);
        }

        // Lint nested enums
        for (class.nested_enums) |nested_enum| {
            try self.lintEnum(nested_enum, file, report);
        }
    }

    fn lintMethod(self: *Self, method: types.Method, class_name: []const u8, file: []const u8, report: *LintReport) !void {
        // Build method name
        const method_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method.name });
        defer self.allocator.free(method_name);

        if (method.doc) |doc| {
            // Check brief
            try self.checkBrief(doc, method_name, "method", file, method.location.line, report);

            // Check params
            if (self.config.require_param_docs) {
                try self.checkParams(doc, method.params, method_name, "method", file, method.location.line, report);
            }

            // Check return (skip constructors/destructors)
            if (self.config.require_return_docs and
                method.kind != .constructor and
                method.kind != .destructor and
                method.kind != .copy_constructor and
                method.kind != .move_constructor)
            {
                try self.checkReturn(doc, method.return_type, method_name, "method", file, method.location.line, report);
            }

            // Check cross-references
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, method_name, "method", file, method.location.line, report);
            }
        } else {
            // No documentation - create a copy of the name for the report
            const name_copy = try self.allocator.dupe(u8, method_name);
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = method.location.line,
                .entity_name = name_copy,
                .entity_type = "method",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintStruct(self: *Self, strct: types.Struct, file: []const u8, report: *LintReport) !void {
        if (strct.doc) |doc| {
            try self.checkBrief(doc, strct.name, "struct", file, strct.location.line, report);
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, strct.name, "struct", file, strct.location.line, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = strct.location.line,
                .entity_name = strct.name,
                .entity_type = "struct",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintEnum(self: *Self, enm: types.Enum, file: []const u8, report: *LintReport) !void {
        if (enm.doc) |doc| {
            try self.checkBrief(doc, enm.name, "enum", file, enm.location.line, report);
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, enm.name, "enum", file, enm.location.line, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = enm.location.line,
                .entity_name = enm.name,
                .entity_type = "enum",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintMacro(self: *Self, macro: types.Macro, file: []const u8, report: *LintReport) !void {
        if (macro.doc) |doc| {
            try self.checkBrief(doc, macro.name, "macro", file, macro.location.line, report);

            // Check macro parameters
            if (self.config.require_param_docs and macro.params != null) {
                try self.checkMacroParams(doc, macro.params.?, macro.name, file, macro.location.line, report);
            }

            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, macro.name, "macro", file, macro.location.line, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = macro.location.line,
                .entity_name = macro.name,
                .entity_type = "macro",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintTypedef(self: *Self, td: types.Typedef, file: []const u8, report: *LintReport) !void {
        if (td.doc) |doc| {
            try self.checkBrief(doc, td.name, "typedef", file, td.location.line, report);
            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, td.name, "typedef", file, td.location.line, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = td.location.line,
                .entity_name = td.name,
                .entity_type = "typedef",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintTypeAlias(self: *Self, alias: types.TypeAlias, file: []const u8, report: *LintReport) !void {
        if (alias.docstring) |doc| {
            try self.checkBrief(doc, alias.name, "type_alias", file, 0, report);

            if (self.config.require_tparam_docs) {
                try self.checkTparams(doc, alias.template_params, alias.name, "type_alias", file, 0, report);
            }

            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, alias.name, "type_alias", file, 0, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = 0,
                .entity_name = alias.name,
                .entity_type = "type_alias",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    fn lintConcept(self: *Self, concept: types.Concept, file: []const u8, report: *LintReport) !void {
        if (concept.docstring) |doc| {
            try self.checkBrief(doc, concept.name, "concept", file, 0, report);

            if (self.config.require_tparam_docs) {
                try self.checkTparams(doc, concept.template_params, concept.name, "concept", file, 0, report);
            }

            if (self.config.check_cross_references) {
                try self.checkCrossReferences(doc, concept.name, "concept", file, 0, report);
            }
        } else {
            _ = try self.addIssueWithRuleCheck(report, .{
                .file = file,
                .line = 0,
                .entity_name = concept.name,
                .entity_type = "concept",
                .severity = .warning,
                .code = "W001",
                .message = "no documentation",
            });
        }
    }

    // =========================================================================
    // Check helpers
    // =========================================================================

    fn checkBrief(self: *Self, doc: types.DocString, entity_name: []const u8, entity_type: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        if (self.config.require_brief) {
            if (doc.brief == null or doc.brief.?.len == 0) {
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W002",
                    .message = "empty @brief description",
                });
                return;
            }
        }

        if (doc.brief) |brief| {
            // Check brief length
            if (brief.len > self.config.max_brief_length) {
                const msg = try std.fmt.allocPrint(self.allocator, "@brief exceeds {d} characters ({d} chars)", .{ self.config.max_brief_length, brief.len });
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .info,
                    .code = "I001",
                    .message = msg,
                });
            }

            // Check for period at end
            if (self.config.require_brief_period and brief.len > 0) {
                const last_char = brief[brief.len - 1];
                if (last_char != '.' and last_char != '!' and last_char != '?') {
                    _ = try self.addIssueWithRuleCheck(report, .{
                        .file = file,
                        .line = line,
                        .entity_name = entity_name,
                        .entity_type = entity_type,
                        .severity = .info,
                        .code = "I002",
                        .message = "@brief missing period at end",
                    });
                }
            }
        }
    }

    fn checkParams(self: *Self, doc: types.DocString, params: []const types.Parameter, entity_name: []const u8, entity_type: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        // Check for duplicate @param documentation and empty descriptions
        var seen_params = std.StringHashMap(void).init(self.allocator);
        defer seen_params.deinit();

        for (doc.params) |doc_param| {
            if (seen_params.contains(doc_param.name)) {
                const msg = try std.fmt.allocPrint(self.allocator, "duplicate @param for '{s}'", .{doc_param.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W008",
                    .message = msg,
                });
            } else {
                try seen_params.put(doc_param.name, {});
            }

            // Check for empty description
            const trimmed_desc = std.mem.trim(u8, doc_param.description, " \t\n\r");
            if (trimmed_desc.len == 0) {
                const msg = try std.fmt.allocPrint(self.allocator, "empty @param description for '{s}'", .{doc_param.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .info,
                    .code = "W010",
                    .message = msg,
                });
            }
        }

        // Check for missing @param documentation
        for (params) |param| {
            var found = false;
            for (doc.params) |doc_param| {
                if (std.mem.eql(u8, doc_param.name, param.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                const msg = try std.fmt.allocPrint(self.allocator, "missing @param for '{s}'", .{param.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W003",
                    .message = msg,
                });
            }
        }

        // Check for @param referencing non-existent parameters
        for (doc.params) |doc_param| {
            var found = false;
            for (params) |param| {
                if (std.mem.eql(u8, param.name, doc_param.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                const msg = try std.fmt.allocPrint(self.allocator, "@param '{s}' does not match any parameter", .{doc_param.name});
                const suggestion = try self.findSimilarParam(doc_param.name, params);
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .@"error",
                    .code = "E001",
                    .message = msg,
                    .suggestion = suggestion,
                });
            }
        }
    }

    fn checkMacroParams(self: *Self, doc: types.DocString, params: []const []const u8, entity_name: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        // Check for missing @param documentation
        for (params) |param| {
            var found = false;
            for (doc.params) |doc_param| {
                if (std.mem.eql(u8, doc_param.name, param)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                const msg = try std.fmt.allocPrint(self.allocator, "missing @param for '{s}'", .{param});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = "macro",
                    .severity = .warning,
                    .code = "W003",
                    .message = msg,
                });
            }
        }
    }

    fn checkTparams(self: *Self, doc: types.DocString, tparams: []const types.TemplateParam, entity_name: []const u8, entity_type: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        // Check for duplicate @tparam documentation
        var seen_tparams = std.StringHashMap(void).init(self.allocator);
        defer seen_tparams.deinit();

        for (doc.tparams) |doc_tparam| {
            if (seen_tparams.contains(doc_tparam.name)) {
                const msg = try std.fmt.allocPrint(self.allocator, "duplicate @tparam for '{s}'", .{doc_tparam.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W009",
                    .message = msg,
                });
            } else {
                try seen_tparams.put(doc_tparam.name, {});
            }

            // Check for empty description
            const trimmed_desc = std.mem.trim(u8, doc_tparam.description, " \t\n\r");
            if (trimmed_desc.len == 0) {
                const msg = try std.fmt.allocPrint(self.allocator, "empty @tparam description for '{s}'", .{doc_tparam.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .info,
                    .code = "W011",
                    .message = msg,
                });
            }
        }

        // Check for missing @tparam documentation
        for (tparams) |tparam| {
            var found = false;
            for (doc.tparams) |doc_tparam| {
                if (std.mem.eql(u8, doc_tparam.name, tparam.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                const msg = try std.fmt.allocPrint(self.allocator, "missing @tparam for '{s}'", .{tparam.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W004",
                    .message = msg,
                });
            }
        }

        // Check for @tparam referencing non-existent template parameters
        for (doc.tparams) |doc_tparam| {
            var found = false;
            for (tparams) |tparam| {
                if (std.mem.eql(u8, tparam.name, doc_tparam.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                const msg = try std.fmt.allocPrint(self.allocator, "@tparam '{s}' does not match any template parameter", .{doc_tparam.name});
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .@"error",
                    .code = "E002",
                    .message = msg,
                });
            }
        }
    }

    fn checkReturn(self: *Self, doc: types.DocString, return_type: []const u8, entity_name: []const u8, entity_type: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        const is_void = isVoidReturn(return_type);

        if (is_void) {
            // Void function should not have @return
            if (doc.returns != null or doc.retvals.len > 0) {
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W006",
                    .message = "@return present for void function",
                });
            }
        } else {
            // Non-void function should have @return
            if (doc.returns == null and doc.retvals.len == 0) {
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W005",
                    .message = "missing @return for non-void function",
                });
            } else if (doc.returns) |returns| {
                // Check for empty @return description
                const trimmed_desc = std.mem.trim(u8, returns, " \t\n\r");
                if (trimmed_desc.len == 0) {
                    _ = try self.addIssueWithRuleCheck(report, .{
                        .file = file,
                        .line = line,
                        .entity_name = entity_name,
                        .entity_type = entity_type,
                        .severity = .info,
                        .code = "W012",
                        .message = "empty @return description",
                    });
                }
            }
        }
    }

    fn checkCrossReferences(self: *Self, doc: types.DocString, entity_name: []const u8, entity_type: []const u8, file: []const u8, line: u32, report: *LintReport) !void {
        // Check @see references
        for (doc.see_also) |ref| {
            if (!self.symbolExists(ref)) {
                const msg = try std.fmt.allocPrint(self.allocator, "@see '{s}' - symbol not found", .{ref});
                const suggestion = try self.findSimilarSymbol(ref);
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .warning,
                    .code = "W007",
                    .message = msg,
                    .suggestion = suggestion,
                });
            }
        }

        // Check @copydoc target
        if (doc.copydoc_target) |target| {
            if (!self.symbolExists(target)) {
                const msg = try std.fmt.allocPrint(self.allocator, "@copydoc '{s}' - target not found", .{target});
                const suggestion = try self.findSimilarSymbol(target);
                _ = try self.addIssueWithRuleCheck(report, .{
                    .file = file,
                    .line = line,
                    .entity_name = entity_name,
                    .entity_type = entity_type,
                    .severity = .@"error",
                    .code = "E003",
                    .message = msg,
                    .suggestion = suggestion,
                });
            }
        }
    }

    // =========================================================================
    // Helper functions
    // =========================================================================

    fn shouldExclude(self: *Self, name: []const u8) bool {
        for (self.config.exclude_patterns) |pattern| {
            if (globMatch(pattern, name)) {
                return true;
            }
        }
        return false;
    }

    fn symbolExists(self: *Self, name: []const u8) bool {
        if (self.symbol_table) |table| {
            return table.lookup(name) != null;
        }
        // If no symbol table, assume symbol exists
        return true;
    }

    fn findSimilarParam(self: *Self, name: []const u8, params: []const types.Parameter) !?[]const u8 {
        var best_match: ?[]const u8 = null;
        var best_distance: usize = 3; // Max edit distance to consider

        for (params) |param| {
            const dist = levenshteinDistance(name, param.name);
            if (dist < best_distance) {
                best_distance = dist;
                best_match = param.name;
            }
        }

        if (best_match) |match| {
            return try std.fmt.allocPrint(self.allocator, "Did you mean '{s}'?", .{match});
        }
        return null;
    }

    fn findSimilarSymbol(self: *Self, name: []const u8) !?[]const u8 {
        if (self.symbol_table == null) return null;

        // For now, just return null - implementing full fuzzy search would be complex
        // Could be enhanced later to search the symbol table for similar names
        _ = name;
        return null;
    }
};

// =========================================================================
// Utility functions
// =========================================================================

fn isVoidReturn(return_type: []const u8) bool {
    const trimmed = std.mem.trim(u8, return_type, " \t");
    return std.mem.eql(u8, trimmed, "void") or trimmed.len == 0;
}

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

/// Simple Levenshtein distance for typo detection
fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Use a simple implementation for short strings
    if (a.len > 20 or b.len > 20) return 100; // Too long, don't bother

    var prev_row: [21]usize = undefined;
    var curr_row: [21]usize = undefined;

    for (0..b.len + 1) |j| {
        prev_row[j] = j;
    }

    for (a, 0..) |ca, i| {
        curr_row[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (ca == cb) 0 else 1;
            curr_row[j + 1] = @min(@min(curr_row[j] + 1, prev_row[j + 1] + 1), prev_row[j] + cost);
        }
        @memcpy(prev_row[0 .. b.len + 1], curr_row[0 .. b.len + 1]);
    }

    return prev_row[b.len];
}

/// Prints the lint report to stderr
pub fn printReport(report: LintReport) void {
    if (report.issues.items.len == 0) {
        std.debug.print("stig lint: No issues found\n", .{});
        return;
    }

    std.debug.print("\nstig lint: {d} error(s), {d} warning(s), {d} info\n\n", .{
        report.error_count,
        report.warning_count,
        report.info_count,
    });

    // Group by file
    var current_file: []const u8 = "";
    for (report.issues.items) |issue| {
        if (!std.mem.eql(u8, issue.file, current_file)) {
            current_file = issue.file;
            std.debug.print("{s}:\n", .{current_file});
        }

        // Format: file:line: severity[code]: message
        if (issue.line > 0) {
            std.debug.print("  {d}: {s}[{s}]: {s}\n", .{
                issue.line,
                issue.severity.toString(),
                issue.code,
                issue.message,
            });
        } else {
            std.debug.print("  {s}[{s}]: {s}\n", .{
                issue.severity.toString(),
                issue.code,
                issue.message,
            });
        }

        // Print entity context
        std.debug.print("    in {s} '{s}'\n", .{ issue.entity_type, issue.entity_name });

        // Print suggestion if available
        if (issue.suggestion) |sug| {
            std.debug.print("    {s}\n", .{sug});
        }
    }

    std.debug.print("\n", .{});
}

// =========================================================================
// Tests
// =========================================================================

test "levenshtein distance" {
    try std.testing.expectEqual(@as(usize, 0), levenshteinDistance("test", "test"));
    try std.testing.expectEqual(@as(usize, 1), levenshteinDistance("test", "tests"));
    try std.testing.expectEqual(@as(usize, 1), levenshteinDistance("test", "tset"));
    try std.testing.expectEqual(@as(usize, 2), levenshteinDistance("test", "best"));
    try std.testing.expectEqual(@as(usize, 4), levenshteinDistance("", "test"));
}

test "glob match" {
    try std.testing.expect(globMatch("test_*", "test_foo"));
    try std.testing.expect(globMatch("*_internal", "foo_internal"));
    try std.testing.expect(globMatch("*", "anything"));
    try std.testing.expect(!globMatch("test_*", "foo_test"));
}

test "is void return" {
    try std.testing.expect(isVoidReturn("void"));
    try std.testing.expect(isVoidReturn(" void "));
    try std.testing.expect(isVoidReturn(""));
    try std.testing.expect(!isVoidReturn("int"));
    try std.testing.expect(!isVoidReturn("void*"));
}

test "lint empty module" {
    var linter = Linter.init(std.testing.allocator, .{});
    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{},
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    var report = try linter.lint(&modules);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.issues.items.len);
}

test "lint undocumented function" {
    var linter = Linter.init(std.testing.allocator, .{});
    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "undocumented_func",
                    .return_type = "void",
                    .params = &[_]types.Parameter{},
                    .doc = null,
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    var report = try linter.lint(&modules);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 1), report.issues.items.len);
    try std.testing.expectEqualStrings("W001", report.issues.items[0].code);
}

test "lint with per-rule configuration - ignore rule" {
    // Configure W001 to be ignored
    const rules = [_]config_mod.Config.RuleConfig{
        .{ .code = "W001", .severity = .ignore },
    };
    var linter = Linter.init(std.testing.allocator, .{
        .rules = &rules,
    });
    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "undocumented_func",
                    .return_type = "void",
                    .params = &[_]types.Parameter{},
                    .doc = null,
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    var report = try linter.lint(&modules);
    defer report.deinit();

    // W001 should be ignored, so no issues
    try std.testing.expectEqual(@as(usize, 0), report.issues.items.len);
}

test "lint with per-rule configuration - change severity" {
    // Configure W001 to be an error instead of warning
    const rules = [_]config_mod.Config.RuleConfig{
        .{ .code = "W001", .severity = .@"error" },
    };
    var linter = Linter.init(std.testing.allocator, .{
        .rules = &rules,
    });
    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "undocumented_func",
                    .return_type = "void",
                    .params = &[_]types.Parameter{},
                    .doc = null,
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    var report = try linter.lint(&modules);
    defer report.deinit();

    // W001 should now be an error
    try std.testing.expectEqual(@as(usize, 1), report.issues.items.len);
    try std.testing.expectEqual(Severity.@"error", report.issues.items[0].severity);
    try std.testing.expectEqual(@as(usize, 1), report.error_count);
    try std.testing.expectEqual(@as(usize, 0), report.warning_count);
}
