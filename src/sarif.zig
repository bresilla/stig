const std = @import("std");
const types = @import("model/types.zig");
const Config = @import("config.zig").Config;
const cli = @import("cli.zig");

/// SARIF version
const sarif_version = "2.1.0";
const sarif_schema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json";

/// Tool information
const tool_name = "stig";
const tool_version = cli.VERSION;
const tool_uri = "https://github.com/bresilla/stig";

/// Lint result for SARIF output
pub const LintResult = struct {
    rule_id: []const u8,
    message: []const u8,
    level: Level,
    file: []const u8,
    line: u32,
    column: u32 = 1,

    pub const Level = enum {
        note,
        warning,
        @"error",
    };
};

/// SARIF Generator - creates SARIF output with stig extensions
pub const SarifGenerator = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .output = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// Generate SARIF output with full documentation model
    pub fn generate(
        self: *Self,
        modules: []const types.Module,
        config: Config,
        lint_results: []const LintResult,
    ) ![]const u8 {
        const writer = self.output.writer(self.allocator);

        try writer.writeAll("{\n");
        try writer.writeAll("  \"$schema\": \"");
        try writer.writeAll(sarif_schema);
        try writer.writeAll("\",\n");
        try writer.writeAll("  \"version\": \"");
        try writer.writeAll(sarif_version);
        try writer.writeAll("\",\n");
        try writer.writeAll("  \"runs\": [{\n");

        // Tool section
        try self.writeTool(writer);

        // Results section (lint findings)
        try self.writeResults(writer, lint_results);

        // Properties section (stig extensions with full doc model)
        try self.writeProperties(writer, modules, config);

        try writer.writeAll("  }]\n");
        try writer.writeAll("}\n");

        return self.output.items;
    }

    fn writeTool(self: *Self, writer: anytype) !void {
        _ = self;
        try writer.writeAll("    \"tool\": {\n");
        try writer.writeAll("      \"driver\": {\n");
        try writer.writeAll("        \"name\": \"");
        try writer.writeAll(tool_name);
        try writer.writeAll("\",\n");
        try writer.writeAll("        \"version\": \"");
        try writer.writeAll(tool_version);
        try writer.writeAll("\",\n");
        try writer.writeAll("        \"informationUri\": \"");
        try writer.writeAll(tool_uri);
        try writer.writeAll("\"\n");
        try writer.writeAll("      }\n");
        try writer.writeAll("    },\n");
    }

    fn writeResults(self: *Self, writer: anytype, results: []const LintResult) !void {
        try writer.writeAll("    \"results\": [");

        for (results, 0..) |result, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n      {\n");

            try writer.writeAll("        \"ruleId\": \"");
            try self.writeJsonString(writer, result.rule_id);
            try writer.writeAll("\",\n");

            try writer.writeAll("        \"level\": \"");
            try writer.writeAll(switch (result.level) {
                .note => "note",
                .warning => "warning",
                .@"error" => "error",
            });
            try writer.writeAll("\",\n");

            try writer.writeAll("        \"message\": {\n");
            try writer.writeAll("          \"text\": \"");
            try self.writeJsonString(writer, result.message);
            try writer.writeAll("\"\n");
            try writer.writeAll("        },\n");

            try writer.writeAll("        \"locations\": [{\n");
            try writer.writeAll("          \"physicalLocation\": {\n");
            try writer.writeAll("            \"artifactLocation\": {\n");
            try writer.writeAll("              \"uri\": \"");
            try self.writeJsonString(writer, result.file);
            try writer.writeAll("\"\n");
            try writer.writeAll("            },\n");
            try writer.writeAll("            \"region\": {\n");
            try writer.print("              \"startLine\": {d},\n", .{result.line});
            try writer.print("              \"startColumn\": {d}\n", .{result.column});
            try writer.writeAll("            }\n");
            try writer.writeAll("          }\n");
            try writer.writeAll("        }]\n");

            try writer.writeAll("      }");
        }

        try writer.writeAll("\n    ],\n");
    }

    fn writeProperties(self: *Self, writer: anytype, modules: []const types.Module, config: Config) !void {
        try writer.writeAll("    \"properties\": {\n");

        // stig:version
        try writer.writeAll("      \"stig:version\": \"1.0\",\n");

        // stig:config
        try self.writeConfig(writer, config);

        // stig:modules (full documentation model)
        try self.writeModules(writer, modules);

        try writer.writeAll("    }\n");
    }

    fn writeConfig(self: *Self, writer: anytype, config: Config) !void {
        try writer.writeAll("      \"stig:config\": {\n");
        try writer.writeAll("        \"title\": \"");
        try self.writeJsonString(writer, config.title);
        try writer.writeAll("\",\n");
        try writer.writeAll("        \"grouping\": \"");
        try writer.writeAll(switch (config.grouping) {
            .by_header => "by_header",
            .by_prefix => "by_prefix",
            .flat => "flat",
            .by_module => "by_module",
        });
        try writer.writeAll("\"\n");
        try writer.writeAll("      },\n");
    }

    fn writeModules(self: *Self, writer: anytype, modules: []const types.Module) !void {
        try writer.writeAll("      \"stig:modules\": [");

        for (modules, 0..) |module, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n        ");
            try self.writeModule(writer, module);
        }

        try writer.writeAll("\n      ]\n");
    }

    fn writeModule(self: *Self, writer: anytype, module: types.Module) !void {
        try writer.writeAll("{\n");

        // Module name
        try writer.writeAll("          \"name\": \"");
        try self.writeJsonString(writer, module.name);
        try writer.writeAll("\",\n");

        // File documentation
        if (module.file_doc) |doc| {
            try writer.writeAll("          \"fileDoc\": ");
            try self.writeDocString(writer, doc, 10);
            try writer.writeAll(",\n");
        }

        // Functions
        try writer.writeAll("          \"functions\": [");
        for (module.functions, 0..) |func, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeFunction(writer, func);
        }
        try writer.writeAll("\n          ],\n");

        // Classes
        try writer.writeAll("          \"classes\": [");
        for (module.classes, 0..) |class, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeClass(writer, class);
        }
        try writer.writeAll("\n          ],\n");

        // Structs
        try writer.writeAll("          \"structs\": [");
        for (module.structs, 0..) |s, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeStruct(writer, s);
        }
        try writer.writeAll("\n          ],\n");

        // Enums
        try writer.writeAll("          \"enums\": [");
        for (module.enums, 0..) |e, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeEnum(writer, e);
        }
        try writer.writeAll("\n          ],\n");

        // Typedefs
        try writer.writeAll("          \"typedefs\": [");
        for (module.typedefs, 0..) |t, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeTypedef(writer, t);
        }
        try writer.writeAll("\n          ],\n");

        // Macros
        try writer.writeAll("          \"macros\": [");
        for (module.macros, 0..) |m, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeMacro(writer, m);
        }
        try writer.writeAll("\n          ],\n");

        // Type aliases
        try writer.writeAll("          \"typeAliases\": [");
        for (module.type_aliases, 0..) |ta, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeTypeAlias(writer, ta);
        }
        try writer.writeAll("\n          ],\n");

        // Concepts
        try writer.writeAll("          \"concepts\": [");
        for (module.concepts, 0..) |c, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writeConcept(writer, c);
        }
        try writer.writeAll("\n          ],\n");

        // Pages
        try writer.writeAll("          \"pages\": [");
        for (module.pages, 0..) |p, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n            ");
            try self.writePage(writer, p);
        }
        try writer.writeAll("\n          ]\n");

        try writer.writeAll("        }");
    }

    fn writeFunction(self: *Self, writer: anytype, func: types.Function) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, func.name);
        try writer.writeAll("\", ");

        try writer.writeAll("\"returnType\": \"");
        try self.writeJsonString(writer, func.return_type);
        try writer.writeAll("\", ");

        // Parameters
        try writer.writeAll("\"params\": [");
        for (func.params, 0..) |param, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll("{\"name\": \"");
            try self.writeJsonString(writer, param.name);
            try writer.writeAll("\", \"type\": \"");
            try self.writeJsonString(writer, param.type_str);
            try writer.writeAll("\"}");
        }
        try writer.writeAll("], ");

        // Location
        try writer.writeAll("\"location\": {\"file\": \"");
        try self.writeJsonString(writer, func.location.file);
        try writer.print("\", \"line\": {d}}}", .{func.location.line});

        // Doc
        if (func.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        // Flags
        if (func.is_static) try writer.writeAll(", \"isStatic\": true");
        if (func.is_inline) try writer.writeAll(", \"isInline\": true");
        if (func.is_constexpr) try writer.writeAll(", \"isConstexpr\": true");
        if (func.is_noexcept) try writer.writeAll(", \"isNoexcept\": true");

        // Template params
        if (func.template_params.len > 0) {
            try writer.writeAll(", \"templateParams\": [");
            for (func.template_params, 0..) |tp, i| {
                if (i > 0) try writer.writeAll(", ");
                try self.writeTemplateParam(writer, tp);
            }
            try writer.writeAll("]");
        }

        try writer.writeAll("}");
    }

    fn writeClass(self: *Self, writer: anytype, class: types.Class) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, class.name);
        try writer.writeAll("\"");

        if (class.namespace) |ns| {
            try writer.writeAll(", \"namespace\": \"");
            try self.writeJsonString(writer, ns);
            try writer.writeAll("\"");
        }

        // Location
        try writer.writeAll(", \"location\": {\"file\": \"");
        try self.writeJsonString(writer, class.location.file);
        try writer.print("\", \"line\": {d}}}", .{class.location.line});

        // Base classes
        if (class.base_classes.len > 0) {
            try writer.writeAll(", \"baseClasses\": [");
            for (class.base_classes, 0..) |bc, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("{\"name\": \"");
                try self.writeJsonString(writer, bc.name);
                try writer.writeAll("\", \"access\": \"");
                try writer.writeAll(switch (bc.access) {
                    .public => "public",
                    .protected => "protected",
                    .private => "private",
                });
                try writer.writeAll("\"}");
            }
            try writer.writeAll("]");
        }

        // Methods
        try writer.writeAll(", \"methods\": [");
        for (class.methods, 0..) |method, i| {
            if (i > 0) try writer.writeAll(", ");
            try self.writeMethod(writer, method);
        }
        try writer.writeAll("]");

        // Fields
        try writer.writeAll(", \"fields\": [");
        for (class.fields, 0..) |field, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll("{\"name\": \"");
            try self.writeJsonString(writer, field.name);
            try writer.writeAll("\", \"type\": \"");
            try self.writeJsonString(writer, field.type_str);
            try writer.writeAll("\", \"access\": \"");
            try writer.writeAll(switch (field.access) {
                .public => "public",
                .protected => "protected",
                .private => "private",
            });
            try writer.writeAll("\"}");
        }
        try writer.writeAll("]");

        // Doc
        if (class.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        // Template params
        if (class.template_params.len > 0) {
            try writer.writeAll(", \"templateParams\": [");
            for (class.template_params, 0..) |tp, i| {
                if (i > 0) try writer.writeAll(", ");
                try self.writeTemplateParam(writer, tp);
            }
            try writer.writeAll("]");
        }

        try writer.writeAll("}");
    }

    fn writeMethod(self: *Self, writer: anytype, method: types.Method) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, method.name);
        try writer.writeAll("\", ");

        try writer.writeAll("\"returnType\": \"");
        try self.writeJsonString(writer, method.return_type);
        try writer.writeAll("\", ");

        try writer.writeAll("\"access\": \"");
        try writer.writeAll(switch (method.access) {
            .public => "public",
            .protected => "protected",
            .private => "private",
        });
        try writer.writeAll("\"");

        // Parameters
        try writer.writeAll(", \"params\": [");
        for (method.params, 0..) |param, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll("{\"name\": \"");
            try self.writeJsonString(writer, param.name);
            try writer.writeAll("\", \"type\": \"");
            try self.writeJsonString(writer, param.type_str);
            try writer.writeAll("\"}");
        }
        try writer.writeAll("]");

        // Kind
        if (method.kind != .regular) {
            try writer.writeAll(", \"kind\": \"");
            try writer.writeAll(switch (method.kind) {
                .regular => "regular",
                .constructor => "constructor",
                .copy_constructor => "copy_constructor",
                .move_constructor => "move_constructor",
                .destructor => "destructor",
                .operator_overload => "operator",
                .conversion_operator => "conversion",
            });
            try writer.writeAll("\"");
        }

        // Flags
        if (method.is_virtual) try writer.writeAll(", \"isVirtual\": true");
        if (method.is_static) try writer.writeAll(", \"isStatic\": true");
        if (method.is_const) try writer.writeAll(", \"isConst\": true");
        if (method.is_override) try writer.writeAll(", \"isOverride\": true");
        if (method.is_pure_virtual) try writer.writeAll(", \"isPureVirtual\": true");

        // Doc
        if (method.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 14);
        }

        try writer.writeAll("}");
    }

    fn writeStruct(self: *Self, writer: anytype, s: types.Struct) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, s.name);
        try writer.writeAll("\"");

        // Location
        try writer.writeAll(", \"location\": {\"file\": \"");
        try self.writeJsonString(writer, s.location.file);
        try writer.print("\", \"line\": {d}}}", .{s.location.line});

        // Fields
        try writer.writeAll(", \"fields\": [");
        for (s.fields, 0..) |field, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll("{\"name\": \"");
            try self.writeJsonString(writer, field.name);
            try writer.writeAll("\", \"type\": \"");
            try self.writeJsonString(writer, field.type_str);
            try writer.writeAll("\"}");
        }
        try writer.writeAll("]");

        // Doc
        if (s.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writeEnum(self: *Self, writer: anytype, e: types.Enum) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, e.name);
        try writer.writeAll("\"");

        // Location
        try writer.writeAll(", \"location\": {\"file\": \"");
        try self.writeJsonString(writer, e.location.file);
        try writer.print("\", \"line\": {d}}}", .{e.location.line});

        // Values
        try writer.writeAll(", \"values\": [");
        for (e.values, 0..) |val, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll("{\"name\": \"");
            try self.writeJsonString(writer, val.name);
            try writer.writeAll("\"");
            if (val.value) |v| {
                try writer.print(", \"value\": {d}", .{v});
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("]");

        // Doc
        if (e.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writeTypedef(self: *Self, writer: anytype, t: types.Typedef) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, t.name);
        try writer.writeAll("\", \"underlying\": \"");
        try self.writeJsonString(writer, t.underlying);
        try writer.writeAll("\"");

        // Location
        try writer.writeAll(", \"location\": {\"file\": \"");
        try self.writeJsonString(writer, t.location.file);
        try writer.print("\", \"line\": {d}}}", .{t.location.line});

        // Doc
        if (t.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writeMacro(self: *Self, writer: anytype, m: types.Macro) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, m.name);
        try writer.writeAll("\"");

        // Params (for function-like macros)
        if (m.params) |params| {
            try writer.writeAll(", \"params\": [");
            for (params, 0..) |p, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.writeJsonString(writer, p);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        }

        // Body
        try writer.writeAll(", \"body\": \"");
        try self.writeJsonString(writer, m.body);
        try writer.writeAll("\"");

        // Location
        try writer.writeAll(", \"location\": {\"file\": \"");
        try self.writeJsonString(writer, m.location.file);
        try writer.print("\", \"line\": {d}}}", .{m.location.line});

        // Doc
        if (m.doc) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writeTypeAlias(self: *Self, writer: anytype, ta: types.TypeAlias) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, ta.name);
        try writer.writeAll("\", \"underlyingType\": \"");
        try self.writeJsonString(writer, ta.underlying_type);
        try writer.writeAll("\"");

        if (ta.namespace) |ns| {
            try writer.writeAll(", \"namespace\": \"");
            try self.writeJsonString(writer, ns);
            try writer.writeAll("\"");
        }

        // Doc
        if (ta.docstring) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writeConcept(self: *Self, writer: anytype, c: types.Concept) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"name\": \"");
        try self.writeJsonString(writer, c.name);
        try writer.writeAll("\", \"constraint\": \"");
        try self.writeJsonString(writer, c.constraint);
        try writer.writeAll("\"");

        if (c.namespace) |ns| {
            try writer.writeAll(", \"namespace\": \"");
            try self.writeJsonString(writer, ns);
            try writer.writeAll("\"");
        }

        // Template params
        if (c.template_params.len > 0) {
            try writer.writeAll(", \"templateParams\": [");
            for (c.template_params, 0..) |tp, i| {
                if (i > 0) try writer.writeAll(", ");
                try self.writeTemplateParam(writer, tp);
            }
            try writer.writeAll("]");
        }

        // Doc
        if (c.docstring) |doc| {
            try writer.writeAll(", \"doc\": ");
            try self.writeDocString(writer, doc, 12);
        }

        try writer.writeAll("}");
    }

    fn writePage(self: *Self, writer: anytype, p: types.Page) !void {
        try writer.writeAll("{");

        try writer.writeAll("\"id\": \"");
        try self.writeJsonString(writer, p.id);
        try writer.writeAll("\", \"title\": \"");
        try self.writeJsonString(writer, p.title);
        try writer.writeAll("\", \"content\": \"");
        try self.writeJsonString(writer, p.content);
        try writer.writeAll("\"");

        if (p.is_mainpage) {
            try writer.writeAll(", \"isMainpage\": true");
        }

        try writer.writeAll("}");
    }

    fn writeTemplateParam(self: *Self, writer: anytype, tp: types.TemplateParam) !void {
        try writer.writeAll("{\"name\": \"");
        try self.writeJsonString(writer, tp.name);
        try writer.writeAll("\", \"kind\": \"");
        try self.writeJsonString(writer, tp.kind);
        try writer.writeAll("\"");
        if (tp.is_variadic) try writer.writeAll(", \"isVariadic\": true");
        if (tp.default_value) |dv| {
            try writer.writeAll(", \"default\": \"");
            try self.writeJsonString(writer, dv);
            try writer.writeAll("\"");
        }
        try writer.writeAll("}");
    }

    fn writeDocString(self: *Self, writer: anytype, doc: types.DocString, indent: usize) !void {
        _ = indent;
        try writer.writeAll("{");

        // Brief
        if (doc.brief) |brief| {
            try writer.writeAll("\"brief\": \"");
            try self.writeJsonString(writer, brief);
            try writer.writeAll("\"");
        } else {
            try writer.writeAll("\"brief\": null");
        }

        // Details
        if (doc.details) |details| {
            try writer.writeAll(", \"details\": \"");
            try self.writeJsonString(writer, details);
            try writer.writeAll("\"");
        }

        // Params
        if (doc.params.len > 0) {
            try writer.writeAll(", \"params\": [");
            for (doc.params, 0..) |param, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("{\"name\": \"");
                try self.writeJsonString(writer, param.name);
                try writer.writeAll("\", \"description\": \"");
                try self.writeJsonString(writer, param.description);
                try writer.writeAll("\"}");
            }
            try writer.writeAll("]");
        }

        // Returns
        if (doc.returns) |ret| {
            try writer.writeAll(", \"returns\": \"");
            try self.writeJsonString(writer, ret);
            try writer.writeAll("\"");
        }

        // Deprecated
        if (doc.deprecated) |dep| {
            try writer.writeAll(", \"deprecated\": \"");
            try self.writeJsonString(writer, dep);
            try writer.writeAll("\"");
        }

        // Since
        if (doc.since) |since| {
            try writer.writeAll(", \"since\": \"");
            try self.writeJsonString(writer, since);
            try writer.writeAll("\"");
        }

        // Examples
        if (doc.examples.len > 0) {
            try writer.writeAll(", \"examples\": [");
            for (doc.examples, 0..) |ex, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.writeJsonString(writer, ex);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        }

        // Notes
        if (doc.notes.len > 0) {
            try writer.writeAll(", \"notes\": [");
            for (doc.notes, 0..) |note, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.writeJsonString(writer, note);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        }

        // Warnings
        if (doc.warnings.len > 0) {
            try writer.writeAll(", \"warnings\": [");
            for (doc.warnings, 0..) |warn, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.writeJsonString(writer, warn);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        }

        // See also
        if (doc.see_also.len > 0) {
            try writer.writeAll(", \"seeAlso\": [");
            for (doc.see_also, 0..) |sa, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.writeJsonString(writer, sa);
                try writer.writeAll("\"");
            }
            try writer.writeAll("]");
        }

        // Tparams
        if (doc.tparams.len > 0) {
            try writer.writeAll(", \"tparams\": [");
            for (doc.tparams, 0..) |tp, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("{\"name\": \"");
                try self.writeJsonString(writer, tp.name);
                try writer.writeAll("\", \"description\": \"");
                try self.writeJsonString(writer, tp.description);
                try writer.writeAll("\"}");
            }
            try writer.writeAll("]");
        }

        try writer.writeAll("}");
    }

    fn writeJsonString(self: *Self, writer: anytype, str: []const u8) !void {
        _ = self;
        for (str) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (c < 0x20) {
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "sarif generator basic" {
    const allocator = std.testing.allocator;
    var gen = SarifGenerator.init(allocator);
    defer gen.deinit();

    const modules = [_]types.Module{};
    const config = Config{};
    const results = [_]LintResult{};

    const output = try gen.generate(&modules, config, &results);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"2.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"stig:version\": \"1.0\"") != null);
}
