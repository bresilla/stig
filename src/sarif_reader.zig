const std = @import("std");
const types = @import("model/types.zig");
const Config = @import("config.zig").Config;

/// Error types for SARIF parsing
pub const ParseError = error{
    InvalidJson,
    MissingStigVersion,
    UnsupportedVersion,
    MissingModules,
    InvalidStructure,
    OutOfMemory,
    Overflow,
};

/// Parsed SARIF document
pub const SarifDocument = struct {
    allocator: std.mem.Allocator,
    modules: []types.Module,
    config: SarifConfig,
    lint_results: []const LintResult,
    /// JSON data - kept alive to hold string references
    _json_data: ?std.json.Parsed(std.json.Value) = null,

    pub fn deinit(self: *SarifDocument) void {
        self.allocator.free(self.modules);
        self.allocator.free(self.lint_results);
        if (self._json_data) |*jd| {
            jd.deinit();
        }
    }
};

/// Configuration extracted from SARIF
pub const SarifConfig = struct {
    title: []const u8 = "API Reference",
    grouping: Grouping = .by_header,

    pub const Grouping = enum {
        by_header,
        by_prefix,
        flat,
        by_module,
    };
};

/// Lint result from SARIF
pub const LintResult = struct {
    rule_id: []const u8,
    message: []const u8,
    level: Level,
    file: []const u8,
    line: u32,
    column: u32,

    pub const Level = enum {
        note,
        warning,
        @"error",
    };
};

/// SARIF Reader - parses SARIF JSON back to document model
pub const SarifReader = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Parse SARIF JSON content
    pub fn parse(self: *Self, content: []const u8) ParseError!SarifDocument {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            return ParseError.InvalidJson;
        };
        errdefer parsed.deinit();

        var doc = try self.parseValue(parsed.value);
        doc._json_data = parsed; // Keep JSON data alive for string references
        return doc;
    }

    /// Duplicate a string to owned memory
    fn dupeString(self: *Self, s: []const u8) ParseError![]const u8 {
        return self.allocator.dupe(u8, s) catch return ParseError.OutOfMemory;
    }

    /// Duplicate an optional string to owned memory
    fn dupeOptString(self: *Self, s: ?[]const u8) ParseError!?[]const u8 {
        if (s) |str| {
            return try self.dupeString(str);
        }
        return null;
    }

    fn parseValue(self: *Self, root: std.json.Value) ParseError!SarifDocument {
        // Get runs array
        const runs = root.object.get("runs") orelse return ParseError.InvalidStructure;
        if (runs != .array or runs.array.items.len == 0) {
            return ParseError.InvalidStructure;
        }

        const run = runs.array.items[0];
        if (run != .object) return ParseError.InvalidStructure;

        // Get properties
        const properties = run.object.get("properties") orelse return ParseError.InvalidStructure;
        if (properties != .object) return ParseError.InvalidStructure;

        // Check stig version
        const stig_version = properties.object.get("stig:version") orelse return ParseError.MissingStigVersion;
        if (stig_version != .string or !std.mem.eql(u8, stig_version.string, "1.0")) {
            return ParseError.UnsupportedVersion;
        }

        // Parse config
        const config = self.parseConfig(properties) catch SarifConfig{};

        // Parse modules
        const modules_json = properties.object.get("stig:modules") orelse return ParseError.MissingModules;
        const modules = try self.parseModules(modules_json);

        // Parse lint results
        const results_json = run.object.get("results");
        const lint_results = if (results_json) |r| try self.parseLintResults(r) else &[_]LintResult{};

        return SarifDocument{
            .allocator = self.allocator,
            .modules = modules,
            .config = config,
            .lint_results = lint_results,
        };
    }

    fn parseConfig(self: *Self, properties: std.json.Value) !SarifConfig {
        _ = self;
        const config_json = properties.object.get("stig:config") orelse return SarifConfig{};
        if (config_json != .object) return SarifConfig{};

        var config = SarifConfig{};

        if (config_json.object.get("title")) |title| {
            if (title == .string) config.title = title.string;
        }

        if (config_json.object.get("grouping")) |grouping| {
            if (grouping == .string) {
                if (std.mem.eql(u8, grouping.string, "by_header")) {
                    config.grouping = .by_header;
                } else if (std.mem.eql(u8, grouping.string, "by_prefix")) {
                    config.grouping = .by_prefix;
                } else if (std.mem.eql(u8, grouping.string, "flat")) {
                    config.grouping = .flat;
                } else if (std.mem.eql(u8, grouping.string, "by_module")) {
                    config.grouping = .by_module;
                }
            }
        }

        return config;
    }

    fn parseModules(self: *Self, modules_json: std.json.Value) ParseError![]types.Module {
        if (modules_json != .array) return ParseError.InvalidStructure;

        var modules: std.ArrayList(types.Module) = .empty;
        errdefer modules.deinit(self.allocator);

        for (modules_json.array.items) |module_json| {
            const module = try self.parseModule(module_json);
            modules.append(self.allocator, module) catch return ParseError.OutOfMemory;
        }

        return modules.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseModule(self: *Self, module_json: std.json.Value) ParseError!types.Module {
        if (module_json != .object) return ParseError.InvalidStructure;

        const name = if (module_json.object.get("name")) |n| (if (n == .string) n.string else "") else "";

        // Parse file doc
        const file_doc: ?types.DocString = if (module_json.object.get("fileDoc")) |fd| try self.parseDocString(fd) else null;

        // Parse functions
        const functions = try self.parseFunctions(module_json.object.get("functions"));
        const classes = try self.parseClasses(module_json.object.get("classes"));
        const structs = try self.parseStructs(module_json.object.get("structs"));
        const enums = try self.parseEnums(module_json.object.get("enums"));
        const typedefs = try self.parseTypedefs(module_json.object.get("typedefs"));
        const macros = try self.parseMacros(module_json.object.get("macros"));
        const type_aliases = try self.parseTypeAliases(module_json.object.get("typeAliases"));
        const concepts = try self.parseConcepts(module_json.object.get("concepts"));
        const pages = try self.parsePages(module_json.object.get("pages"));

        return types.Module{
            .name = name,
            .functions = functions,
            .classes = classes,
            .structs = structs,
            .enums = enums,
            .typedefs = typedefs,
            .macros = macros,
            .type_aliases = type_aliases,
            .concepts = concepts,
            .file_doc = file_doc,
            .pages = pages,
        };
    }

    fn parseFunctions(self: *Self, funcs_json: ?std.json.Value) ParseError![]const types.Function {
        const arr = funcs_json orelse return &[_]types.Function{};
        if (arr != .array) return &[_]types.Function{};

        var functions: std.ArrayList(types.Function) = .empty;
        errdefer functions.deinit(self.allocator);

        for (arr.array.items) |func_json| {
            const func = try self.parseFunction(func_json);
            functions.append(self.allocator, func) catch return ParseError.OutOfMemory;
        }

        return functions.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseFunction(self: *Self, func_json: std.json.Value) ParseError!types.Function {
        if (func_json != .object) return ParseError.InvalidStructure;

        const name = self.getString(func_json, "name") orelse "";
        const return_type = self.getString(func_json, "returnType") orelse "";

        // Parse parameters
        const params = try self.parseParameters(func_json.object.get("params"));

        // Parse location
        const location = self.parseLocation(func_json.object.get("location"));

        // Parse doc
        const doc: ?types.DocString = if (func_json.object.get("doc")) |d| try self.parseDocString(d) else null;

        // Parse template params
        const template_params = try self.parseTemplateParams(func_json.object.get("templateParams"));

        return types.Function{
            .name = name,
            .return_type = return_type,
            .params = params,
            .location = location,
            .doc = doc,
            .is_static = self.getBool(func_json, "isStatic"),
            .is_inline = self.getBool(func_json, "isInline"),
            .is_constexpr = self.getBool(func_json, "isConstexpr"),
            .is_noexcept = self.getBool(func_json, "isNoexcept"),
            .template_params = template_params,
        };
    }

    fn parseClasses(self: *Self, classes_json: ?std.json.Value) ParseError![]const types.Class {
        const arr = classes_json orelse return &[_]types.Class{};
        if (arr != .array) return &[_]types.Class{};

        var classes: std.ArrayList(types.Class) = .empty;
        errdefer classes.deinit(self.allocator);

        for (arr.array.items) |class_json| {
            const class = try self.parseClass(class_json);
            classes.append(self.allocator, class) catch return ParseError.OutOfMemory;
        }

        return classes.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseClass(self: *Self, class_json: std.json.Value) ParseError!types.Class {
        if (class_json != .object) return ParseError.InvalidStructure;

        const name = self.getString(class_json, "name") orelse "";
        const namespace = self.getString(class_json, "namespace");
        const location = self.parseLocation(class_json.object.get("location"));
        const doc: ?types.DocString = if (class_json.object.get("doc")) |d| try self.parseDocString(d) else null;

        // Parse base classes
        const base_classes = try self.parseBaseClasses(class_json.object.get("baseClasses"));

        // Parse methods
        const methods = try self.parseMethods(class_json.object.get("methods"));

        // Parse fields
        const fields = try self.parseClassFields(class_json.object.get("fields"));

        // Parse template params
        const template_params = try self.parseTemplateParams(class_json.object.get("templateParams"));

        return types.Class{
            .name = name,
            .namespace = namespace,
            .location = location,
            .doc = doc,
            .base_classes = base_classes,
            .methods = methods,
            .fields = fields,
            .template_params = template_params,
        };
    }

    fn parseMethods(self: *Self, methods_json: ?std.json.Value) ParseError![]const types.Method {
        const arr = methods_json orelse return &[_]types.Method{};
        if (arr != .array) return &[_]types.Method{};

        var methods: std.ArrayList(types.Method) = .empty;
        errdefer methods.deinit(self.allocator);

        for (arr.array.items) |method_json| {
            const method = try self.parseMethod(method_json);
            methods.append(self.allocator, method) catch return ParseError.OutOfMemory;
        }

        return methods.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseMethod(self: *Self, method_json: std.json.Value) ParseError!types.Method {
        if (method_json != .object) return ParseError.InvalidStructure;

        const name = self.getString(method_json, "name") orelse "";
        const return_type = self.getString(method_json, "returnType") orelse "";
        const params = try self.parseParameters(method_json.object.get("params"));
        const doc: ?types.DocString = if (method_json.object.get("doc")) |d| try self.parseDocString(d) else null;

        // Parse access
        const access = self.parseAccess(self.getString(method_json, "access"));

        // Parse kind
        const kind = self.parseMethodKind(self.getString(method_json, "kind"));

        return types.Method{
            .name = name,
            .return_type = return_type,
            .params = params,
            .doc = doc,
            .access = access,
            .kind = kind,
            .is_virtual = self.getBool(method_json, "isVirtual"),
            .is_static = self.getBool(method_json, "isStatic"),
            .is_const = self.getBool(method_json, "isConst"),
            .is_override = self.getBool(method_json, "isOverride"),
            .is_pure_virtual = self.getBool(method_json, "isPureVirtual"),
        };
    }

    fn parseBaseClasses(self: *Self, base_json: ?std.json.Value) ParseError![]const types.BaseClass {
        const arr = base_json orelse return &[_]types.BaseClass{};
        if (arr != .array) return &[_]types.BaseClass{};

        var bases: std.ArrayList(types.BaseClass) = .empty;
        errdefer bases.deinit(self.allocator);

        for (arr.array.items) |bc_json| {
            if (bc_json != .object) continue;
            const bc = types.BaseClass{
                .name = self.getString(bc_json, "name") orelse "",
                .access = self.parseAccess(self.getString(bc_json, "access")),
            };
            bases.append(self.allocator, bc) catch return ParseError.OutOfMemory;
        }

        return bases.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseClassFields(self: *Self, fields_json: ?std.json.Value) ParseError![]const types.ClassField {
        const arr = fields_json orelse return &[_]types.ClassField{};
        if (arr != .array) return &[_]types.ClassField{};

        var fields: std.ArrayList(types.ClassField) = .empty;
        errdefer fields.deinit(self.allocator);

        for (arr.array.items) |field_json| {
            if (field_json != .object) continue;
            const field = types.ClassField{
                .name = self.getString(field_json, "name") orelse "",
                .type_str = self.getString(field_json, "type") orelse "",
                .access = self.parseAccess(self.getString(field_json, "access")),
            };
            fields.append(self.allocator, field) catch return ParseError.OutOfMemory;
        }

        return fields.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseStructs(self: *Self, structs_json: ?std.json.Value) ParseError![]const types.Struct {
        const arr = structs_json orelse return &[_]types.Struct{};
        if (arr != .array) return &[_]types.Struct{};

        var structs: std.ArrayList(types.Struct) = .empty;
        errdefer structs.deinit(self.allocator);

        for (arr.array.items) |struct_json| {
            if (struct_json != .object) continue;

            const s = types.Struct{
                .name = self.getString(struct_json, "name") orelse "",
                .location = self.parseLocation(struct_json.object.get("location")),
                .fields = try self.parseStructFields(struct_json.object.get("fields")),
                .doc = if (struct_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            structs.append(self.allocator, s) catch return ParseError.OutOfMemory;
        }

        return structs.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseStructFields(self: *Self, fields_json: ?std.json.Value) ParseError![]const types.StructField {
        const arr = fields_json orelse return &[_]types.StructField{};
        if (arr != .array) return &[_]types.StructField{};

        var fields: std.ArrayList(types.StructField) = .empty;
        errdefer fields.deinit(self.allocator);

        for (arr.array.items) |field_json| {
            if (field_json != .object) continue;
            const field = types.StructField{
                .name = self.getString(field_json, "name") orelse "",
                .type_str = self.getString(field_json, "type") orelse "",
            };
            fields.append(self.allocator, field) catch return ParseError.OutOfMemory;
        }

        return fields.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseEnums(self: *Self, enums_json: ?std.json.Value) ParseError![]const types.Enum {
        const arr = enums_json orelse return &[_]types.Enum{};
        if (arr != .array) return &[_]types.Enum{};

        var enums: std.ArrayList(types.Enum) = .empty;
        errdefer enums.deinit(self.allocator);

        for (arr.array.items) |enum_json| {
            if (enum_json != .object) continue;

            const e = types.Enum{
                .name = self.getString(enum_json, "name") orelse "",
                .location = self.parseLocation(enum_json.object.get("location")),
                .values = try self.parseEnumValues(enum_json.object.get("values")),
                .doc = if (enum_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            enums.append(self.allocator, e) catch return ParseError.OutOfMemory;
        }

        return enums.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseEnumValues(self: *Self, values_json: ?std.json.Value) ParseError![]const types.EnumValue {
        const arr = values_json orelse return &[_]types.EnumValue{};
        if (arr != .array) return &[_]types.EnumValue{};

        var values: std.ArrayList(types.EnumValue) = .empty;
        errdefer values.deinit(self.allocator);

        for (arr.array.items) |val_json| {
            if (val_json != .object) continue;

            const value: ?i64 = if (val_json.object.get("value")) |v| blk: {
                if (v == .integer) break :blk v.integer;
                break :blk null;
            } else null;

            const ev = types.EnumValue{
                .name = self.getString(val_json, "name") orelse "",
                .value = value,
            };
            values.append(self.allocator, ev) catch return ParseError.OutOfMemory;
        }

        return values.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseTypedefs(self: *Self, typedefs_json: ?std.json.Value) ParseError![]const types.Typedef {
        const arr = typedefs_json orelse return &[_]types.Typedef{};
        if (arr != .array) return &[_]types.Typedef{};

        var typedefs: std.ArrayList(types.Typedef) = .empty;
        errdefer typedefs.deinit(self.allocator);

        for (arr.array.items) |td_json| {
            if (td_json != .object) continue;

            const td = types.Typedef{
                .name = self.getString(td_json, "name") orelse "",
                .underlying = self.getString(td_json, "underlying") orelse "",
                .location = self.parseLocation(td_json.object.get("location")),
                .doc = if (td_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            typedefs.append(self.allocator, td) catch return ParseError.OutOfMemory;
        }

        return typedefs.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseMacros(self: *Self, macros_json: ?std.json.Value) ParseError![]const types.Macro {
        const arr = macros_json orelse return &[_]types.Macro{};
        if (arr != .array) return &[_]types.Macro{};

        var macros: std.ArrayList(types.Macro) = .empty;
        errdefer macros.deinit(self.allocator);

        for (arr.array.items) |macro_json| {
            if (macro_json != .object) continue;

            // Parse params
            const params: ?[]const []const u8 = if (macro_json.object.get("params")) |p| blk: {
                if (p != .array) break :blk null;
                var param_list: std.ArrayList([]const u8) = .empty;
                for (p.array.items) |param| {
                    if (param == .string) {
                        param_list.append(self.allocator, param.string) catch break :blk null;
                    }
                }
                break :blk param_list.toOwnedSlice(self.allocator) catch null;
            } else null;

            const m = types.Macro{
                .name = self.getString(macro_json, "name") orelse "",
                .body = self.getString(macro_json, "body") orelse "",
                .params = params,
                .location = self.parseLocation(macro_json.object.get("location")),
                .doc = if (macro_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            macros.append(self.allocator, m) catch return ParseError.OutOfMemory;
        }

        return macros.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseTypeAliases(self: *Self, aliases_json: ?std.json.Value) ParseError![]const types.TypeAlias {
        const arr = aliases_json orelse return &[_]types.TypeAlias{};
        if (arr != .array) return &[_]types.TypeAlias{};

        var aliases: std.ArrayList(types.TypeAlias) = .empty;
        errdefer aliases.deinit(self.allocator);

        for (arr.array.items) |alias_json| {
            if (alias_json != .object) continue;

            const ta = types.TypeAlias{
                .name = self.getString(alias_json, "name") orelse "",
                .underlying_type = self.getString(alias_json, "underlyingType") orelse "",
                .namespace = self.getString(alias_json, "namespace"),
                .docstring = if (alias_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            aliases.append(self.allocator, ta) catch return ParseError.OutOfMemory;
        }

        return aliases.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseConcepts(self: *Self, concepts_json: ?std.json.Value) ParseError![]const types.Concept {
        const arr = concepts_json orelse return &[_]types.Concept{};
        if (arr != .array) return &[_]types.Concept{};

        var concepts: std.ArrayList(types.Concept) = .empty;
        errdefer concepts.deinit(self.allocator);

        for (arr.array.items) |concept_json| {
            if (concept_json != .object) continue;

            const c = types.Concept{
                .name = self.getString(concept_json, "name") orelse "",
                .constraint = self.getString(concept_json, "constraint") orelse "",
                .namespace = self.getString(concept_json, "namespace"),
                .template_params = try self.parseTemplateParams(concept_json.object.get("templateParams")),
                .docstring = if (concept_json.object.get("doc")) |d| try self.parseDocString(d) else null,
            };
            concepts.append(self.allocator, c) catch return ParseError.OutOfMemory;
        }

        return concepts.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parsePages(self: *Self, pages_json: ?std.json.Value) ParseError![]const types.Page {
        const arr = pages_json orelse return &[_]types.Page{};
        if (arr != .array) return &[_]types.Page{};

        var pages: std.ArrayList(types.Page) = .empty;
        errdefer pages.deinit(self.allocator);

        for (arr.array.items) |page_json| {
            if (page_json != .object) continue;

            const p = types.Page{
                .id = self.getString(page_json, "id") orelse "",
                .title = self.getString(page_json, "title") orelse "",
                .content = self.getString(page_json, "content") orelse "",
                .is_mainpage = self.getBool(page_json, "isMainpage"),
            };
            pages.append(self.allocator, p) catch return ParseError.OutOfMemory;
        }

        return pages.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseParameters(self: *Self, params_json: ?std.json.Value) ParseError![]const types.Parameter {
        const arr = params_json orelse return &[_]types.Parameter{};
        if (arr != .array) return &[_]types.Parameter{};

        var params: std.ArrayList(types.Parameter) = .empty;
        errdefer params.deinit(self.allocator);

        for (arr.array.items) |param_json| {
            if (param_json != .object) continue;
            const param = types.Parameter{
                .name = self.getString(param_json, "name") orelse "",
                .type_str = self.getString(param_json, "type") orelse "",
            };
            params.append(self.allocator, param) catch return ParseError.OutOfMemory;
        }

        return params.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseTemplateParams(self: *Self, tparams_json: ?std.json.Value) ParseError![]const types.TemplateParam {
        const arr = tparams_json orelse return &[_]types.TemplateParam{};
        if (arr != .array) return &[_]types.TemplateParam{};

        var tparams: std.ArrayList(types.TemplateParam) = .empty;
        errdefer tparams.deinit(self.allocator);

        for (arr.array.items) |tp_json| {
            if (tp_json != .object) continue;
            const tp = types.TemplateParam{
                .name = self.getString(tp_json, "name") orelse "",
                .kind = self.getString(tp_json, "kind") orelse "typename",
                .is_variadic = self.getBool(tp_json, "isVariadic"),
                .default_value = self.getString(tp_json, "default"),
            };
            tparams.append(self.allocator, tp) catch return ParseError.OutOfMemory;
        }

        return tparams.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseDocString(self: *Self, doc_json: std.json.Value) ParseError!types.DocString {
        if (doc_json != .object) return types.DocString{ .raw = "" };

        // Parse params
        const params = try self.parseParamDocs(doc_json.object.get("params"));
        const tparams = try self.parseParamDocs(doc_json.object.get("tparams"));
        const examples = try self.parseStringArray(doc_json.object.get("examples"));
        const notes = try self.parseStringArray(doc_json.object.get("notes"));
        const warnings = try self.parseStringArray(doc_json.object.get("warnings"));
        const see_also = try self.parseStringArray(doc_json.object.get("seeAlso"));

        return types.DocString{
            .raw = "",
            .brief = self.getString(doc_json, "brief"),
            .details = self.getString(doc_json, "details"),
            .params = params,
            .returns = self.getString(doc_json, "returns"),
            .deprecated = self.getString(doc_json, "deprecated"),
            .since = self.getString(doc_json, "since"),
            .tparams = tparams,
            .examples = examples,
            .notes = notes,
            .warnings = warnings,
            .see_also = see_also,
        };
    }

    fn parseParamDocs(self: *Self, params_json: ?std.json.Value) ParseError![]const types.ParamDoc {
        const arr = params_json orelse return &[_]types.ParamDoc{};
        if (arr != .array) return &[_]types.ParamDoc{};

        var params: std.ArrayList(types.ParamDoc) = .empty;
        errdefer params.deinit(self.allocator);

        for (arr.array.items) |param_json| {
            if (param_json != .object) continue;
            const param = types.ParamDoc{
                .name = self.getString(param_json, "name") orelse "",
                .description = self.getString(param_json, "description") orelse "",
            };
            params.append(self.allocator, param) catch return ParseError.OutOfMemory;
        }

        return params.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseStringArray(self: *Self, arr_json: ?std.json.Value) ParseError![]const []const u8 {
        const arr = arr_json orelse return &[_][]const u8{};
        if (arr != .array) return &[_][]const u8{};

        var strings: std.ArrayList([]const u8) = .empty;
        errdefer strings.deinit(self.allocator);

        for (arr.array.items) |item| {
            if (item == .string) {
                strings.append(self.allocator, item.string) catch return ParseError.OutOfMemory;
            }
        }

        return strings.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseLintResults(self: *Self, results_json: std.json.Value) ParseError![]LintResult {
        if (results_json != .array) return &[_]LintResult{};

        var results: std.ArrayList(LintResult) = .empty;
        errdefer results.deinit(self.allocator);

        for (results_json.array.items) |result_json| {
            if (result_json != .object) continue;

            // Parse level
            const level_str = self.getString(result_json, "level") orelse "warning";
            const level: LintResult.Level = if (std.mem.eql(u8, level_str, "error"))
                .@"error"
            else if (std.mem.eql(u8, level_str, "note"))
                .note
            else
                .warning;

            // Parse message
            const message: []const u8 = if (result_json.object.get("message")) |msg| blk: {
                if (msg != .object) break :blk "";
                break :blk self.getString(msg, "text") orelse "";
            } else "";

            // Parse location
            var file: []const u8 = "";
            var line: u32 = 0;
            var column: u32 = 1;

            if (result_json.object.get("locations")) |locs| {
                if (locs == .array and locs.array.items.len > 0) {
                    const loc = locs.array.items[0];
                    if (loc == .object) {
                        if (loc.object.get("physicalLocation")) |phys| {
                            if (phys == .object) {
                                if (phys.object.get("artifactLocation")) |art| {
                                    if (art == .object) {
                                        file = self.getString(art, "uri") orelse "";
                                    }
                                }
                                if (phys.object.get("region")) |reg| {
                                    if (reg == .object) {
                                        line = self.getU32(reg, "startLine");
                                        column = self.getU32(reg, "startColumn");
                                        if (column == 0) column = 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            const result = LintResult{
                .rule_id = self.getString(result_json, "ruleId") orelse "",
                .message = message,
                .level = level,
                .file = file,
                .line = line,
                .column = column,
            };
            results.append(self.allocator, result) catch return ParseError.OutOfMemory;
        }

        return results.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    fn parseLocation(self: *Self, loc_json: ?std.json.Value) types.SourceLocation {
        const loc = loc_json orelse return .{ .file = "", .line = 0, .column = 0 };
        if (loc != .object) return .{ .file = "", .line = 0, .column = 0 };

        return .{
            .file = self.getString(loc, "file") orelse "",
            .line = self.getU32(loc, "line"),
            .column = 0,
        };
    }

    fn parseAccess(self: *Self, access_str: ?[]const u8) types.AccessSpecifier {
        _ = self;
        const str = access_str orelse return .private;
        if (std.mem.eql(u8, str, "public")) return .public;
        if (std.mem.eql(u8, str, "protected")) return .protected;
        return .private;
    }

    fn parseMethodKind(self: *Self, kind_str: ?[]const u8) types.MethodKind {
        _ = self;
        const str = kind_str orelse return .regular;
        if (std.mem.eql(u8, str, "constructor")) return .constructor;
        if (std.mem.eql(u8, str, "copy_constructor")) return .copy_constructor;
        if (std.mem.eql(u8, str, "move_constructor")) return .move_constructor;
        if (std.mem.eql(u8, str, "destructor")) return .destructor;
        if (std.mem.eql(u8, str, "operator")) return .operator_overload;
        if (std.mem.eql(u8, str, "conversion")) return .conversion_operator;
        return .regular;
    }

    fn getString(self: *Self, obj: std.json.Value, key: []const u8) ?[]const u8 {
        _ = self;
        if (obj != .object) return null;
        const val = obj.object.get(key) orelse return null;
        if (val == .string) return val.string;
        return null;
    }

    fn getBool(self: *Self, obj: std.json.Value, key: []const u8) bool {
        _ = self;
        if (obj != .object) return false;
        const val = obj.object.get(key) orelse return false;
        if (val == .bool) return val.bool;
        return false;
    }

    fn getU32(self: *Self, obj: std.json.Value, key: []const u8) u32 {
        _ = self;
        if (obj != .object) return 0;
        const val = obj.object.get(key) orelse return 0;
        if (val == .integer) {
            if (val.integer < 0) return 0;
            if (val.integer > std.math.maxInt(u32)) return std.math.maxInt(u32);
            return @intCast(val.integer);
        }
        return 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "sarif reader basic" {
    const allocator = std.testing.allocator;
    var reader = SarifReader.init(allocator);

    const sarif_json =
        \\{
        \\  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
        \\  "version": "2.1.0",
        \\  "runs": [{
        \\    "tool": {
        \\      "driver": {
        \\        "name": "stig",
        \\        "version": "0.1.0"
        \\      }
        \\    },
        \\    "results": [],
        \\    "properties": {
        \\      "stig:version": "1.0",
        \\      "stig:config": {
        \\        "title": "Test API",
        \\        "grouping": "by_header"
        \\      },
        \\      "stig:modules": [
        \\        {
        \\          "name": "test.h",
        \\          "functions": [],
        \\          "classes": [],
        \\          "structs": [],
        \\          "enums": [],
        \\          "typedefs": [],
        \\          "macros": [],
        \\          "typeAliases": [],
        \\          "concepts": [],
        \\          "pages": []
        \\        }
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    var doc = try reader.parse(sarif_json);
    defer doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), doc.modules.len);
    try std.testing.expectEqualStrings("test.h", doc.modules[0].name);
    try std.testing.expectEqualStrings("Test API", doc.config.title);
}

test "sarif reader with function" {
    const allocator = std.testing.allocator;
    var reader = SarifReader.init(allocator);

    const sarif_json =
        \\{
        \\  "version": "2.1.0",
        \\  "runs": [{
        \\    "tool": {"driver": {"name": "stig"}},
        \\    "results": [],
        \\    "properties": {
        \\      "stig:version": "1.0",
        \\      "stig:modules": [{
        \\        "name": "math.h",
        \\        "functions": [{
        \\          "name": "add",
        \\          "returnType": "int",
        \\          "params": [
        \\            {"name": "a", "type": "int"},
        \\            {"name": "b", "type": "int"}
        \\          ],
        \\          "location": {"file": "math.h", "line": 10},
        \\          "doc": {
        \\            "brief": "Adds two numbers",
        \\            "returns": "The sum"
        \\          }
        \\        }],
        \\        "classes": [],
        \\        "structs": [],
        \\        "enums": [],
        \\        "typedefs": [],
        \\        "macros": [],
        \\        "typeAliases": [],
        \\        "concepts": [],
        \\        "pages": []
        \\      }]
        \\    }
        \\  }]
        \\}
    ;

    var doc = try reader.parse(sarif_json);
    defer doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), doc.modules[0].functions.len);
    try std.testing.expectEqualStrings("add", doc.modules[0].functions[0].name);
    try std.testing.expectEqualStrings("int", doc.modules[0].functions[0].return_type);
    try std.testing.expectEqual(@as(usize, 2), doc.modules[0].functions[0].params.len);

    if (doc.modules[0].functions[0].doc) |doc_str| {
        try std.testing.expectEqualStrings("Adds two numbers", doc_str.brief.?);
    }
}
