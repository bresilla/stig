//! JSON Reader - Parses JSON back into DocumentModel
//!
//! This module handles deserialization of JSON documentation files back into
//! the DocumentModel structure, enabling the `stig render` command and
//! JSON-based documentation pipelines.

const std = @import("std");
const schema = @import("schema.zig");

pub const ParseError = error{
    InvalidJson,
    InvalidSchemaVersion,
    MissingRequiredField,
    InvalidFieldType,
    OutOfMemory,
    UnexpectedToken,
    Overflow,
    InvalidCharacter,
    InvalidNumber,
    InvalidEnumTag,
    InvalidLiteral,
    LengthMismatch,
    DuplicateField,
    UnknownField,
};

/// Result of parsing a JSON document
pub const ParseResult = struct {
    model: schema.DocumentModel,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *ParseResult) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

/// Parse a JSON string into a DocumentModel
pub fn parse(json_str: []const u8, allocator: std.mem.Allocator) ParseError!ParseResult {
    // Create arena for all allocations
    const arena = allocator.create(std.heap.ArenaAllocator) catch return error.OutOfMemory;
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    const arena_alloc = arena.allocator();

    // Parse JSON
    const parsed = std.json.parseFromSlice(std.json.Value, arena_alloc, json_str, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidJson,
        };
    };

    const root = parsed.value;
    if (root != .object) {
        return error.InvalidJson;
    }

    // Parse DocumentModel
    const model = try parseDocumentModel(root.object, arena_alloc);

    return ParseResult{
        .model = model,
        .arena = arena,
    };
}

/// Parse a JSON file into a DocumentModel
pub fn parseFile(path: []const u8, allocator: std.mem.Allocator) !ParseResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error: Cannot open file '{s}': {}\n", .{ path, err });
        return error.InvalidJson;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch |err| {
        std.debug.print("Error: Cannot read file '{s}': {}\n", .{ path, err });
        return error.OutOfMemory;
    };
    defer allocator.free(content);

    return parse(content, allocator);
}

// ============================================================================
// Parsing Functions
// ============================================================================

fn parseDocumentModel(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.DocumentModel {
    const schema_version = try getString(obj, "schema_version") orelse "2.0";

    return schema.DocumentModel{
        .schema_version = schema_version,
        .generator = try parseGeneratorInfo(obj),
        .generated_at = try getString(obj, "generated_at") orelse "",
        .project = try parseProjectInfo(obj),
        .config = try parseConfigInfo(obj),
        .statistics = try parseStatistics(obj),
        .index = try parseIndexEntries(obj, allocator),
        .modules = try parseModules(obj, allocator),
        .pages = try parsePages(obj, allocator),
        .appendix = try parseAppendix(obj, allocator),
    };
}

fn parseGeneratorInfo(obj: std.json.ObjectMap) ParseError!schema.GeneratorInfo {
    const gen_obj = obj.get("generator") orelse return schema.GeneratorInfo{
        .name = "unknown",
        .version = "0.0.0",
    };

    if (gen_obj != .object) return error.InvalidFieldType;

    return schema.GeneratorInfo{
        .name = try getString(gen_obj.object, "name") orelse "unknown",
        .version = try getString(gen_obj.object, "version") orelse "0.0.0",
    };
}

fn parseProjectInfo(obj: std.json.ObjectMap) ParseError!schema.ProjectInfo {
    const proj_obj = obj.get("project") orelse return schema.ProjectInfo{
        .title = "Untitled",
    };

    if (proj_obj != .object) return error.InvalidFieldType;

    return schema.ProjectInfo{
        .title = try getString(proj_obj.object, "title") orelse "Untitled",
        .description = try getString(proj_obj.object, "description"),
        .version = try getString(proj_obj.object, "version"),
    };
}

fn parseConfigInfo(obj: std.json.ObjectMap) ParseError!schema.ConfigInfo {
    const config_obj = obj.get("config") orelse return schema.ConfigInfo{};

    if (config_obj != .object) return error.InvalidFieldType;

    return schema.ConfigInfo{
        .language = try getString(config_obj.object, "language") orelse "en",
        .source_url_template = try getString(config_obj.object, "source_url_template"),
    };
}

fn parseStatistics(obj: std.json.ObjectMap) ParseError!schema.Statistics {
    const stats_obj = obj.get("statistics") orelse return schema.Statistics{
        .modules = 0,
        .functions = 0,
        .classes = 0,
        .structs = 0,
        .enums = 0,
        .macros = 0,
        .typedefs = 0,
        .type_aliases = 0,
        .concepts = 0,
        .documented = 0,
        .undocumented = 0,
        .coverage_percent = 0.0,
    };

    if (stats_obj != .object) return error.InvalidFieldType;

    return schema.Statistics{
        .modules = try getU32(stats_obj.object, "modules") orelse 0,
        .functions = try getU32(stats_obj.object, "functions") orelse 0,
        .classes = try getU32(stats_obj.object, "classes") orelse 0,
        .structs = try getU32(stats_obj.object, "structs") orelse 0,
        .enums = try getU32(stats_obj.object, "enums") orelse 0,
        .macros = try getU32(stats_obj.object, "macros") orelse 0,
        .typedefs = try getU32(stats_obj.object, "typedefs") orelse 0,
        .type_aliases = try getU32(stats_obj.object, "type_aliases") orelse 0,
        .concepts = try getU32(stats_obj.object, "concepts") orelse 0,
        .documented = try getU32(stats_obj.object, "documented") orelse 0,
        .undocumented = try getU32(stats_obj.object, "undocumented") orelse 0,
        .coverage_percent = try getF64(stats_obj.object, "coverage_percent") orelse 0.0,
    };
}

fn parseIndexEntries(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.IndexEntry {
    const index_arr = obj.get("index") orelse return &[_]schema.IndexEntry{};
    if (index_arr != .array) return error.InvalidFieldType;

    var entries: std.ArrayList(schema.IndexEntry) = .empty;
    defer entries.deinit(allocator);

    for (index_arr.array.items) |item| {
        if (item != .object) continue;
        const entry = try parseIndexEntry(item.object);
        entries.append(allocator, entry) catch return error.OutOfMemory;
    }

    return entries.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseIndexEntry(obj: std.json.ObjectMap) ParseError!schema.IndexEntry {
    return schema.IndexEntry{
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .kind = try parseSymbolKind(obj),
        .brief = try getString(obj, "brief"),
        .module = try getString(obj, "module") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .path = try getString(obj, "path") orelse "",
    };
}

fn parseSymbolKind(obj: std.json.ObjectMap) ParseError!schema.SymbolKind {
    const kind_str = try getString(obj, "kind") orelse return .function;
    return stringToSymbolKind(kind_str);
}

fn stringToSymbolKind(s: []const u8) schema.SymbolKind {
    if (std.mem.eql(u8, s, "function")) return .function;
    if (std.mem.eql(u8, s, "class")) return .class_;
    if (std.mem.eql(u8, s, "struct")) return .struct_;
    if (std.mem.eql(u8, s, "union")) return .union_;
    if (std.mem.eql(u8, s, "enum")) return .enum_;
    if (std.mem.eql(u8, s, "typedef")) return .typedef;
    if (std.mem.eql(u8, s, "type_alias")) return .type_alias;
    if (std.mem.eql(u8, s, "macro")) return .macro;
    if (std.mem.eql(u8, s, "concept")) return .concept;
    if (std.mem.eql(u8, s, "namespace")) return .namespace;
    if (std.mem.eql(u8, s, "method")) return .method;
    if (std.mem.eql(u8, s, "field")) return .field;
    return .function;
}

fn parseModules(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ModuleDoc {
    const modules_arr = obj.get("modules") orelse return &[_]schema.ModuleDoc{};
    if (modules_arr != .array) return error.InvalidFieldType;

    var modules: std.ArrayList(schema.ModuleDoc) = .empty;
    defer modules.deinit(allocator);

    for (modules_arr.array.items) |item| {
        if (item != .object) continue;
        const module = try parseModuleDoc(item.object, allocator);
        modules.append(allocator, module) catch return error.OutOfMemory;
    }

    return modules.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseModuleDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.ModuleDoc {
    return schema.ModuleDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .path = try getString(obj, "path") orelse "",
        .title = try getString(obj, "title"),
        .file_doc = try parseOptionalDocString(obj, "file_doc", allocator),
        .includes = try parseIncludes(obj, allocator),
        .functions = try parseFunctions(obj, allocator),
        .classes = try parseClasses(obj, allocator),
        .structs = try parseStructs(obj, allocator),
        .unions = try parseUnions(obj, allocator),
        .enums = try parseEnums(obj, allocator),
        .typedefs = try parseTypedefs(obj, allocator),
        .type_aliases = try parseTypeAliases(obj, allocator),
        .macros = try parseMacros(obj, allocator),
        .concepts = try parseConcepts(obj, allocator),
        .namespaces = try parseNamespaces(obj, allocator),
    };
}

fn parseIncludes(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.IncludeDoc {
    const arr = obj.get("includes") orelse return &[_]schema.IncludeDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var includes: std.ArrayList(schema.IncludeDoc) = .empty;
    defer includes.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const inc = schema.IncludeDoc{
            .path = try getString(item.object, "path") orelse "",
            .is_system = try getBool(item.object, "is_system") orelse false,
            .resolved = try getString(item.object, "resolved"),
        };
        includes.append(allocator, inc) catch return error.OutOfMemory;
    }

    return includes.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseFunctions(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.FunctionDoc {
    const arr = obj.get("functions") orelse return &[_]schema.FunctionDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var functions: std.ArrayList(schema.FunctionDoc) = .empty;
    defer functions.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const func = try parseFunctionDoc(item.object, allocator);
        functions.append(allocator, func) catch return error.OutOfMemory;
    }

    return functions.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseFunctionDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.FunctionDoc {
    return schema.FunctionDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .signature = try getString(obj, "signature") orelse "",
        .return_type = try getString(obj, "return_type") orelse "",
        .parameters = try parseParameters(obj, allocator),
        .template_params = try parseTemplateParams(obj, allocator),
        .requires_clause = try getString(obj, "requires_clause"),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
        .qualifiers = try parseFunctionQualifiers(obj),
        .calls = try parseStringArray(obj, "calls", allocator),
    };
}

fn parseParameters(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ParameterDoc {
    const arr = obj.get("parameters") orelse return &[_]schema.ParameterDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var params: std.ArrayList(schema.ParameterDoc) = .empty;
    defer params.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const param = schema.ParameterDoc{
            .name = try getString(item.object, "name") orelse "",
            .type_str = try getString(item.object, "type_str") orelse "",
            .doc = try getString(item.object, "doc"),
        };
        params.append(allocator, param) catch return error.OutOfMemory;
    }

    return params.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseTemplateParams(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.TemplateParamDoc {
    const arr = obj.get("template_params") orelse return &[_]schema.TemplateParamDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var params: std.ArrayList(schema.TemplateParamDoc) = .empty;
    defer params.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const param = schema.TemplateParamDoc{
            .name = try getString(item.object, "name") orelse "",
            .kind = try getString(item.object, "kind") orelse "typename",
            .is_variadic = try getBool(item.object, "is_variadic") orelse false,
            .default_value = try getString(item.object, "default_value"),
            .doc = try getString(item.object, "doc"),
        };
        params.append(allocator, param) catch return error.OutOfMemory;
    }

    return params.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseLocation(obj: std.json.ObjectMap) ParseError!schema.LocationDoc {
    const loc_obj = obj.get("location") orelse return schema.LocationDoc{
        .file = "",
        .line = 0,
        .column = 0,
    };

    if (loc_obj != .object) return error.InvalidFieldType;

    return schema.LocationDoc{
        .file = try getString(loc_obj.object, "file") orelse "",
        .line = try getU32(loc_obj.object, "line") orelse 0,
        .column = try getU32(loc_obj.object, "column") orelse 0,
    };
}

fn parseFunctionQualifiers(obj: std.json.ObjectMap) ParseError!schema.FunctionQualifiers {
    const qual_obj = obj.get("qualifiers") orelse return schema.FunctionQualifiers{};
    if (qual_obj != .object) return error.InvalidFieldType;

    return schema.FunctionQualifiers{
        .is_static = try getBool(qual_obj.object, "is_static") orelse false,
        .is_inline = try getBool(qual_obj.object, "is_inline") orelse false,
        .is_constexpr = try getBool(qual_obj.object, "is_constexpr") orelse false,
        .is_consteval = try getBool(qual_obj.object, "is_consteval") orelse false,
        .is_noexcept = try getBool(qual_obj.object, "is_noexcept") orelse false,
    };
}

fn parseClasses(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ClassDoc {
    const arr = obj.get("classes") orelse return &[_]schema.ClassDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var classes: std.ArrayList(schema.ClassDoc) = .empty;
    defer classes.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const class = try parseClassDoc(item.object, allocator);
        classes.append(allocator, class) catch return error.OutOfMemory;
    }

    return classes.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseClassDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.ClassDoc {
    return schema.ClassDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .template_params = try parseTemplateParams(obj, allocator),
        .requires_clause = try getString(obj, "requires_clause"),
        .base_classes = try parseBaseClasses(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
        .members = try parseClassMembers(obj, allocator),
        .nested_classes = try parseNestedClasses(obj, allocator),
        .nested_enums = try parseNestedEnums(obj, allocator),
        .friends = try parseFriends(obj, allocator),
    };
}

fn parseBaseClasses(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.BaseClassDoc {
    const arr = obj.get("base_classes") orelse return &[_]schema.BaseClassDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var bases: std.ArrayList(schema.BaseClassDoc) = .empty;
    defer bases.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const base = schema.BaseClassDoc{
            .name = try getString(item.object, "name") orelse "",
            .access = try parseAccessSpecifier(item.object),
            .is_virtual = try getBool(item.object, "is_virtual") orelse false,
            .resolved_link = try getString(item.object, "resolved_link"),
        };
        bases.append(allocator, base) catch return error.OutOfMemory;
    }

    return bases.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseAccessSpecifier(obj: std.json.ObjectMap) ParseError!schema.AccessSpecifier {
    const access_str = try getString(obj, "access") orelse return .public;
    if (std.mem.eql(u8, access_str, "public")) return .public;
    if (std.mem.eql(u8, access_str, "protected")) return .protected;
    if (std.mem.eql(u8, access_str, "private")) return .private;
    return .public;
}

fn parseClassMembers(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.ClassMembers {
    const members_obj = obj.get("members") orelse return schema.ClassMembers{
        .public = schema.MemberGroup{},
        .protected = schema.MemberGroup{},
        .private = schema.MemberGroup{},
    };

    if (members_obj != .object) return error.InvalidFieldType;

    return schema.ClassMembers{
        .public = try parseMemberGroup(members_obj.object, "public", allocator),
        .protected = try parseMemberGroup(members_obj.object, "protected", allocator),
        .private = try parseMemberGroup(members_obj.object, "private", allocator),
    };
}

fn parseMemberGroup(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError!schema.MemberGroup {
    const group_obj = obj.get(key) orelse return schema.MemberGroup{};
    if (group_obj != .object) return error.InvalidFieldType;

    return schema.MemberGroup{
        .methods = try parseMethods(group_obj.object, allocator),
        .fields = try parseFields(group_obj.object, allocator),
    };
}

fn parseMethods(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.MethodDoc {
    const arr = obj.get("methods") orelse return &[_]schema.MethodDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var methods: std.ArrayList(schema.MethodDoc) = .empty;
    defer methods.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const method = try parseMethodDoc(item.object, allocator);
        methods.append(allocator, method) catch return error.OutOfMemory;
    }

    return methods.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseMethodDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.MethodDoc {
    return schema.MethodDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .signature = try getString(obj, "signature") orelse "",
        .return_type = try getString(obj, "return_type") orelse "",
        .parameters = try parseParameters(obj, allocator),
        .kind = try parseMethodKind(obj),
        .operator_symbol = try getString(obj, "operator_symbol"),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .qualifiers = try parseMethodQualifiers(obj),
        .calls = try parseStringArray(obj, "calls", allocator),
        .location = try parseLocation(obj),
    };
}

fn parseMethodKind(obj: std.json.ObjectMap) ParseError!schema.MethodKind {
    const kind_str = try getString(obj, "kind") orelse return .regular;
    if (std.mem.eql(u8, kind_str, "regular")) return .regular;
    if (std.mem.eql(u8, kind_str, "constructor")) return .constructor;
    if (std.mem.eql(u8, kind_str, "copy_constructor")) return .copy_constructor;
    if (std.mem.eql(u8, kind_str, "move_constructor")) return .move_constructor;
    if (std.mem.eql(u8, kind_str, "destructor")) return .destructor;
    if (std.mem.eql(u8, kind_str, "operator_overload")) return .operator_overload;
    if (std.mem.eql(u8, kind_str, "conversion_operator")) return .conversion_operator;
    return .regular;
}

fn parseMethodQualifiers(obj: std.json.ObjectMap) ParseError!schema.MethodQualifiers {
    const qual_obj = obj.get("qualifiers") orelse return schema.MethodQualifiers{};
    if (qual_obj != .object) return error.InvalidFieldType;

    return schema.MethodQualifiers{
        .is_virtual = try getBool(qual_obj.object, "is_virtual") orelse false,
        .is_static = try getBool(qual_obj.object, "is_static") orelse false,
        .is_const = try getBool(qual_obj.object, "is_const") orelse false,
        .is_override = try getBool(qual_obj.object, "is_override") orelse false,
        .is_final = try getBool(qual_obj.object, "is_final") orelse false,
        .is_pure_virtual = try getBool(qual_obj.object, "is_pure_virtual") orelse false,
        .is_defaulted = try getBool(qual_obj.object, "is_defaulted") orelse false,
        .is_deleted = try getBool(qual_obj.object, "is_deleted") orelse false,
        .is_constexpr = try getBool(qual_obj.object, "is_constexpr") orelse false,
        .is_consteval = try getBool(qual_obj.object, "is_consteval") orelse false,
        .is_explicit = try getBool(qual_obj.object, "is_explicit") orelse false,
        .is_noexcept = try getBool(qual_obj.object, "is_noexcept") orelse false,
    };
}

fn parseFields(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.FieldDoc {
    const arr = obj.get("fields") orelse return &[_]schema.FieldDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var fields: std.ArrayList(schema.FieldDoc) = .empty;
    defer fields.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const field = schema.FieldDoc{
            .name = try getString(item.object, "name") orelse "",
            .type_str = try getString(item.object, "type_str") orelse "",
            .doc = try getString(item.object, "doc"),
        };
        fields.append(allocator, field) catch return error.OutOfMemory;
    }

    return fields.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseNestedClasses(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ClassDoc {
    const arr = obj.get("nested_classes") orelse return &[_]schema.ClassDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var classes: std.ArrayList(schema.ClassDoc) = .empty;
    defer classes.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const class = try parseClassDoc(item.object, allocator);
        classes.append(allocator, class) catch return error.OutOfMemory;
    }

    return classes.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseNestedEnums(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.EnumDoc {
    const arr = obj.get("nested_enums") orelse return &[_]schema.EnumDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var enums: std.ArrayList(schema.EnumDoc) = .empty;
    defer enums.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const e = try parseEnumDoc(item.object, allocator);
        enums.append(allocator, e) catch return error.OutOfMemory;
    }

    return enums.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseFriends(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.FriendDoc {
    const arr = obj.get("friends") orelse return &[_]schema.FriendDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var friends: std.ArrayList(schema.FriendDoc) = .empty;
    defer friends.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const friend = schema.FriendDoc{
            .kind = try parseFriendKind(item.object),
            .name = try getString(item.object, "name") orelse "",
            .signature = try getString(item.object, "signature"),
        };
        friends.append(allocator, friend) catch return error.OutOfMemory;
    }

    return friends.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseFriendKind(obj: std.json.ObjectMap) ParseError!schema.FriendKind {
    const kind_str = try getString(obj, "kind") orelse return .function;
    if (std.mem.eql(u8, kind_str, "class")) return .class_;
    if (std.mem.eql(u8, kind_str, "function")) return .function;
    return .function;
}

fn parseStructs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.StructDoc {
    const arr = obj.get("structs") orelse return &[_]schema.StructDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var structs: std.ArrayList(schema.StructDoc) = .empty;
    defer structs.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const s = try parseStructDoc(item.object, allocator);
        structs.append(allocator, s) catch return error.OutOfMemory;
    }

    return structs.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseStructDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.StructDoc {
    return schema.StructDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .fields = try parseFields(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseUnions(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.UnionDoc {
    const arr = obj.get("unions") orelse return &[_]schema.UnionDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var unions: std.ArrayList(schema.UnionDoc) = .empty;
    defer unions.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const u = try parseUnionDoc(item.object, allocator);
        unions.append(allocator, u) catch return error.OutOfMemory;
    }

    return unions.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseUnionDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.UnionDoc {
    return schema.UnionDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .fields = try parseFields(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseEnums(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.EnumDoc {
    const arr = obj.get("enums") orelse return &[_]schema.EnumDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var enums: std.ArrayList(schema.EnumDoc) = .empty;
    defer enums.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const e = try parseEnumDoc(item.object, allocator);
        enums.append(allocator, e) catch return error.OutOfMemory;
    }

    return enums.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseEnumDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.EnumDoc {
    return schema.EnumDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .values = try parseEnumValues(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseEnumValues(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.EnumValueDoc {
    const arr = obj.get("values") orelse return &[_]schema.EnumValueDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var values: std.ArrayList(schema.EnumValueDoc) = .empty;
    defer values.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const val = schema.EnumValueDoc{
            .name = try getString(item.object, "name") orelse "",
            .value = try getI64(item.object, "value"),
            .doc = try getString(item.object, "doc"),
        };
        values.append(allocator, val) catch return error.OutOfMemory;
    }

    return values.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseTypedefs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.TypedefDoc {
    const arr = obj.get("typedefs") orelse return &[_]schema.TypedefDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var typedefs: std.ArrayList(schema.TypedefDoc) = .empty;
    defer typedefs.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const td = try parseTypedefDoc(item.object, allocator);
        typedefs.append(allocator, td) catch return error.OutOfMemory;
    }

    return typedefs.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseTypedefDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.TypedefDoc {
    return schema.TypedefDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .underlying = try getString(obj, "underlying") orelse "",
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseTypeAliases(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.TypeAliasDoc {
    const arr = obj.get("type_aliases") orelse return &[_]schema.TypeAliasDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var aliases: std.ArrayList(schema.TypeAliasDoc) = .empty;
    defer aliases.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const alias = try parseTypeAliasDoc(item.object, allocator);
        aliases.append(allocator, alias) catch return error.OutOfMemory;
    }

    return aliases.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseTypeAliasDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.TypeAliasDoc {
    return schema.TypeAliasDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .underlying_type = try getString(obj, "underlying_type") orelse "",
        .template_params = try parseTemplateParams(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseMacros(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.MacroDoc {
    const arr = obj.get("macros") orelse return &[_]schema.MacroDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var macros: std.ArrayList(schema.MacroDoc) = .empty;
    defer macros.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const m = try parseMacroDoc(item.object, allocator);
        macros.append(allocator, m) catch return error.OutOfMemory;
    }

    return macros.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseMacroDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.MacroDoc {
    return schema.MacroDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .params = try parseOptionalStringArray(obj, "params", allocator),
        .body = try getString(obj, "body") orelse "",
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseConcepts(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ConceptDoc {
    const arr = obj.get("concepts") orelse return &[_]schema.ConceptDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var concepts: std.ArrayList(schema.ConceptDoc) = .empty;
    defer concepts.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const c = try parseConceptDoc(item.object, allocator);
        concepts.append(allocator, c) catch return error.OutOfMemory;
    }

    return concepts.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseConceptDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.ConceptDoc {
    return schema.ConceptDoc{
        .id = try getString(obj, "id") orelse "",
        .name = try getString(obj, "name") orelse "",
        .qualified_name = try getString(obj, "qualified_name") orelse "",
        .anchor = try getString(obj, "anchor") orelse "",
        .constraint = try getString(obj, "constraint") orelse "",
        .template_params = try parseTemplateParams(obj, allocator),
        .doc = try parseOptionalDocString(obj, "doc", allocator),
        .location = try parseLocation(obj),
        .source_url = try getString(obj, "source_url"),
    };
}

fn parseNamespaces(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.NamespaceDoc {
    const arr = obj.get("namespaces") orelse return &[_]schema.NamespaceDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var namespaces: std.ArrayList(schema.NamespaceDoc) = .empty;
    defer namespaces.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const ns = schema.NamespaceDoc{
            .name = try getString(item.object, "name") orelse "",
            .qualified_name = try getString(item.object, "qualified_name") orelse "",
            .doc = try parseOptionalDocString(item.object, "doc", allocator),
        };
        namespaces.append(allocator, ns) catch return error.OutOfMemory;
    }

    return namespaces.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseOptionalDocString(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError!?schema.DocStringDoc {
    const doc_val = obj.get(key) orelse return null;
    if (doc_val == .null) return null;
    if (doc_val != .object) return error.InvalidFieldType;
    return try parseDocStringDoc(doc_val.object, allocator);
}

fn parseDocStringDoc(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.DocStringDoc {
    return schema.DocStringDoc{
        .raw = try getString(obj, "raw") orelse "",
        .brief = try getString(obj, "brief"),
        .details = try getString(obj, "details"),
        .params = try parseParamDocs(obj, "params", allocator),
        .tparams = try parseParamDocs(obj, "tparams", allocator),
        .returns = try getString(obj, "returns"),
        .retvals = try parseRetvalDocs(obj, allocator),
        .exceptions = try parseExceptionDocs(obj, allocator),
        .examples = try parseStringArray(obj, "examples", allocator),
        .code_blocks = try parseCodeBlocks(obj, allocator),
        .notes = try parseStringArray(obj, "notes", allocator),
        .warnings = try parseStringArray(obj, "warnings", allocator),
        .attention = try parseStringArray(obj, "attention", allocator),
        .important = try parseStringArray(obj, "important", allocator),
        .deprecated = try getString(obj, "deprecated"),
        .see_also = try parseResolvedRefs(obj, "see_also", allocator),
        .preconditions = try parseStringArray(obj, "preconditions", allocator),
        .postconditions = try parseStringArray(obj, "postconditions", allocator),
        .since = try getString(obj, "since"),
        .author = try getString(obj, "author"),
        .version = try getString(obj, "version"),
        .date = try getString(obj, "date"),
        .copyright = try getString(obj, "copyright"),
        .effects = try getString(obj, "effects"),
        .requires = try getString(obj, "requires"),
        .complexity = try getString(obj, "complexity"),
        .remarks = try parseStringArray(obj, "remarks", allocator),
        .sync = try getString(obj, "sync"),
        .invariants = try parseStringArray(obj, "invariants", allocator),
        .ingroup = try getString(obj, "ingroup"),
        .module = try getString(obj, "module"),
        .mermaid_diagrams = try parseMermaidDiagrams(obj, allocator),
        .refs = try parseResolvedRefs(obj, "refs", allocator),
    };
}

fn parseParamDocs(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError![]const schema.ParamDoc {
    const arr = obj.get(key) orelse return &[_]schema.ParamDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var params: std.ArrayList(schema.ParamDoc) = .empty;
    defer params.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const param = schema.ParamDoc{
            .name = try getString(item.object, "name") orelse "",
            .description = try getString(item.object, "description") orelse "",
        };
        params.append(allocator, param) catch return error.OutOfMemory;
    }

    return params.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseRetvalDocs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.RetvalDoc {
    const arr = obj.get("retvals") orelse return &[_]schema.RetvalDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var retvals: std.ArrayList(schema.RetvalDoc) = .empty;
    defer retvals.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const rv = schema.RetvalDoc{
            .value = try getString(item.object, "value") orelse "",
            .description = try getString(item.object, "description") orelse "",
        };
        retvals.append(allocator, rv) catch return error.OutOfMemory;
    }

    return retvals.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseExceptionDocs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.ExceptionDoc {
    const arr = obj.get("exceptions") orelse return &[_]schema.ExceptionDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var exceptions: std.ArrayList(schema.ExceptionDoc) = .empty;
    defer exceptions.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const exc = schema.ExceptionDoc{
            .exception_type = try getString(item.object, "exception_type") orelse "",
            .description = try getString(item.object, "description") orelse "",
        };
        exceptions.append(allocator, exc) catch return error.OutOfMemory;
    }

    return exceptions.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseCodeBlocks(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.CodeBlockDoc {
    const arr = obj.get("code_blocks") orelse return &[_]schema.CodeBlockDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var blocks: std.ArrayList(schema.CodeBlockDoc) = .empty;
    defer blocks.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const block = schema.CodeBlockDoc{
            .content = try getString(item.object, "content") orelse "",
            .language = try getString(item.object, "language"),
            .show_line_numbers = try getBool(item.object, "show_line_numbers") orelse false,
        };
        blocks.append(allocator, block) catch return error.OutOfMemory;
    }

    return blocks.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseMermaidDiagrams(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.MermaidDiagramDoc {
    const arr = obj.get("mermaid_diagrams") orelse return &[_]schema.MermaidDiagramDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var diagrams: std.ArrayList(schema.MermaidDiagramDoc) = .empty;
    defer diagrams.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const diagram = schema.MermaidDiagramDoc{
            .content = try getString(item.object, "content") orelse "",
            .caption = try getString(item.object, "caption"),
        };
        diagrams.append(allocator, diagram) catch return error.OutOfMemory;
    }

    return diagrams.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseResolvedRefs(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError![]const schema.ResolvedRefDoc {
    const arr = obj.get(key) orelse return &[_]schema.ResolvedRefDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var refs: std.ArrayList(schema.ResolvedRefDoc) = .empty;
    defer refs.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const ref = schema.ResolvedRefDoc{
            .target = try getString(item.object, "target") orelse "",
            .display_text = try getString(item.object, "display_text"),
            .resolved_url = try getString(item.object, "resolved_url"),
            .is_external = try getBool(item.object, "is_external") orelse false,
        };
        refs.append(allocator, ref) catch return error.OutOfMemory;
    }

    return refs.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parsePages(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.PageDoc {
    const arr = obj.get("pages") orelse return &[_]schema.PageDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var pages: std.ArrayList(schema.PageDoc) = .empty;
    defer pages.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const page = schema.PageDoc{
            .id = try getString(item.object, "id") orelse "",
            .title = try getString(item.object, "title") orelse "",
            .content = try getString(item.object, "content") orelse "",
            .is_mainpage = try getBool(item.object, "is_mainpage") orelse false,
        };
        pages.append(allocator, page) catch return error.OutOfMemory;
    }

    return pages.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseAppendix(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError!schema.Appendix {
    const app_obj = obj.get("appendix") orelse return schema.Appendix{};
    if (app_obj != .object) return error.InvalidFieldType;

    return schema.Appendix{
        .todos = try parseTodoDocs(app_obj.object, allocator),
        .bugs = try parseBugDocs(app_obj.object, allocator),
        .tests = try parseTestDocs(app_obj.object, allocator),
    };
}

fn parseTodoDocs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.TodoDoc {
    const arr = obj.get("todos") orelse return &[_]schema.TodoDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var todos: std.ArrayList(schema.TodoDoc) = .empty;
    defer todos.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const todo = schema.TodoDoc{
            .description = try getString(item.object, "description") orelse "",
            .location = try parseLocation(item.object),
            .entity_name = try getString(item.object, "entity_name") orelse "",
            .entity_kind = try parseSymbolKind(item.object),
        };
        todos.append(allocator, todo) catch return error.OutOfMemory;
    }

    return todos.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseBugDocs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.BugDoc {
    const arr = obj.get("bugs") orelse return &[_]schema.BugDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var bugs: std.ArrayList(schema.BugDoc) = .empty;
    defer bugs.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const bug = schema.BugDoc{
            .description = try getString(item.object, "description") orelse "",
            .location = try parseLocation(item.object),
            .entity_name = try getString(item.object, "entity_name") orelse "",
            .entity_kind = try parseSymbolKind(item.object),
        };
        bugs.append(allocator, bug) catch return error.OutOfMemory;
    }

    return bugs.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseTestDocs(obj: std.json.ObjectMap, allocator: std.mem.Allocator) ParseError![]const schema.TestDoc {
    const arr = obj.get("tests") orelse return &[_]schema.TestDoc{};
    if (arr != .array) return error.InvalidFieldType;

    var tests: std.ArrayList(schema.TestDoc) = .empty;
    defer tests.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .object) continue;
        const t = schema.TestDoc{
            .name = try getString(item.object, "name") orelse "",
            .file = try getString(item.object, "file"),
            .line = try getU32(item.object, "line"),
            .tests_entity = try getString(item.object, "tests_entity") orelse "",
        };
        tests.append(allocator, t) catch return error.OutOfMemory;
    }

    return tests.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn getString(obj: std.json.ObjectMap, key: []const u8) ParseError!?[]const u8 {
    const val = obj.get(key) orelse return null;
    if (val == .null) return null;
    if (val != .string) return error.InvalidFieldType;
    return val.string;
}

fn getBool(obj: std.json.ObjectMap, key: []const u8) ParseError!?bool {
    const val = obj.get(key) orelse return null;
    if (val == .null) return null;
    if (val != .bool) return error.InvalidFieldType;
    return val.bool;
}

fn getU32(obj: std.json.ObjectMap, key: []const u8) ParseError!?u32 {
    const val = obj.get(key) orelse return null;
    if (val == .null) return null;
    if (val != .integer) return error.InvalidFieldType;
    if (val.integer < 0 or val.integer > std.math.maxInt(u32)) return error.Overflow;
    return @intCast(val.integer);
}

fn getI64(obj: std.json.ObjectMap, key: []const u8) ParseError!?i64 {
    const val = obj.get(key) orelse return null;
    if (val == .null) return null;
    if (val != .integer) return error.InvalidFieldType;
    return val.integer;
}

fn getF64(obj: std.json.ObjectMap, key: []const u8) ParseError!?f64 {
    const val = obj.get(key) orelse return null;
    if (val == .null) return null;
    return switch (val) {
        .float => val.float,
        .integer => @floatFromInt(val.integer),
        else => return error.InvalidFieldType,
    };
}

fn parseStringArray(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError![]const []const u8 {
    const arr = obj.get(key) orelse return &[_][]const u8{};
    if (arr != .array) return error.InvalidFieldType;

    var strings: std.ArrayList([]const u8) = .empty;
    defer strings.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .string) continue;
        strings.append(allocator, item.string) catch return error.OutOfMemory;
    }

    return strings.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn parseOptionalStringArray(obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) ParseError!?[]const []const u8 {
    const arr = obj.get(key) orelse return null;
    if (arr == .null) return null;
    if (arr != .array) return error.InvalidFieldType;

    var strings: std.ArrayList([]const u8) = .empty;
    defer strings.deinit(allocator);

    for (arr.array.items) |item| {
        if (item != .string) continue;
        strings.append(allocator, item.string) catch return error.OutOfMemory;
    }

    return strings.toOwnedSlice(allocator) catch return error.OutOfMemory;
}
