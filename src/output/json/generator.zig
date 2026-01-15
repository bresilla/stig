const std = @import("std");
const types = @import("../../model/types.zig");
const schema = @import("schema.zig");
const xref = @import("../../xref.zig");
const config_mod = @import("../../config.zig");
const cli = @import("../../cli.zig");

/// JSON Generator - transforms types.Module into DocumentModel and serializes to JSON
pub const Generator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,
    indent_level: usize = 0,
    compact: bool = false,

    // For cross-reference resolution
    symbol_table: ?*xref.SymbolTable = null,
    config: config_mod.Config = .{},

    // Anchor generation state
    anchor_map: std.StringHashMap([]const u8),
    anchor_counter: std.StringHashMap(u32),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .anchor_map = std.StringHashMap([]const u8).init(allocator),
            .anchor_counter = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn initCompact(allocator: std.mem.Allocator) Self {
        var gen = init(allocator);
        gen.compact = true;
        return gen;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);

        // Note: anchors are allocated with the arena in generate(), so they don't
        // need to be freed here - the arena handles cleanup.
        // Just clear the maps for reuse.
        self.anchor_map.deinit();
        self.anchor_counter.deinit();
    }

    pub fn setSymbolTable(self: *Self, table: *xref.SymbolTable) void {
        self.symbol_table = table;
    }

    pub fn setConfig(self: *Self, cfg: config_mod.Config) void {
        self.config = cfg;
    }

    /// Main entry point: generate JSON from modules
    pub fn generate(self: *Self, modules: []const types.Module) ![]const u8 {
        // Clear buffer
        self.buffer.clearRetainingCapacity();

        // Create arena for document model - must outlive serialization
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        // Build symbol table if not provided
        var owned_symbol_table: ?xref.SymbolTable = null;
        defer if (owned_symbol_table) |*st| st.deinit();

        if (self.symbol_table == null) {
            owned_symbol_table = xref.SymbolTable.initWithConfig(self.allocator, self.config);
            try owned_symbol_table.?.buildFromModules(modules);
            self.symbol_table = &owned_symbol_table.?;
        }

        // Build document model
        const doc_model = try self.buildDocumentModel(modules, arena_alloc);

        // Serialize to JSON
        try self.serializeDocumentModel(doc_model);

        return self.buffer.items;
    }

    // =========================================================================
    // Document Model Building
    // =========================================================================

    fn buildDocumentModel(self: *Self, modules: []const types.Module, arena_alloc: std.mem.Allocator) !schema.DocumentModel {

        // Build statistics
        const stats = self.calculateStatistics(modules);

        // Build modules
        var module_docs: std.ArrayList(schema.ModuleDoc) = .empty;
        for (modules) |module| {
            const module_doc = try self.buildModuleDoc(module, arena_alloc);
            try module_docs.append(arena_alloc, module_doc);
        }

        // Build index
        const index = try self.buildIndex(module_docs.items, arena_alloc);

        // Build appendix
        const appendix = try self.buildAppendix(modules, arena_alloc);

        // Build pages
        var pages: std.ArrayList(schema.PageDoc) = .empty;
        for (modules) |module| {
            for (module.pages) |page| {
                try pages.append(arena_alloc, schema.PageDoc{
                    .id = page.id,
                    .title = page.title,
                    .content = page.content,
                    .is_mainpage = page.is_mainpage,
                });
            }
        }

        // Get timestamp
        const timestamp = try self.getTimestamp(arena_alloc);

        return schema.DocumentModel{
            .generator = schema.GeneratorInfo{
                .name = "stig",
                .version = cli.VERSION,
            },
            .generated_at = timestamp,
            .project = schema.ProjectInfo{
                .title = self.config.title,
                .description = null,
                .version = null,
            },
            .config = schema.ConfigInfo{
                .language = "en",
                .source_url_template = null,
            },
            .statistics = stats,
            .index = try arena_alloc.dupe(schema.IndexEntry, index),
            .modules = try arena_alloc.dupe(schema.ModuleDoc, module_docs.items),
            .pages = try arena_alloc.dupe(schema.PageDoc, pages.items),
            .appendix = appendix,
        };
    }

    fn calculateStatistics(self: *Self, modules: []const types.Module) schema.Statistics {
        _ = self;
        var stats = schema.Statistics{
            .modules = @intCast(modules.len),
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

        for (modules) |module| {
            stats.functions += @intCast(module.functions.len);
            stats.classes += @intCast(module.classes.len);
            stats.structs += @intCast(module.structs.len);
            stats.enums += @intCast(module.enums.len);
            stats.macros += @intCast(module.macros.len);
            stats.typedefs += @intCast(module.typedefs.len);
            stats.type_aliases += @intCast(module.type_aliases.len);
            stats.concepts += @intCast(module.concepts.len);

            // Count documented
            for (module.functions) |func| {
                if (func.doc != null) stats.documented += 1 else stats.undocumented += 1;
            }
            for (module.classes) |class| {
                if (class.doc != null) stats.documented += 1 else stats.undocumented += 1;
            }
            for (module.structs) |s| {
                if (s.doc != null) stats.documented += 1 else stats.undocumented += 1;
            }
            for (module.enums) |e| {
                if (e.doc != null) stats.documented += 1 else stats.undocumented += 1;
            }
        }

        const total = stats.documented + stats.undocumented;
        if (total > 0) {
            stats.coverage_percent = @as(f64, @floatFromInt(stats.documented)) / @as(f64, @floatFromInt(total)) * 100.0;
        }

        return stats;
    }

    fn buildModuleDoc(self: *Self, module: types.Module, arena: std.mem.Allocator) !schema.ModuleDoc {
        const module_id = try self.generateModuleId(module.name, arena);
        const module_path = try self.generateModulePath(module.name, arena);

        // Build functions
        var functions: std.ArrayList(schema.FunctionDoc) = .empty;
        for (module.functions) |func| {
            const func_doc = try self.buildFunctionDoc(func, module.name, arena);
            try functions.append(arena, func_doc);
        }

        // Build classes
        var classes: std.ArrayList(schema.ClassDoc) = .empty;
        for (module.classes) |class| {
            const class_doc = try self.buildClassDoc(class, module.name, arena);
            try classes.append(arena, class_doc);
        }

        // Build structs
        var structs: std.ArrayList(schema.StructDoc) = .empty;
        for (module.structs) |s| {
            const struct_doc = try self.buildStructDoc(s, module.name, arena);
            try structs.append(arena, struct_doc);
        }

        // Build enums
        var enums: std.ArrayList(schema.EnumDoc) = .empty;
        for (module.enums) |e| {
            const enum_doc = try self.buildEnumDoc(e, module.name, arena);
            try enums.append(arena, enum_doc);
        }

        // Build includes
        var includes: std.ArrayList(schema.IncludeDoc) = .empty;
        for (module.includes) |inc| {
            try includes.append(arena, schema.IncludeDoc{
                .path = inc.path,
                .is_system = inc.is_system,
                .resolved = null,
            });
        }

        return schema.ModuleDoc{
            .id = module_id,
            .name = module.name,
            .path = module_path,
            .title = null,
            .file_doc = if (module.file_doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .includes = try arena.dupe(schema.IncludeDoc, includes.items),
            .functions = try arena.dupe(schema.FunctionDoc, functions.items),
            .classes = try arena.dupe(schema.ClassDoc, classes.items),
            .structs = try arena.dupe(schema.StructDoc, structs.items),
            .enums = try arena.dupe(schema.EnumDoc, enums.items),
        };
    }

    fn buildFunctionDoc(self: *Self, func: types.Function, _: []const u8, arena: std.mem.Allocator) !schema.FunctionDoc {
        const anchor = try self.generateAnchor(func.name, arena);
        const signature = try self.buildFunctionSignature(func, arena);

        // Build parameters
        var params: std.ArrayList(schema.ParameterDoc) = .empty;
        for (func.params) |param| {
            try params.append(arena, schema.ParameterDoc{
                .name = param.name,
                .type_str = param.type_str,
                .doc = param.doc,
            });
        }

        return schema.FunctionDoc{
            .id = anchor,
            .name = func.name,
            .qualified_name = func.name,
            .anchor = anchor,
            .signature = signature,
            .return_type = func.return_type,
            .parameters = try arena.dupe(schema.ParameterDoc, params.items),
            .doc = if (func.doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .location = schema.LocationDoc{
                .file = func.location.file,
                .line = func.location.line,
                .column = func.location.column,
            },
            .source_url = null,
            .qualifiers = schema.FunctionQualifiers{
                .is_static = func.is_static,
                .is_inline = func.is_inline,
                .is_constexpr = func.is_constexpr,
                .is_consteval = func.is_consteval,
                .is_noexcept = func.is_noexcept,
            },
        };
    }

    fn buildClassDoc(self: *Self, class: types.Class, _: []const u8, arena: std.mem.Allocator) !schema.ClassDoc {
        const anchor = try self.generateAnchor(class.name, arena);

        // Build members organized by access
        var public_methods: std.ArrayList(schema.MethodDoc) = .empty;
        var protected_methods: std.ArrayList(schema.MethodDoc) = .empty;
        var private_methods: std.ArrayList(schema.MethodDoc) = .empty;

        var public_fields: std.ArrayList(schema.FieldDoc) = .empty;
        var protected_fields: std.ArrayList(schema.FieldDoc) = .empty;
        var private_fields: std.ArrayList(schema.FieldDoc) = .empty;

        for (class.methods) |method| {
            const method_doc = try self.buildMethodDoc(method, arena);
            switch (method.access) {
                .public => try public_methods.append(arena, method_doc),
                .protected => try protected_methods.append(arena, method_doc),
                .private => try private_methods.append(arena, method_doc),
            }
        }

        for (class.fields) |field| {
            const field_doc = schema.FieldDoc{
                .name = field.name,
                .type_str = field.type_str,
                .doc = field.doc,
            };
            switch (field.access) {
                .public => try public_fields.append(arena, field_doc),
                .protected => try protected_fields.append(arena, field_doc),
                .private => try private_fields.append(arena, field_doc),
            }
        }

        return schema.ClassDoc{
            .id = anchor,
            .name = class.name,
            .qualified_name = class.name,
            .anchor = anchor,
            .doc = if (class.doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .location = schema.LocationDoc{
                .file = class.location.file,
                .line = class.location.line,
                .column = class.location.column,
            },
            .source_url = null,
            .members = schema.ClassMembers{
                .public = schema.MemberGroup{
                    .methods = try arena.dupe(schema.MethodDoc, public_methods.items),
                    .fields = try arena.dupe(schema.FieldDoc, public_fields.items),
                },
                .protected = schema.MemberGroup{
                    .methods = try arena.dupe(schema.MethodDoc, protected_methods.items),
                    .fields = try arena.dupe(schema.FieldDoc, protected_fields.items),
                },
                .private = schema.MemberGroup{
                    .methods = try arena.dupe(schema.MethodDoc, private_methods.items),
                    .fields = try arena.dupe(schema.FieldDoc, private_fields.items),
                },
            },
        };
    }

    fn buildMethodDoc(self: *Self, method: types.Method, arena: std.mem.Allocator) !schema.MethodDoc {
        const anchor = try self.generateAnchor(method.name, arena);
        const signature = try self.buildMethodSignature(method, arena);

        // Build parameters
        var params: std.ArrayList(schema.ParameterDoc) = .empty;
        for (method.params) |param| {
            try params.append(arena, schema.ParameterDoc{
                .name = param.name,
                .type_str = param.type_str,
                .doc = param.doc,
            });
        }

        return schema.MethodDoc{
            .id = anchor,
            .name = method.name,
            .anchor = anchor,
            .signature = signature,
            .return_type = method.return_type,
            .parameters = try arena.dupe(schema.ParameterDoc, params.items),
            .kind = switch (method.kind) {
                .regular => .regular,
                .constructor => .constructor,
                .copy_constructor => .copy_constructor,
                .move_constructor => .move_constructor,
                .destructor => .destructor,
                .operator_overload => .operator_overload,
                .conversion_operator => .conversion_operator,
            },
            .operator_symbol = method.operator_symbol,
            .doc = if (method.doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .qualifiers = schema.MethodQualifiers{
                .is_virtual = method.is_virtual,
                .is_static = method.is_static,
                .is_const = method.is_const,
                .is_override = method.is_override,
                .is_final = method.is_final,
                .is_pure_virtual = method.is_pure_virtual,
                .is_defaulted = method.is_defaulted,
                .is_deleted = method.is_deleted,
                .is_constexpr = method.is_constexpr,
                .is_consteval = method.is_consteval,
                .is_explicit = method.is_explicit,
                .is_noexcept = method.is_noexcept,
            },
            .location = schema.LocationDoc{
                .file = method.location.file,
                .line = method.location.line,
                .column = method.location.column,
            },
        };
    }

    fn buildStructDoc(self: *Self, s: types.Struct, _: []const u8, arena: std.mem.Allocator) !schema.StructDoc {
        const anchor = try self.generateAnchor(s.name, arena);

        var fields: std.ArrayList(schema.FieldDoc) = .empty;
        for (s.fields) |field| {
            try fields.append(arena, schema.FieldDoc{
                .name = field.name,
                .type_str = field.type_str,
                .doc = field.doc,
            });
        }

        return schema.StructDoc{
            .id = anchor,
            .name = s.name,
            .qualified_name = s.name,
            .anchor = anchor,
            .fields = try arena.dupe(schema.FieldDoc, fields.items),
            .doc = if (s.doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .location = schema.LocationDoc{
                .file = s.location.file,
                .line = s.location.line,
                .column = s.location.column,
            },
            .source_url = null,
        };
    }

    fn buildEnumDoc(self: *Self, e: types.Enum, _: []const u8, arena: std.mem.Allocator) !schema.EnumDoc {
        const anchor = try self.generateAnchor(e.name, arena);

        var values: std.ArrayList(schema.EnumValueDoc) = .empty;
        for (e.values) |val| {
            try values.append(arena, schema.EnumValueDoc{
                .name = val.name,
                .value = val.value,
                .doc = val.doc,
            });
        }

        return schema.EnumDoc{
            .id = anchor,
            .name = e.name,
            .qualified_name = e.name,
            .anchor = anchor,
            .values = try arena.dupe(schema.EnumValueDoc, values.items),
            .doc = if (e.doc) |doc| try self.buildDocStringDoc(doc, arena) else null,
            .location = schema.LocationDoc{
                .file = e.location.file,
                .line = e.location.line,
                .column = e.location.column,
            },
            .source_url = null,
        };
    }

    fn buildDocStringDoc(self: *Self, doc: types.DocString, arena: std.mem.Allocator) !schema.DocStringDoc {
        // Build params
        var params: std.ArrayList(schema.ParamDoc) = .empty;
        for (doc.params) |param| {
            try params.append(arena, schema.ParamDoc{
                .name = param.name,
                .description = param.description,
            });
        }

        // Build resolved refs
        var refs: std.ArrayList(schema.ResolvedRefDoc) = .empty;
        for (doc.refs) |ref| {
            const resolved_url = if (self.symbol_table) |st|
                self.resolveReference(ref.target, st, arena)
            else
                null;

            try refs.append(arena, schema.ResolvedRefDoc{
                .target = ref.target,
                .display_text = ref.display_text,
                .resolved_url = resolved_url,
                .is_external = false,
            });
        }

        return schema.DocStringDoc{
            .raw = doc.raw,
            .brief = doc.brief,
            .details = doc.details,
            .params = try arena.dupe(schema.ParamDoc, params.items),
            .returns = doc.returns,
            .refs = try arena.dupe(schema.ResolvedRefDoc, refs.items),
        };
    }

    fn buildIndex(_: *Self, modules: []const schema.ModuleDoc, arena: std.mem.Allocator) ![]schema.IndexEntry {
        var index: std.ArrayList(schema.IndexEntry) = .empty;

        for (modules) |module| {
            // Index functions
            for (module.functions) |func| {
                try index.append(arena, schema.IndexEntry{
                    .name = func.name,
                    .qualified_name = func.qualified_name,
                    .kind = .function,
                    .brief = if (func.doc) |doc| doc.brief else null,
                    .module = module.name,
                    .anchor = func.anchor,
                    .path = module.path,
                });
            }

            // Index classes
            for (module.classes) |class| {
                try index.append(arena, schema.IndexEntry{
                    .name = class.name,
                    .qualified_name = class.qualified_name,
                    .kind = .class_,
                    .brief = if (class.doc) |doc| doc.brief else null,
                    .module = module.name,
                    .anchor = class.anchor,
                    .path = module.path,
                });
            }

            // Index structs
            for (module.structs) |s| {
                try index.append(arena, schema.IndexEntry{
                    .name = s.name,
                    .qualified_name = s.qualified_name,
                    .kind = .struct_,
                    .brief = if (s.doc) |doc| doc.brief else null,
                    .module = module.name,
                    .anchor = s.anchor,
                    .path = module.path,
                });
            }

            // Index enums
            for (module.enums) |e| {
                try index.append(arena, schema.IndexEntry{
                    .name = e.name,
                    .qualified_name = e.qualified_name,
                    .kind = .enum_,
                    .brief = if (e.doc) |doc| doc.brief else null,
                    .module = module.name,
                    .anchor = e.anchor,
                    .path = module.path,
                });
            }
        }

        return index.items;
    }

    fn buildAppendix(self: *Self, modules: []const types.Module, arena: std.mem.Allocator) !schema.Appendix {
        _ = self;
        var todos: std.ArrayList(schema.TodoDoc) = .empty;
        const bugs: std.ArrayList(schema.BugDoc) = .empty;
        const tests: std.ArrayList(schema.TestDoc) = .empty;

        for (modules) |module| {
            // Collect TODOs from functions
            for (module.functions) |func| {
                if (func.doc) |doc| {
                    for (doc.todos) |todo| {
                        try todos.append(arena, schema.TodoDoc{
                            .description = todo.description,
                            .location = schema.LocationDoc{
                                .file = func.location.file,
                                .line = func.location.line,
                                .column = func.location.column,
                            },
                            .entity_name = func.name,
                            .entity_kind = .function,
                        });
                    }
                }
            }
        }

        return schema.Appendix{
            .todos = try arena.dupe(schema.TodoDoc, todos.items),
            .bugs = try arena.dupe(schema.BugDoc, bugs.items),
            .tests = try arena.dupe(schema.TestDoc, tests.items),
        };
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    fn generateAnchor(self: *Self, name: []const u8, arena: std.mem.Allocator) ![]const u8 {
        // Check if already generated
        if (self.anchor_map.get(name)) |anchor| {
            return anchor;
        }

        // Generate lowercase, hyphenated anchor
        var anchor: std.ArrayList(u8) = .empty;
        for (name) |c| {
            if (std.ascii.isAlphanumeric(c)) {
                try anchor.append(arena, std.ascii.toLower(c));
            } else if (c == ':' or c == '_') {
                try anchor.append(arena, '-');
            }
        }

        // Handle duplicates
        const base_anchor = try anchor.toOwnedSlice(arena);
        const count_result = try self.anchor_counter.getOrPut(base_anchor);
        if (count_result.found_existing) {
            count_result.value_ptr.* += 1;
            const unique_anchor = try std.fmt.allocPrint(arena, "{s}-{d}", .{ base_anchor, count_result.value_ptr.* });
            try self.anchor_map.put(name, unique_anchor);
            return unique_anchor;
        } else {
            count_result.value_ptr.* = 0;
            try self.anchor_map.put(name, base_anchor);
            return base_anchor;
        }
    }

    fn generateModuleId(self: *Self, name: []const u8, arena: std.mem.Allocator) ![]const u8 {
        _ = self;
        // Convert "include/spatial/point.hpp" -> "include-spatial-point-hpp"
        var id: std.ArrayList(u8) = .empty;
        for (name) |c| {
            if (std.ascii.isAlphanumeric(c)) {
                try id.append(arena, c);
            } else {
                try id.append(arena, '-');
            }
        }
        return id.toOwnedSlice(arena);
    }

    fn generateModulePath(self: *Self, name: []const u8, arena: std.mem.Allocator) ![]const u8 {
        _ = self;
        // Convert "include/spatial/point.hpp" -> "spatial/point"
        // Remove "include/" prefix and file extension
        var path = name;
        if (std.mem.startsWith(u8, path, "include/")) {
            path = path[8..];
        }
        if (std.mem.lastIndexOf(u8, path, ".")) |idx| {
            path = path[0..idx];
        }
        return try arena.dupe(u8, path);
    }

    fn buildFunctionSignature(self: *Self, func: types.Function, arena: std.mem.Allocator) ![]const u8 {
        _ = self;
        var sig: std.ArrayList(u8) = .empty;
        const writer = sig.writer(arena);

        try writer.print("{s} {s}(", .{ func.return_type, func.name });
        for (func.params, 0..) |param, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s} {s}", .{ param.type_str, param.name });
        }
        try writer.writeAll(")");

        return sig.toOwnedSlice(arena);
    }

    fn buildMethodSignature(self: *Self, method: types.Method, arena: std.mem.Allocator) ![]const u8 {
        _ = self;
        var sig: std.ArrayList(u8) = .empty;
        const writer = sig.writer(arena);

        try writer.print("{s} {s}(", .{ method.return_type, method.name });
        for (method.params, 0..) |param, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s} {s}", .{ param.type_str, param.name });
        }
        try writer.writeAll(")");

        if (method.is_const) try writer.writeAll(" const");
        if (method.is_noexcept) try writer.writeAll(" noexcept");

        return sig.toOwnedSlice(arena);
    }

    fn resolveReference(self: *Self, target: []const u8, symbol_table: *xref.SymbolTable, arena: std.mem.Allocator) ?[]const u8 {
        _ = self;
        _ = arena;
        if (symbol_table.lookup(target)) |info| {
            // For now, just return the anchor
            // In multi-file mode, this would be "../module/path#anchor"
            return info.anchor;
        }
        return null;
    }

    fn getTimestamp(self: *Self, arena: std.mem.Allocator) ![]const u8 {
        _ = self;
        const timestamp = std.time.timestamp();
        const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_seconds.getDaySeconds();

        return try std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
    }

    // =========================================================================
    // JSON Serialization
    // =========================================================================

    fn serializeDocumentModel(self: *Self, model: schema.DocumentModel) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Schema version
        try self.writeIndent();
        try self.writeKeyValue("schema_version", model.schema_version);
        try self.writeChar(',');
        try self.writeNewline();

        // Generator
        try self.writeIndent();
        try self.writeKey("generator");
        try self.writeChar('{');
        try self.writeKeyValue("name", model.generator.name);
        try self.writeChar(',');
        try self.writeKeyValue("version", model.generator.version);
        try self.writeChar('}');
        try self.writeChar(',');
        try self.writeNewline();

        // Generated timestamp
        try self.writeIndent();
        try self.writeKeyValue("generated_at", model.generated_at);
        try self.writeChar(',');
        try self.writeNewline();

        // Project
        try self.writeIndent();
        try self.writeKey("project");
        try self.serializeProjectInfo(model.project);
        try self.writeChar(',');
        try self.writeNewline();

        // Config
        try self.writeIndent();
        try self.writeKey("config");
        try self.serializeConfigInfo(model.config);
        try self.writeChar(',');
        try self.writeNewline();

        // Statistics
        try self.writeIndent();
        try self.writeKey("statistics");
        try self.serializeStatistics(model.statistics);
        try self.writeChar(',');
        try self.writeNewline();

        // Index
        try self.writeIndent();
        try self.writeKey("index");
        try self.serializeIndex(model.index);
        try self.writeChar(',');
        try self.writeNewline();

        // Modules
        try self.writeIndent();
        try self.writeKey("modules");
        try self.serializeModules(model.modules);
        try self.writeChar(',');
        try self.writeNewline();

        // Pages
        try self.writeIndent();
        try self.writeKey("pages");
        try self.serializePages(model.pages);
        try self.writeChar(',');
        try self.writeNewline();

        // Appendix
        try self.writeIndent();
        try self.writeKey("appendix");
        try self.serializeAppendix(model.appendix);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeChar('}');
        try self.writeNewline();
    }

    fn serializeStatistics(self: *Self, stats: schema.Statistics) !void {
        try self.writeChar('{');
        try self.writeKey("modules");
        try self.writeUint(stats.modules);
        try self.writeChar(',');
        try self.writeKey("functions");
        try self.writeUint(stats.functions);
        try self.writeChar(',');
        try self.writeKey("coverage_percent");
        try self.writeFloat(stats.coverage_percent);
        try self.writeChar('}');
    }

    // =========================================================================
    // Low-level writing utilities (from old json.zig)
    // =========================================================================

    fn writeChar(self: *Self, c: u8) !void {
        try self.buffer.append(self.allocator, c);
    }

    fn writeString(self: *Self, s: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, s);
    }

    fn writeNewline(self: *Self) !void {
        if (!self.compact) {
            try self.buffer.append(self.allocator, '\n');
        }
    }

    fn writeIndent(self: *Self) !void {
        if (!self.compact) {
            for (0..self.indent_level) |_| {
                try self.buffer.appendSlice(self.allocator, "  ");
            }
        }
    }

    fn writeKey(self: *Self, key: []const u8) !void {
        try self.writeJsonString(key);
        try self.writeString(": ");
    }

    fn writeKeyValue(self: *Self, key: []const u8, value: []const u8) !void {
        try self.writeKey(key);
        try self.writeJsonString(value);
    }

    fn writeJsonString(self: *Self, s: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        for (s) |c| {
            switch (c) {
                '"' => try self.buffer.appendSlice(self.allocator, "\\\""),
                '\\' => try self.buffer.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => {
                    if (c < 0x20) {
                        try self.buffer.appendSlice(self.allocator, "\\u00");
                        const hex = "0123456789abcdef";
                        try self.buffer.append(self.allocator, hex[c >> 4]);
                        try self.buffer.append(self.allocator, hex[c & 0x0f]);
                    } else {
                        try self.buffer.append(self.allocator, c);
                    }
                },
            }
        }
        try self.buffer.append(self.allocator, '"');
    }

    fn writeUint(self: *Self, value: u32) !void {
        var buf: [11]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, result);
    }

    fn writeFloat(self: *Self, value: f64) !void {
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d:.1}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, result);
    }

    fn writeInt(self: *Self, value: anytype) !void {
        var buf: [24]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, result);
    }

    fn writeBool(self: *Self, value: bool) !void {
        try self.buffer.appendSlice(self.allocator, if (value) "true" else "false");
    }

    fn writeNull(self: *Self) !void {
        try self.buffer.appendSlice(self.allocator, "null");
    }

    fn writeOptionalString(self: *Self, value: ?[]const u8) !void {
        if (value) |v| {
            try self.writeJsonString(v);
        } else {
            try self.writeNull();
        }
    }

    // =========================================================================
    // Complex type serialization
    // =========================================================================

    fn serializeProjectInfo(self: *Self, project: schema.ProjectInfo) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("title", project.title);

        if (project.description) |desc| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("description", desc);
        }
        if (project.version) |ver| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("version", ver);
        }
        if (project.authors.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("authors");
            try self.serializeStringArray(project.authors);
        }
        if (project.license) |lic| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("license", lic);
        }
        if (project.repository) |repo| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("repository", repo);
        }

        try self.writeNewline();
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeConfigInfo(self: *Self, config: schema.ConfigInfo) !void {
        try self.writeChar('{');
        try self.writeKey("language");
        try self.writeJsonString(config.language);
        if (config.source_url_template) |tmpl| {
            try self.writeChar(',');
            try self.writeKey("source_url_template");
            try self.writeJsonString(tmpl);
        }
        try self.writeChar('}');
    }

    fn serializeIndex(self: *Self, index: []const schema.IndexEntry) !void {
        try self.writeChar('[');
        if (index.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (index, 0..) |entry, i| {
                try self.writeIndent();
                try self.serializeIndexEntry(entry);
                if (i < index.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeIndexEntry(self: *Self, entry: schema.IndexEntry) !void {
        try self.writeChar('{');
        try self.writeKeyValue("name", entry.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", entry.qualified_name);
        try self.writeChar(',');
        try self.writeKey("kind");
        try self.writeJsonString(@tagName(entry.kind));
        if (entry.brief) |b| {
            try self.writeChar(',');
            try self.writeKeyValue("brief", b);
        }
        try self.writeChar(',');
        try self.writeKeyValue("module", entry.module);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", entry.anchor);
        try self.writeChar(',');
        try self.writeKeyValue("path", entry.path);
        try self.writeChar('}');
    }

    fn serializeModules(self: *Self, modules: []const schema.ModuleDoc) !void {
        try self.writeChar('[');
        if (modules.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (modules, 0..) |mod, i| {
                try self.writeIndent();
                try self.serializeModuleDoc(mod);
                if (i < modules.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeModuleDoc(self: *Self, mod: schema.ModuleDoc) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("id", mod.id);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("name", mod.name);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("path", mod.path);

        if (mod.title) |t| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("title", t);
        }

        if (mod.file_doc) |fd| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("file_doc");
            try self.serializeDocStringDoc(fd);
        }

        if (mod.includes.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("includes");
            try self.serializeIncludes(mod.includes);
        }

        if (mod.functions.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("functions");
            try self.serializeFunctions(mod.functions);
        }

        if (mod.classes.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("classes");
            try self.serializeClasses(mod.classes);
        }

        if (mod.structs.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("structs");
            try self.serializeStructs(mod.structs);
        }

        if (mod.unions.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("unions");
            try self.serializeUnions(mod.unions);
        }

        if (mod.enums.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("enums");
            try self.serializeEnums(mod.enums);
        }

        if (mod.typedefs.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("typedefs");
            try self.serializeTypedefs(mod.typedefs);
        }

        if (mod.type_aliases.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("type_aliases");
            try self.serializeTypeAliases(mod.type_aliases);
        }

        if (mod.macros.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("macros");
            try self.serializeMacros(mod.macros);
        }

        if (mod.concepts.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("concepts");
            try self.serializeConcepts(mod.concepts);
        }

        if (mod.namespaces.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("namespaces");
            try self.serializeNamespaces(mod.namespaces);
        }

        try self.writeNewline();
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeIncludes(self: *Self, includes: []const schema.IncludeDoc) !void {
        try self.writeChar('[');
        for (includes, 0..) |inc, i| {
            try self.writeChar('{');
            try self.writeKeyValue("path", inc.path);
            try self.writeChar(',');
            try self.writeKey("is_system");
            try self.writeBool(inc.is_system);
            if (inc.resolved) |r| {
                try self.writeChar(',');
                try self.writeKeyValue("resolved", r);
            }
            try self.writeChar('}');
            if (i < includes.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeFunctions(self: *Self, funcs: []const schema.FunctionDoc) !void {
        try self.writeChar('[');
        if (funcs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (funcs, 0..) |f, i| {
                try self.writeIndent();
                try self.serializeFunctionDoc(f);
                if (i < funcs.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeFunctionDoc(self: *Self, func: schema.FunctionDoc) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("id", func.id);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("name", func.name);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("qualified_name", func.qualified_name);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("anchor", func.anchor);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("signature", func.signature);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("return_type", func.return_type);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("parameters");
        try self.serializeParameters(func.parameters);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("template_params");
        try self.serializeTemplateParams(func.template_params);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("requires_clause");
        try self.writeOptionalString(func.requires_clause);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("doc");
        if (func.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(func.location);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("source_url");
        try self.writeOptionalString(func.source_url);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("qualifiers");
        try self.serializeFunctionQualifiers(func.qualifiers);

        try self.writeNewline();
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeParameters(self: *Self, params: []const schema.ParameterDoc) !void {
        try self.writeChar('[');
        for (params, 0..) |p, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", p.name);
            try self.writeChar(',');
            try self.writeKeyValue("type_str", p.type_str);
            if (p.doc) |d| {
                try self.writeChar(',');
                try self.writeKeyValue("doc", d);
            }
            try self.writeChar('}');
            if (i < params.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeTemplateParams(self: *Self, params: []const schema.TemplateParamDoc) !void {
        try self.writeChar('[');
        for (params, 0..) |p, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", p.name);
            try self.writeChar(',');
            try self.writeKeyValue("kind", p.kind);
            try self.writeChar(',');
            try self.writeKey("is_variadic");
            try self.writeBool(p.is_variadic);
            if (p.default_value) |dv| {
                try self.writeChar(',');
                try self.writeKeyValue("default_value", dv);
            }
            if (p.doc) |d| {
                try self.writeChar(',');
                try self.writeKeyValue("doc", d);
            }
            try self.writeChar('}');
            if (i < params.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeLocation(self: *Self, loc: schema.LocationDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("file", loc.file);
        try self.writeChar(',');
        try self.writeKey("line");
        try self.writeUint(loc.line);
        try self.writeChar(',');
        try self.writeKey("column");
        try self.writeUint(loc.column);
        try self.writeChar('}');
    }

    fn serializeFunctionQualifiers(self: *Self, q: schema.FunctionQualifiers) !void {
        try self.writeChar('{');
        try self.writeKey("is_static");
        try self.writeBool(q.is_static);
        try self.writeChar(',');
        try self.writeKey("is_inline");
        try self.writeBool(q.is_inline);
        try self.writeChar(',');
        try self.writeKey("is_constexpr");
        try self.writeBool(q.is_constexpr);
        try self.writeChar(',');
        try self.writeKey("is_consteval");
        try self.writeBool(q.is_consteval);
        try self.writeChar(',');
        try self.writeKey("is_noexcept");
        try self.writeBool(q.is_noexcept);
        try self.writeChar('}');
    }

    fn serializeClasses(self: *Self, classes: []const schema.ClassDoc) std.mem.Allocator.Error!void {
        try self.writeChar('[');
        if (classes.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (classes, 0..) |c, i| {
                try self.writeIndent();
                try self.serializeClassDoc(c);
                if (i < classes.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeClassDoc(self: *Self, class: schema.ClassDoc) std.mem.Allocator.Error!void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("id", class.id);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("name", class.name);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("qualified_name", class.qualified_name);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyValue("anchor", class.anchor);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("template_params");
        try self.serializeTemplateParams(class.template_params);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("requires_clause");
        try self.writeOptionalString(class.requires_clause);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("base_classes");
        try self.serializeBaseClasses(class.base_classes);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("doc");
        if (class.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(class.location);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("members");
        try self.serializeClassMembers(class.members);

        if (class.nested_classes.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("nested_classes");
            try self.serializeClasses(class.nested_classes);
        }

        if (class.nested_enums.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("nested_enums");
            try self.serializeEnums(class.nested_enums);
        }

        if (class.friends.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("friends");
            try self.serializeFriends(class.friends);
        }

        try self.writeNewline();
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeBaseClasses(self: *Self, bases: []const schema.BaseClassDoc) !void {
        try self.writeChar('[');
        for (bases, 0..) |b, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", b.name);
            try self.writeChar(',');
            try self.writeKey("access");
            try self.writeJsonString(@tagName(b.access));
            try self.writeChar(',');
            try self.writeKey("is_virtual");
            try self.writeBool(b.is_virtual);
            if (b.resolved_link) |link| {
                try self.writeChar(',');
                try self.writeKeyValue("resolved_link", link);
            }
            try self.writeChar('}');
            if (i < bases.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeClassMembers(self: *Self, members: schema.ClassMembers) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKey("public");
        try self.serializeMemberGroup(members.public);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("protected");
        try self.serializeMemberGroup(members.protected);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("private");
        try self.serializeMemberGroup(members.private);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeMemberGroup(self: *Self, group: schema.MemberGroup) !void {
        try self.writeChar('{');
        try self.writeKey("methods");
        try self.serializeMethods(group.methods);
        try self.writeChar(',');
        try self.writeKey("fields");
        try self.serializeFields(group.fields);
        try self.writeChar('}');
    }

    fn serializeMethods(self: *Self, methods: []const schema.MethodDoc) !void {
        try self.writeChar('[');
        if (methods.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (methods, 0..) |m, i| {
                try self.writeIndent();
                try self.serializeMethodDoc(m);
                if (i < methods.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeMethodDoc(self: *Self, method: schema.MethodDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", method.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", method.name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", method.anchor);
        try self.writeChar(',');
        try self.writeKeyValue("signature", method.signature);
        try self.writeChar(',');
        try self.writeKeyValue("return_type", method.return_type);
        try self.writeChar(',');
        try self.writeKey("parameters");
        try self.serializeParameters(method.parameters);
        try self.writeChar(',');
        try self.writeKey("kind");
        try self.writeJsonString(@tagName(method.kind));
        if (method.operator_symbol) |op| {
            try self.writeChar(',');
            try self.writeKeyValue("operator_symbol", op);
        }
        try self.writeChar(',');
        try self.writeKey("doc");
        if (method.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("qualifiers");
        try self.serializeMethodQualifiers(method.qualifiers);
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(method.location);
        try self.writeChar('}');
    }

    fn serializeMethodQualifiers(self: *Self, q: schema.MethodQualifiers) !void {
        try self.writeChar('{');
        try self.writeKey("is_virtual");
        try self.writeBool(q.is_virtual);
        try self.writeChar(',');
        try self.writeKey("is_static");
        try self.writeBool(q.is_static);
        try self.writeChar(',');
        try self.writeKey("is_const");
        try self.writeBool(q.is_const);
        try self.writeChar(',');
        try self.writeKey("is_override");
        try self.writeBool(q.is_override);
        try self.writeChar(',');
        try self.writeKey("is_final");
        try self.writeBool(q.is_final);
        try self.writeChar(',');
        try self.writeKey("is_pure_virtual");
        try self.writeBool(q.is_pure_virtual);
        try self.writeChar(',');
        try self.writeKey("is_defaulted");
        try self.writeBool(q.is_defaulted);
        try self.writeChar(',');
        try self.writeKey("is_deleted");
        try self.writeBool(q.is_deleted);
        try self.writeChar(',');
        try self.writeKey("is_constexpr");
        try self.writeBool(q.is_constexpr);
        try self.writeChar(',');
        try self.writeKey("is_noexcept");
        try self.writeBool(q.is_noexcept);
        try self.writeChar('}');
    }

    fn serializeFields(self: *Self, fields: []const schema.FieldDoc) !void {
        try self.writeChar('[');
        for (fields, 0..) |f, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", f.name);
            try self.writeChar(',');
            try self.writeKeyValue("type_str", f.type_str);
            if (f.doc) |d| {
                try self.writeChar(',');
                try self.writeKeyValue("doc", d);
            }
            try self.writeChar('}');
            if (i < fields.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeFriends(self: *Self, friends: []const schema.FriendDoc) !void {
        try self.writeChar('[');
        for (friends, 0..) |f, i| {
            try self.writeChar('{');
            try self.writeKey("kind");
            try self.writeJsonString(@tagName(f.kind));
            try self.writeChar(',');
            try self.writeKeyValue("name", f.name);
            if (f.signature) |sig| {
                try self.writeChar(',');
                try self.writeKeyValue("signature", sig);
            }
            try self.writeChar('}');
            if (i < friends.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeStructs(self: *Self, structs: []const schema.StructDoc) !void {
        try self.writeChar('[');
        if (structs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (structs, 0..) |s, i| {
                try self.writeIndent();
                try self.serializeStructDoc(s);
                if (i < structs.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeStructDoc(self: *Self, s: schema.StructDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", s.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", s.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", s.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", s.anchor);
        try self.writeChar(',');
        try self.writeKey("fields");
        try self.serializeFields(s.fields);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (s.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(s.location);
        try self.writeChar('}');
    }

    fn serializeUnions(self: *Self, unions: []const schema.UnionDoc) !void {
        try self.writeChar('[');
        if (unions.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (unions, 0..) |u, i| {
                try self.writeIndent();
                try self.serializeUnionDoc(u);
                if (i < unions.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeUnionDoc(self: *Self, u: schema.UnionDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", u.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", u.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", u.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", u.anchor);
        try self.writeChar(',');
        try self.writeKey("fields");
        try self.serializeFields(u.fields);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (u.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(u.location);
        try self.writeChar('}');
    }

    fn serializeEnums(self: *Self, enums: []const schema.EnumDoc) !void {
        try self.writeChar('[');
        if (enums.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (enums, 0..) |e, i| {
                try self.writeIndent();
                try self.serializeEnumDoc(e);
                if (i < enums.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeEnumDoc(self: *Self, e: schema.EnumDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", e.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", e.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", e.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", e.anchor);
        try self.writeChar(',');
        try self.writeKey("values");
        try self.serializeEnumValues(e.values);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (e.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(e.location);
        try self.writeChar('}');
    }

    fn serializeEnumValues(self: *Self, values: []const schema.EnumValueDoc) !void {
        try self.writeChar('[');
        for (values, 0..) |v, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", v.name);
            if (v.value) |val| {
                try self.writeChar(',');
                try self.writeKey("value");
                try self.writeInt(val);
            }
            if (v.doc) |d| {
                try self.writeChar(',');
                try self.writeKeyValue("doc", d);
            }
            try self.writeChar('}');
            if (i < values.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeTypedefs(self: *Self, typedefs: []const schema.TypedefDoc) !void {
        try self.writeChar('[');
        if (typedefs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (typedefs, 0..) |t, i| {
                try self.writeIndent();
                try self.serializeTypedefDoc(t);
                if (i < typedefs.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeTypedefDoc(self: *Self, t: schema.TypedefDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", t.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", t.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", t.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", t.anchor);
        try self.writeChar(',');
        try self.writeKeyValue("underlying", t.underlying);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (t.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(t.location);
        try self.writeChar('}');
    }

    fn serializeTypeAliases(self: *Self, aliases: []const schema.TypeAliasDoc) !void {
        try self.writeChar('[');
        if (aliases.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (aliases, 0..) |a, i| {
                try self.writeIndent();
                try self.serializeTypeAliasDoc(a);
                if (i < aliases.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeTypeAliasDoc(self: *Self, a: schema.TypeAliasDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", a.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", a.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", a.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", a.anchor);
        try self.writeChar(',');
        try self.writeKeyValue("underlying_type", a.underlying_type);
        try self.writeChar(',');
        try self.writeKey("template_params");
        try self.serializeTemplateParams(a.template_params);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (a.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(a.location);
        try self.writeChar('}');
    }

    fn serializeMacros(self: *Self, macros: []const schema.MacroDoc) !void {
        try self.writeChar('[');
        if (macros.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (macros, 0..) |m, i| {
                try self.writeIndent();
                try self.serializeMacroDoc(m);
                if (i < macros.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeMacroDoc(self: *Self, m: schema.MacroDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", m.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", m.name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", m.anchor);
        try self.writeChar(',');
        try self.writeKey("params");
        if (m.params) |params| {
            try self.serializeStringArray(params);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKeyValue("body", m.body);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (m.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(m.location);
        try self.writeChar('}');
    }

    fn serializeConcepts(self: *Self, concepts: []const schema.ConceptDoc) !void {
        try self.writeChar('[');
        if (concepts.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (concepts, 0..) |c, i| {
                try self.writeIndent();
                try self.serializeConceptDoc(c);
                if (i < concepts.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeConceptDoc(self: *Self, c: schema.ConceptDoc) !void {
        try self.writeChar('{');
        try self.writeKeyValue("id", c.id);
        try self.writeChar(',');
        try self.writeKeyValue("name", c.name);
        try self.writeChar(',');
        try self.writeKeyValue("qualified_name", c.qualified_name);
        try self.writeChar(',');
        try self.writeKeyValue("anchor", c.anchor);
        try self.writeChar(',');
        try self.writeKeyValue("constraint", c.constraint);
        try self.writeChar(',');
        try self.writeKey("template_params");
        try self.serializeTemplateParams(c.template_params);
        try self.writeChar(',');
        try self.writeKey("doc");
        if (c.doc) |d| {
            try self.serializeDocStringDoc(d);
        } else {
            try self.writeNull();
        }
        try self.writeChar(',');
        try self.writeKey("location");
        try self.serializeLocation(c.location);
        try self.writeChar('}');
    }

    fn serializeNamespaces(self: *Self, namespaces: []const schema.NamespaceDoc) !void {
        try self.writeChar('[');
        for (namespaces, 0..) |ns, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", ns.name);
            try self.writeChar(',');
            try self.writeKeyValue("qualified_name", ns.qualified_name);
            try self.writeChar(',');
            try self.writeKey("doc");
            if (ns.doc) |d| {
                try self.serializeDocStringDoc(d);
            } else {
                try self.writeNull();
            }
            try self.writeChar('}');
            if (i < namespaces.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeDocStringDoc(self: *Self, doc: schema.DocStringDoc) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("raw", doc.raw);

        if (doc.brief) |b| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("brief", b);
        }

        if (doc.details) |d| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("details", d);
        }

        if (doc.params.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("params");
            try self.serializeParamDocs(doc.params);
        }

        if (doc.tparams.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("tparams");
            try self.serializeParamDocs(doc.tparams);
        }

        if (doc.returns) |r| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("returns", r);
        }

        if (doc.retvals.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("retvals");
            try self.serializeRetvalDocs(doc.retvals);
        }

        if (doc.exceptions.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("exceptions");
            try self.serializeExceptionDocs(doc.exceptions);
        }

        if (doc.examples.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("examples");
            try self.serializeStringArray(doc.examples);
        }

        if (doc.code_blocks.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("code_blocks");
            try self.serializeCodeBlocks(doc.code_blocks);
        }

        if (doc.notes.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("notes");
            try self.serializeStringArray(doc.notes);
        }

        if (doc.warnings.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("warnings");
            try self.serializeStringArray(doc.warnings);
        }

        if (doc.deprecated) |dep| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("deprecated", dep);
        }

        if (doc.see_also.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("see_also");
            try self.serializeResolvedRefs(doc.see_also);
        }

        if (doc.since) |s| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("since", s);
        }

        if (doc.author) |a| {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKeyValue("author", a);
        }

        if (doc.refs.len > 0) {
            try self.writeChar(',');
            try self.writeNewline();
            try self.writeIndent();
            try self.writeKey("refs");
            try self.serializeResolvedRefs(doc.refs);
        }

        try self.writeNewline();
        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeParamDocs(self: *Self, params: []const schema.ParamDoc) !void {
        try self.writeChar('[');
        for (params, 0..) |p, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", p.name);
            try self.writeChar(',');
            try self.writeKeyValue("description", p.description);
            try self.writeChar('}');
            if (i < params.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeRetvalDocs(self: *Self, retvals: []const schema.RetvalDoc) !void {
        try self.writeChar('[');
        for (retvals, 0..) |r, i| {
            try self.writeChar('{');
            try self.writeKeyValue("value", r.value);
            try self.writeChar(',');
            try self.writeKeyValue("description", r.description);
            try self.writeChar('}');
            if (i < retvals.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeExceptionDocs(self: *Self, exceptions: []const schema.ExceptionDoc) !void {
        try self.writeChar('[');
        for (exceptions, 0..) |e, i| {
            try self.writeChar('{');
            try self.writeKeyValue("exception_type", e.exception_type);
            try self.writeChar(',');
            try self.writeKeyValue("description", e.description);
            try self.writeChar('}');
            if (i < exceptions.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeCodeBlocks(self: *Self, blocks: []const schema.CodeBlockDoc) !void {
        try self.writeChar('[');
        for (blocks, 0..) |b, i| {
            try self.writeChar('{');
            try self.writeKeyValue("content", b.content);
            if (b.language) |lang| {
                try self.writeChar(',');
                try self.writeKeyValue("language", lang);
            }
            try self.writeChar(',');
            try self.writeKey("show_line_numbers");
            try self.writeBool(b.show_line_numbers);
            try self.writeChar('}');
            if (i < blocks.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeResolvedRefs(self: *Self, refs: []const schema.ResolvedRefDoc) !void {
        try self.writeChar('[');
        for (refs, 0..) |r, i| {
            try self.writeChar('{');
            try self.writeKeyValue("target", r.target);
            if (r.display_text) |dt| {
                try self.writeChar(',');
                try self.writeKeyValue("display_text", dt);
            }
            if (r.resolved_url) |url| {
                try self.writeChar(',');
                try self.writeKeyValue("resolved_url", url);
            }
            try self.writeChar(',');
            try self.writeKey("is_external");
            try self.writeBool(r.is_external);
            try self.writeChar('}');
            if (i < refs.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeStringArray(self: *Self, strings: []const []const u8) !void {
        try self.writeChar('[');
        for (strings, 0..) |s, i| {
            try self.writeJsonString(s);
            if (i < strings.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializePages(self: *Self, pages: []const schema.PageDoc) !void {
        try self.writeChar('[');
        if (pages.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;
            for (pages, 0..) |p, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeKeyValue("id", p.id);
                try self.writeChar(',');
                try self.writeKeyValue("title", p.title);
                try self.writeChar(',');
                try self.writeKeyValue("content", p.content);
                try self.writeChar(',');
                try self.writeKey("is_mainpage");
                try self.writeBool(p.is_mainpage);
                try self.writeChar('}');
                if (i < pages.len - 1) try self.writeChar(',');
                try self.writeNewline();
            }
            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeAppendix(self: *Self, appendix: schema.Appendix) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKey("todos");
        try self.serializeTodos(appendix.todos);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("bugs");
        try self.serializeBugs(appendix.bugs);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("tests");
        try self.serializeTests(appendix.tests);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeTodos(self: *Self, todos: []const schema.TodoDoc) !void {
        try self.writeChar('[');
        for (todos, 0..) |t, i| {
            try self.writeChar('{');
            try self.writeKeyValue("description", t.description);
            try self.writeChar(',');
            try self.writeKey("location");
            try self.serializeLocation(t.location);
            try self.writeChar(',');
            try self.writeKeyValue("entity_name", t.entity_name);
            try self.writeChar(',');
            try self.writeKey("entity_kind");
            try self.writeJsonString(@tagName(t.entity_kind));
            try self.writeChar('}');
            if (i < todos.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeBugs(self: *Self, bugs: []const schema.BugDoc) !void {
        try self.writeChar('[');
        for (bugs, 0..) |b, i| {
            try self.writeChar('{');
            try self.writeKeyValue("description", b.description);
            try self.writeChar(',');
            try self.writeKey("location");
            try self.serializeLocation(b.location);
            try self.writeChar(',');
            try self.writeKeyValue("entity_name", b.entity_name);
            try self.writeChar(',');
            try self.writeKey("entity_kind");
            try self.writeJsonString(@tagName(b.entity_kind));
            try self.writeChar('}');
            if (i < bugs.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }

    fn serializeTests(self: *Self, tests: []const schema.TestDoc) !void {
        try self.writeChar('[');
        for (tests, 0..) |t, i| {
            try self.writeChar('{');
            try self.writeKeyValue("name", t.name);
            if (t.file) |f| {
                try self.writeChar(',');
                try self.writeKeyValue("file", f);
            }
            if (t.line) |l| {
                try self.writeChar(',');
                try self.writeKey("line");
                try self.writeUint(l);
            }
            try self.writeChar(',');
            try self.writeKeyValue("tests_entity", t.tests_entity);
            try self.writeChar('}');
            if (i < tests.len - 1) try self.writeChar(',');
        }
        try self.writeChar(']');
    }
};
