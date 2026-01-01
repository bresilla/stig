const std = @import("std");
const types = @import("model/types.zig");
const config = @import("config.zig");

/// Type of symbol for cross-referencing
pub const SymbolKind = enum {
    function,
    struct_type,
    class_type,
    enum_type,
    typedef,
    macro,
};

/// Information about a symbol's location in documentation
pub const SymbolInfo = struct {
    /// Kind of symbol
    kind: SymbolKind,
    /// Source file where defined
    source_file: []const u8,
    /// Anchor ID for linking (lowercase, hyphenated)
    anchor: []const u8,
    /// Original name
    name: []const u8,
};

/// Symbol table for cross-reference resolution
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(SymbolInfo),
    /// External documentation link configuration
    external_docs: []const config.ExternalDocLink = &[_]config.ExternalDocLink{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .symbols = std.StringHashMap(SymbolInfo).init(allocator),
        };
    }

    /// Initialize with external documentation configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, cfg: config.Config) Self {
        return Self{
            .allocator = allocator,
            .symbols = std.StringHashMap(SymbolInfo).init(allocator),
            .external_docs = cfg.external_docs,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free allocated anchors - but only once per unique anchor
        // Since short names share anchors with full names, we need to track what we've freed
        // Use pointer address as key since anchors are slices pointing to same memory
        var freed_ptrs = std.AutoHashMap(usize, void).init(self.allocator);
        defer freed_ptrs.deinit();

        var iter = self.symbols.valueIterator();
        while (iter.next()) |info| {
            const ptr_addr = @intFromPtr(info.anchor.ptr);
            const gop = freed_ptrs.getOrPut(ptr_addr) catch continue;
            if (!gop.found_existing) {
                self.allocator.free(info.anchor);
            }
        }
        self.symbols.deinit();
    }

    /// Registers a symbol in the table
    /// Also registers the short name (without namespace) for easier lookup
    pub fn register(self: *Self, name: []const u8, kind: SymbolKind, source_file: []const u8) !void {
        try self.registerWithUniqueName(name, kind, source_file, null);
    }

    /// Registers a symbol with an optional unique name override for linking
    pub fn registerWithUniqueName(self: *Self, name: []const u8, kind: SymbolKind, source_file: []const u8, unique_name: ?[]const u8) !void {
        // Skip if already registered (can happen with multiple modules)
        if (self.symbols.contains(name)) return;

        const anchor = try self.generateAnchor(name);
        const info = SymbolInfo{
            .kind = kind,
            .source_file = source_file,
            .anchor = anchor,
            .name = name,
        };

        // Register with full name
        try self.symbols.put(name, info);

        // Also register with short name (without namespace) if different
        const short_name = self.extractShortName(name);
        if (!std.mem.eql(u8, short_name, name)) {
            // Only register short name if not already taken
            if (!self.symbols.contains(short_name)) {
                try self.symbols.put(short_name, info);
            }
        }

        // Register with unique name override if provided
        if (unique_name) |uname| {
            // Handle relative names (starting with *)
            if (std.mem.startsWith(u8, uname, "*")) {
                // Relative name - prepend parent scope
                if (std.mem.lastIndexOf(u8, name, "::")) |idx| {
                    const parent_scope = name[0 .. idx + 2];
                    const relative_part = uname[1..];
                    const full_unique = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ parent_scope, relative_part });
                    defer self.allocator.free(full_unique);
                    if (!self.symbols.contains(full_unique)) {
                        try self.symbols.put(try self.allocator.dupe(u8, full_unique), info);
                    }
                }
            } else {
                // Absolute unique name
                if (!self.symbols.contains(uname)) {
                    try self.symbols.put(uname, info);
                }
            }
        }
    }

    /// Extracts the short name from a fully qualified name
    /// e.g., "spatial::Point2" -> "Point2"
    fn extractShortName(self: *Self, name: []const u8) []const u8 {
        _ = self;
        if (std.mem.lastIndexOf(u8, name, "::")) |idx| {
            return name[idx + 2 ..];
        }
        return name;
    }

    /// Looks up a symbol by name
    pub fn lookup(self: *Self, name: []const u8) ?SymbolInfo {
        return self.symbols.get(name);
    }

    /// Looks up a symbol with scope-relative resolution
    /// If name starts with *, searches from current_scope outward
    /// If name starts with ?, performs fuzzy matching
    pub fn lookupScoped(self: *Self, name: []const u8, current_scope: []const u8) ?SymbolInfo {
        if (name.len == 0) return null;

        // Check for * prefix (relative lookup)
        if (name[0] == '*') {
            const relative_name = name[1..];
            return self.lookupRelative(relative_name, current_scope);
        }

        // Check for ? prefix (fuzzy lookup)
        if (name[0] == '?') {
            const fuzzy_name = name[1..];
            return self.lookupFuzzy(fuzzy_name, current_scope);
        }

        // Normal lookup
        return self.lookup(name);
    }

    /// Looks up a symbol starting from current scope and moving outward
    fn lookupRelative(self: *Self, name: []const u8, current_scope: []const u8) ?SymbolInfo {
        // Try current scope first
        if (current_scope.len > 0) {
            // Build fully qualified name: current_scope::name
            var qualified = std.ArrayList(u8).init(self.allocator);
            defer qualified.deinit();

            qualified.appendSlice(self.allocator, current_scope) catch return null;
            qualified.appendSlice(self.allocator, "::") catch return null;
            qualified.appendSlice(self.allocator, name) catch return null;

            if (self.symbols.get(qualified.items)) |info| {
                return info;
            }

            // Try parent scopes
            var scope = current_scope;
            while (std.mem.lastIndexOf(u8, scope, "::")) |idx| {
                scope = scope[0..idx];

                qualified.clearRetainingCapacity();
                qualified.appendSlice(self.allocator, scope) catch return null;
                qualified.appendSlice(self.allocator, "::") catch return null;
                qualified.appendSlice(self.allocator, name) catch return null;

                if (self.symbols.get(qualified.items)) |info| {
                    return info;
                }
            }
        }

        // Try global scope
        return self.symbols.get(name);
    }

    /// Looks up a symbol with fuzzy matching (partial name match)
    fn lookupFuzzy(self: *Self, name: []const u8, current_scope: []const u8) ?SymbolInfo {
        // First try relative lookup
        if (self.lookupRelative(name, current_scope)) |info| {
            return info;
        }

        // Then try to find any symbol ending with the name
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.endsWith(u8, key, name)) {
                // Check if it's a proper suffix (preceded by :: or start of string)
                if (key.len == name.len) {
                    return entry.value_ptr.*;
                }
                if (key.len > name.len + 1 and
                    key[key.len - name.len - 2] == ':' and
                    key[key.len - name.len - 1] == ':')
                {
                    return entry.value_ptr.*;
                }
            }
        }

        return null;
    }

    /// Generates a markdown anchor from a name (lowercase, replace spaces/underscores with hyphens)
    fn generateAnchor(self: *Self, name: []const u8) ![]u8 {
        var anchor = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z') {
                anchor[i] = c + 32; // lowercase
            } else if (c == '_' or c == ' ') {
                anchor[i] = '-';
            } else {
                anchor[i] = c;
            }
        }
        return anchor;
    }

    /// Builds symbol table from parsed modules
    pub fn buildFromModules(self: *Self, modules: []const types.Module) !void {
        for (modules) |module| {
            // Register functions with signature-based names for overload disambiguation
            for (module.functions) |func| {
                const unique_name = if (func.doc) |doc| doc.unique_name_override else null;
                try self.registerWithUniqueName(func.name, .function, module.name, unique_name);

                // Also register with signature for overload disambiguation
                const sig_name = try self.generateSignatureName(func.name, func.params);
                if (!std.mem.eql(u8, sig_name, func.name)) {
                    // Only register if different from base name (i.e., has parameters)
                    if (!self.symbols.contains(sig_name)) {
                        const anchor = try self.generateAnchor(func.name);
                        try self.symbols.put(sig_name, SymbolInfo{
                            .kind = .function,
                            .source_file = module.name,
                            .anchor = anchor,
                            .name = func.name,
                        });
                        // Don't free sig_name - it's now owned by the hashmap
                    } else {
                        self.allocator.free(sig_name);
                    }
                } else {
                    self.allocator.free(sig_name);
                }
            }

            // Register structs
            for (module.structs) |s| {
                const unique_name = if (s.doc) |doc| doc.unique_name_override else null;
                try self.registerWithUniqueName(s.name, .struct_type, module.name, unique_name);
            }

            // Register enums
            for (module.enums) |e| {
                const unique_name = if (e.doc) |doc| doc.unique_name_override else null;
                try self.registerWithUniqueName(e.name, .enum_type, module.name, unique_name);
            }

            // Register typedefs
            for (module.typedefs) |td| {
                const unique_name = if (td.doc) |doc| doc.unique_name_override else null;
                try self.registerWithUniqueName(td.name, .typedef, module.name, unique_name);
            }

            // Register classes (C++)
            for (module.classes) |class| {
                const unique_name = if (class.doc) |doc| doc.unique_name_override else null;
                try self.registerWithUniqueName(class.name, .class_type, module.name, unique_name);

                // Register class methods with qualified names (Class::method)
                for (class.methods) |method| {
                    const method_unique_name = if (method.doc) |doc| doc.unique_name_override else null;

                    // Build qualified name: ClassName::methodName
                    const qualified_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class.name, method.name });
                    defer self.allocator.free(qualified_name);

                    try self.registerWithUniqueName(qualified_name, .function, module.name, method_unique_name);

                    // Also register with signature for overload disambiguation
                    const sig_name = try self.generateSignatureName(qualified_name, method.params);
                    if (!std.mem.eql(u8, sig_name, qualified_name)) {
                        if (!self.symbols.contains(sig_name)) {
                            const anchor = try self.generateAnchor(qualified_name);
                            try self.symbols.put(sig_name, SymbolInfo{
                                .kind = .function,
                                .source_file = module.name,
                                .anchor = anchor,
                                .name = qualified_name,
                            });
                        } else {
                            self.allocator.free(sig_name);
                        }
                    } else {
                        self.allocator.free(sig_name);
                    }
                }
            }
        }
    }

    /// Generates a function name with parameter signature for overload disambiguation
    /// e.g., "process" with params [int, double] -> "process(int, double)"
    fn generateSignatureName(self: *Self, name: []const u8, params: []const types.Parameter) ![]u8 {
        if (params.len == 0) {
            return try self.allocator.dupe(u8, name);
        }

        // Calculate total length
        var total_len = name.len + 1; // name + "("
        for (params, 0..) |param, i| {
            if (i > 0) total_len += 2; // ", "
            total_len += param.type_str.len;
        }
        total_len += 1; // ")"

        var result = try self.allocator.alloc(u8, total_len);
        var pos: usize = 0;

        // Copy name
        @memcpy(result[pos..][0..name.len], name);
        pos += name.len;

        // Add "("
        result[pos] = '(';
        pos += 1;

        // Add parameter types
        for (params, 0..) |param, i| {
            if (i > 0) {
                result[pos] = ',';
                result[pos + 1] = ' ';
                pos += 2;
            }
            @memcpy(result[pos..][0..param.type_str.len], param.type_str);
            pos += param.type_str.len;
        }

        // Add ")"
        result[pos] = ')';

        return result;
    }

    /// Generates a relative link to a symbol from a given context
    /// Returns null if symbol not found
    pub fn generateLink(self: *Self, symbol_name: []const u8, from_file: []const u8, output_format: OutputFormat) ?[]const u8 {
        const info = self.lookup(symbol_name) orelse return null;
        _ = from_file; // TODO: Calculate relative path
        _ = output_format;

        // For now, return a simple anchor link
        // In mdbook format, this would be more complex with relative paths
        return info.anchor;
    }

    /// Checks if a symbol matches an external documentation prefix
    /// Returns the external URL if matched, null otherwise
    pub fn getExternalLink(self: *Self, symbol_name: []const u8) ?[]const u8 {
        for (self.external_docs) |ext| {
            if (std.mem.startsWith(u8, symbol_name, ext.prefix)) {
                // Extract the symbol part after the prefix
                const symbol_part = symbol_name[ext.prefix.len..];

                // Replace $$ in template with symbol part
                // For now, just return the template (full implementation would allocate)
                _ = symbol_part;
                return ext.url_template;
            }
        }
        return null;
    }

    /// Generates an external documentation URL for a symbol
    /// Allocates memory for the result
    pub fn generateExternalUrl(self: *Self, symbol_name: []const u8) !?[]const u8 {
        for (self.external_docs) |ext| {
            if (std.mem.startsWith(u8, symbol_name, ext.prefix)) {
                const symbol_part = symbol_name[ext.prefix.len..];

                // Count how many $$ replacements we need
                var replacement_count: usize = 0;
                var i: usize = 0;
                while (i < ext.url_template.len - 1) : (i += 1) {
                    if (ext.url_template[i] == '$' and ext.url_template[i + 1] == '$') {
                        replacement_count += 1;
                        i += 1;
                    }
                }

                if (replacement_count == 0) {
                    // No replacements, just return the template
                    return try self.allocator.dupe(u8, ext.url_template);
                }

                // Calculate result size
                const result_len = ext.url_template.len - (replacement_count * 2) + (replacement_count * symbol_part.len);
                var result = try self.allocator.alloc(u8, result_len);

                // Build result with replacements
                var src_idx: usize = 0;
                var dst_idx: usize = 0;
                while (src_idx < ext.url_template.len) {
                    if (src_idx < ext.url_template.len - 1 and
                        ext.url_template[src_idx] == '$' and
                        ext.url_template[src_idx + 1] == '$')
                    {
                        @memcpy(result[dst_idx..][0..symbol_part.len], symbol_part);
                        dst_idx += symbol_part.len;
                        src_idx += 2;
                    } else {
                        result[dst_idx] = ext.url_template[src_idx];
                        dst_idx += 1;
                        src_idx += 1;
                    }
                }

                return result;
            }
        }
        return null;
    }

    pub const OutputFormat = enum {
        /// Single markdown file - use #anchor links
        markdown,
        /// mdbook structure - use relative path links
        mdbook,
    };
};

/// Cross-reference resolver for markdown generation
pub const XRefResolver = struct {
    symbol_table: *SymbolTable,
    current_file: []const u8,
    output_format: SymbolTable.OutputFormat,

    const Self = @This();

    pub fn init(symbol_table: *SymbolTable, current_file: []const u8, output_format: SymbolTable.OutputFormat) Self {
        return Self{
            .symbol_table = symbol_table,
            .current_file = current_file,
            .output_format = output_format,
        };
    }

    /// Resolves a type name to a markdown link if it exists in the symbol table
    /// Returns the original name if not found
    pub fn resolveTypeLink(self: *Self, type_name: []const u8) []const u8 {
        // Strip pointer/const qualifiers to get base type
        const base_type = self.extractBaseType(type_name);

        if (self.symbol_table.lookup(base_type)) |info| {
            _ = info;
            // For now, just return the base type
            // TODO: Generate actual link syntax
            return base_type;
        }

        return type_name;
    }

    /// Extracts the base type name from a type string
    /// e.g., "const struct Point *" -> "Point"
    fn extractBaseType(self: *Self, type_str: []const u8) []const u8 {
        _ = self;
        var result = type_str;

        // Strip leading const
        if (std.mem.startsWith(u8, result, "const ")) {
            result = result[6..];
        }

        // Strip leading struct/enum/union keywords
        if (std.mem.startsWith(u8, result, "struct ")) {
            result = result[7..];
        } else if (std.mem.startsWith(u8, result, "enum ")) {
            result = result[5..];
        } else if (std.mem.startsWith(u8, result, "union ")) {
            result = result[6..];
        }

        // Strip trailing pointer/reference
        result = std.mem.trimRight(u8, result, " *&");

        return result;
    }

    /// Generates a markdown link for a symbol
    pub fn makeLink(self: *Self, symbol_name: []const u8) ?LinkResult {
        const info = self.symbol_table.lookup(symbol_name) orelse return null;

        return LinkResult{
            .text = symbol_name,
            .anchor = info.anchor,
            .kind = info.kind,
            .target_file = info.source_file,
        };
    }

    /// Resolves a @ref link to a LinkResult
    /// Handles symbols, pages, sections, and anchors
    /// Returns null if the reference cannot be resolved
    pub fn resolveRef(self: *Self, ref: types.RefLink, pages: []const types.Page) ?RefLinkResult {
        // First, try to resolve as a symbol
        if (self.symbol_table.lookup(ref.target)) |info| {
            return RefLinkResult{
                .text = ref.display_text orelse ref.target,
                .anchor = info.anchor,
                .target_file = info.source_file,
                .kind = .symbol,
                .symbol_kind = info.kind,
            };
        }

        // Try to resolve as a page (check if target matches a page ID)
        for (pages) |page| {
            if (std.mem.eql(u8, page.id, ref.target)) {
                return RefLinkResult{
                    .text = ref.display_text orelse page.title,
                    .anchor = page.id,
                    .target_file = page.id, // Page file is based on ID
                    .kind = .page,
                    .symbol_kind = null,
                };
            }
        }

        // TODO: Handle @section and @anchor references
        // For now, return null if not found
        return null;
    }

    pub const LinkResult = struct {
        text: []const u8,
        anchor: []const u8,
        kind: SymbolKind,
        target_file: []const u8,
    };

    pub const RefLinkResult = struct {
        text: []const u8,
        anchor: []const u8,
        target_file: []const u8,
        kind: types.RefKind,
        symbol_kind: ?SymbolKind,
    };
};

// Tests
test "symbol table registration and lookup" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.register("Point", .struct_type, "geometry.h");
    try table.register("add", .function, "math.h");

    const point_info = table.lookup("Point");
    try std.testing.expect(point_info != null);
    try std.testing.expectEqual(SymbolKind.struct_type, point_info.?.kind);
    try std.testing.expectEqualStrings("geometry.h", point_info.?.source_file);

    const add_info = table.lookup("add");
    try std.testing.expect(add_info != null);
    try std.testing.expectEqual(SymbolKind.function, add_info.?.kind);

    const missing = table.lookup("NonExistent");
    try std.testing.expect(missing == null);
}

test "anchor generation" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.register("MyStruct", .struct_type, "test.h");
    try table.register("some_function", .function, "test.h");

    const my_struct = table.lookup("MyStruct");
    try std.testing.expectEqualStrings("mystruct", my_struct.?.anchor);

    const some_func = table.lookup("some_function");
    try std.testing.expectEqualStrings("some-function", some_func.?.anchor);
}

test "extract base type" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    var resolver = XRefResolver.init(&table, "test.h", .markdown);

    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("Point"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("Point *"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("const Point *"));
    try std.testing.expectEqualStrings("Point", resolver.extractBaseType("struct Point"));
    try std.testing.expectEqualStrings("Color", resolver.extractBaseType("enum Color"));
}

test "build from modules" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    const modules = [_]types.Module{
        .{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "test_func",
                    .return_type = "int",
                    .params = &[_]types.Parameter{},
                    .location = .{ .file = "test.h", .line = 1, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{
                .{
                    .name = "TestStruct",
                    .fields = &[_]types.StructField{},
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    try table.buildFromModules(&modules);

    try std.testing.expect(table.lookup("test_func") != null);
    try std.testing.expect(table.lookup("TestStruct") != null);
}
