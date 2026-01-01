const std = @import("std");
const types = @import("../model/types.zig");

/// JSON output generator for Stig documentation
pub const JsonGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,
    indent_level: usize = 0,
    compact: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn initCompact(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .compact = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Generates JSON documentation for the given modules
    pub fn generate(self: *Self, modules: []const types.Module) ![]const u8 {
        // Clear buffer for fresh generation
        self.buffer.clearRetainingCapacity();

        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Version
        try self.writeIndent();
        try self.writeKeyValue("version", "1.0");
        try self.writeChar(',');
        try self.writeNewline();

        // Generator
        try self.writeIndent();
        try self.writeKeyValue("generator", "stig");
        try self.writeChar(',');
        try self.writeNewline();

        // Generated timestamp
        try self.writeIndent();
        try self.writeKey("generated_at");
        try self.writeTimestamp();
        try self.writeChar(',');
        try self.writeNewline();

        // Modules array
        try self.writeIndent();
        try self.writeKey("modules");
        try self.writeChar('[');

        if (modules.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (modules, 0..) |module, i| {
                try self.writeIndent();
                try self.serializeModule(module);
                if (i < modules.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }

        try self.writeChar(']');
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeChar('}');
        try self.writeNewline();

        return self.buffer.items;
    }

    // =========================================================================
    // Module serialization
    // =========================================================================

    fn serializeModule(self: *Self, module: types.Module) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", module.name);
        try self.writeChar(',');
        try self.writeNewline();

        // File documentation
        try self.writeIndent();
        try self.writeKey("file_doc");
        if (module.file_doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Functions
        try self.writeIndent();
        try self.writeKey("functions");
        try self.serializeFunctions(module.functions);
        try self.writeChar(',');
        try self.writeNewline();

        // Classes
        try self.writeIndent();
        try self.writeKey("classes");
        try self.serializeClasses(module.classes);
        try self.writeChar(',');
        try self.writeNewline();

        // Structs
        try self.writeIndent();
        try self.writeKey("structs");
        try self.serializeStructs(module.structs);
        try self.writeChar(',');
        try self.writeNewline();

        // Enums
        try self.writeIndent();
        try self.writeKey("enums");
        try self.serializeEnums(module.enums);
        try self.writeChar(',');
        try self.writeNewline();

        // Typedefs
        try self.writeIndent();
        try self.writeKey("typedefs");
        try self.serializeTypedefs(module.typedefs);
        try self.writeChar(',');
        try self.writeNewline();

        // Type aliases
        try self.writeIndent();
        try self.writeKey("type_aliases");
        try self.serializeTypeAliases(module.type_aliases);
        try self.writeChar(',');
        try self.writeNewline();

        // Macros
        try self.writeIndent();
        try self.writeKey("macros");
        try self.serializeMacros(module.macros);
        try self.writeChar(',');
        try self.writeNewline();

        // Concepts
        try self.writeIndent();
        try self.writeKey("concepts");
        try self.serializeConcepts(module.concepts);
        try self.writeChar(',');
        try self.writeNewline();

        // Groups
        try self.writeIndent();
        try self.writeKey("groups");
        try self.serializeGroups(module.groups);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    // =========================================================================
    // Function serialization
    // =========================================================================

    fn serializeFunctions(self: *Self, functions: []const types.Function) !void {
        try self.writeChar('[');
        if (functions.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (functions, 0..) |func, i| {
                try self.writeIndent();
                try self.serializeFunction(func);
                if (i < functions.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeFunction(self: *Self, func: types.Function) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", func.name);
        try self.writeChar(',');
        try self.writeNewline();

        // Signature
        try self.writeIndent();
        try self.writeKey("signature");
        try self.writeFunctionSignature(func);
        try self.writeChar(',');
        try self.writeNewline();

        // Return type
        try self.writeIndent();
        try self.writeKeyValue("return_type", func.return_type);
        try self.writeChar(',');
        try self.writeNewline();

        // Parameters
        try self.writeIndent();
        try self.writeKey("parameters");
        try self.serializeParameters(func.params);
        try self.writeChar(',');
        try self.writeNewline();

        // Documentation
        try self.writeIndent();
        try self.writeKey("doc");
        if (func.doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Location
        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(func.location);
        try self.writeChar(',');
        try self.writeNewline();

        // Attributes
        try self.writeIndent();
        try self.writeKey("attributes");
        try self.serializeAttributes(func.attributes);
        try self.writeChar(',');
        try self.writeNewline();

        // Template parameters
        try self.writeIndent();
        try self.writeKey("template_params");
        try self.serializeTemplateParams(func.template_params);
        try self.writeChar(',');
        try self.writeNewline();

        // Requires clause
        try self.writeIndent();
        try self.writeKey("requires_clause");
        if (func.requires_clause) |req| {
            try self.writeJsonString(req);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Qualifiers
        try self.writeIndent();
        try self.writeKey("qualifiers");
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyBool("is_static", func.is_static);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_inline", func.is_inline);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_constexpr", func.is_constexpr);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_consteval", func.is_consteval);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_noexcept", func.is_noexcept);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn writeFunctionSignature(self: *Self, func: types.Function) !void {
        // Build signature string
        var sig_buffer: std.ArrayList(u8) = .empty;
        defer sig_buffer.deinit(self.allocator);

        try sig_buffer.appendSlice(self.allocator, func.return_type);
        try sig_buffer.append(self.allocator, ' ');
        try sig_buffer.appendSlice(self.allocator, func.name);
        try sig_buffer.append(self.allocator, '(');

        for (func.params, 0..) |param, i| {
            if (i > 0) {
                try sig_buffer.appendSlice(self.allocator, ", ");
            }
            try sig_buffer.appendSlice(self.allocator, param.type_str);
            try sig_buffer.append(self.allocator, ' ');
            try sig_buffer.appendSlice(self.allocator, param.name);
        }

        try sig_buffer.append(self.allocator, ')');
        try self.writeJsonString(sig_buffer.items);
    }

    fn serializeParameters(self: *Self, params: []const types.Parameter) !void {
        try self.writeChar('[');
        if (params.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (params, 0..) |param, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", param.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("type", param.type_str);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (param.doc) |doc| {
                    try self.writeJsonString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < params.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Class serialization
    // =========================================================================

    const SerializeError = std.mem.Allocator.Error;

    fn serializeClasses(self: *Self, classes: []const types.Class) SerializeError!void {
        try self.writeChar('[');
        if (classes.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (classes, 0..) |class, i| {
                try self.writeIndent();
                try self.serializeClass(class);
                if (i < classes.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeClass(self: *Self, class: types.Class) SerializeError!void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", class.name);
        try self.writeChar(',');
        try self.writeNewline();

        // Namespace
        try self.writeIndent();
        try self.writeKey("namespace");
        if (class.namespace) |ns| {
            try self.writeJsonString(ns);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Documentation
        try self.writeIndent();
        try self.writeKey("doc");
        if (class.doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Location
        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(class.location);
        try self.writeChar(',');
        try self.writeNewline();

        // Base classes
        try self.writeIndent();
        try self.writeKey("base_classes");
        try self.serializeBaseClasses(class.base_classes);
        try self.writeChar(',');
        try self.writeNewline();

        // Template parameters
        try self.writeIndent();
        try self.writeKey("template_params");
        try self.serializeTemplateParams(class.template_params);
        try self.writeChar(',');
        try self.writeNewline();

        // Requires clause
        try self.writeIndent();
        try self.writeKey("requires_clause");
        if (class.requires_clause) |req| {
            try self.writeJsonString(req);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Attributes
        try self.writeIndent();
        try self.writeKey("attributes");
        try self.serializeAttributes(class.attributes);
        try self.writeChar(',');
        try self.writeNewline();

        // Methods
        try self.writeIndent();
        try self.writeKey("methods");
        try self.serializeMethods(class.methods);
        try self.writeChar(',');
        try self.writeNewline();

        // Fields
        try self.writeIndent();
        try self.writeKey("fields");
        try self.serializeClassFields(class.fields);
        try self.writeChar(',');
        try self.writeNewline();

        // Nested classes (use explicit error handling to avoid recursive inference issues)
        try self.writeIndent();
        try self.writeKey("nested_classes");
        self.serializeNestedClasses(class.nested_classes) catch |e| return e;
        try self.writeChar(',');
        try self.writeNewline();

        // Nested enums
        try self.writeIndent();
        try self.writeKey("nested_enums");
        try self.serializeEnums(class.nested_enums);
        try self.writeChar(',');
        try self.writeNewline();

        // Friends
        try self.writeIndent();
        try self.writeKey("friends");
        try self.serializeFriends(class.friends);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    // Helper for nested classes to break the recursive error inference
    fn serializeNestedClasses(self: *Self, classes: []const types.Class) SerializeError!void {
        try self.writeChar('[');
        if (classes.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (classes, 0..) |class, i| {
                try self.writeIndent();
                try self.serializeClass(class);
                if (i < classes.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeBaseClasses(self: *Self, bases: []const types.BaseClass) !void {
        try self.writeChar('[');
        if (bases.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (bases, 0..) |base, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", base.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("access");
                try self.writeJsonString(@tagName(base.access));
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyBool("is_virtual", base.is_virtual);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < bases.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeMethods(self: *Self, methods: []const types.Method) !void {
        try self.writeChar('[');
        if (methods.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (methods, 0..) |method, i| {
                try self.writeIndent();
                try self.serializeMethod(method);
                if (i < methods.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeMethod(self: *Self, method: types.Method) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", method.name);
        try self.writeChar(',');
        try self.writeNewline();

        // Return type
        try self.writeIndent();
        try self.writeKeyValue("return_type", method.return_type);
        try self.writeChar(',');
        try self.writeNewline();

        // Parameters
        try self.writeIndent();
        try self.writeKey("parameters");
        try self.serializeParameters(method.params);
        try self.writeChar(',');
        try self.writeNewline();

        // Documentation
        try self.writeIndent();
        try self.writeKey("doc");
        if (method.doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Access
        try self.writeIndent();
        try self.writeKey("access");
        try self.writeJsonString(@tagName(method.access));
        try self.writeChar(',');
        try self.writeNewline();

        // Kind
        try self.writeIndent();
        try self.writeKey("kind");
        try self.writeJsonString(@tagName(method.kind));
        try self.writeChar(',');
        try self.writeNewline();

        // Operator symbol
        try self.writeIndent();
        try self.writeKey("operator_symbol");
        if (method.operator_symbol) |op| {
            try self.writeJsonString(op);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Attributes
        try self.writeIndent();
        try self.writeKey("attributes");
        try self.serializeAttributes(method.attributes);
        try self.writeChar(',');
        try self.writeNewline();

        // Qualifiers
        try self.writeIndent();
        try self.writeKey("qualifiers");
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyBool("is_virtual", method.is_virtual);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_static", method.is_static);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_const", method.is_const);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_override", method.is_override);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_pure_virtual", method.is_pure_virtual);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_defaulted", method.is_defaulted);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_deleted", method.is_deleted);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_constexpr", method.is_constexpr);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_consteval", method.is_consteval);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_explicit", method.is_explicit);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKeyBool("is_noexcept", method.is_noexcept);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeClassFields(self: *Self, fields: []const types.ClassField) !void {
        try self.writeChar('[');
        if (fields.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (fields, 0..) |field, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", field.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("type", field.type_str);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (field.doc) |doc| {
                    try self.writeJsonString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("access");
                try self.writeJsonString(@tagName(field.access));
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < fields.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeFriends(self: *Self, friends: []const types.Friend) !void {
        try self.writeChar('[');
        if (friends.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (friends, 0..) |friend, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKey("kind");
                try self.writeJsonString(@tagName(friend.kind));
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("name", friend.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("signature");
                if (friend.signature) |sig| {
                    try self.writeJsonString(sig);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < friends.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Struct serialization
    // =========================================================================

    fn serializeStructs(self: *Self, structs: []const types.Struct) !void {
        try self.writeChar('[');
        if (structs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (structs, 0..) |s, i| {
                try self.writeIndent();
                try self.serializeStruct(s);
                if (i < structs.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeStruct(self: *Self, s: types.Struct) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", s.name);
        try self.writeChar(',');
        try self.writeNewline();

        // Documentation
        try self.writeIndent();
        try self.writeKey("doc");
        if (s.doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Location
        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(s.location);
        try self.writeChar(',');
        try self.writeNewline();

        // Fields
        try self.writeIndent();
        try self.writeKey("fields");
        try self.serializeStructFields(s.fields);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeStructFields(self: *Self, fields: []const types.StructField) !void {
        try self.writeChar('[');
        if (fields.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (fields, 0..) |field, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", field.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("type", field.type_str);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (field.doc) |doc| {
                    try self.writeJsonString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < fields.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Enum serialization
    // =========================================================================

    fn serializeEnums(self: *Self, enums: []const types.Enum) !void {
        try self.writeChar('[');
        if (enums.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (enums, 0..) |e, i| {
                try self.writeIndent();
                try self.serializeEnum(e);
                if (i < enums.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeEnum(self: *Self, e: types.Enum) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Name
        try self.writeIndent();
        try self.writeKeyValue("name", e.name);
        try self.writeChar(',');
        try self.writeNewline();

        // Documentation
        try self.writeIndent();
        try self.writeKey("doc");
        if (e.doc) |doc| {
            try self.serializeDocString(doc);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Location
        try self.writeIndent();
        try self.writeKey("location");
        try self.serializeLocation(e.location);
        try self.writeChar(',');
        try self.writeNewline();

        // Values
        try self.writeIndent();
        try self.writeKey("values");
        try self.serializeEnumValues(e.values);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeEnumValues(self: *Self, values: []const types.EnumValue) !void {
        try self.writeChar('[');
        if (values.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (values, 0..) |val, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", val.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("value");
                if (val.value) |v| {
                    try self.writeInt(v);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (val.doc) |doc| {
                    try self.writeJsonString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < values.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Typedef serialization
    // =========================================================================

    fn serializeTypedefs(self: *Self, typedefs: []const types.Typedef) !void {
        try self.writeChar('[');
        if (typedefs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (typedefs, 0..) |td, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", td.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("underlying", td.underlying);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (td.doc) |doc| {
                    try self.serializeDocString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("location");
                try self.serializeLocation(td.location);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < typedefs.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Type alias serialization
    // =========================================================================

    fn serializeTypeAliases(self: *Self, aliases: []const types.TypeAlias) !void {
        try self.writeChar('[');
        if (aliases.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (aliases, 0..) |alias, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", alias.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("underlying_type", alias.underlying_type);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("namespace");
                if (alias.namespace) |ns| {
                    try self.writeJsonString(ns);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("template_params");
                try self.serializeTemplateParams(alias.template_params);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (alias.docstring) |doc| {
                    try self.serializeDocString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < aliases.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Macro serialization
    // =========================================================================

    fn serializeMacros(self: *Self, macros: []const types.Macro) !void {
        try self.writeChar('[');
        if (macros.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (macros, 0..) |macro, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", macro.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("params");
                if (macro.params) |params| {
                    try self.writeStringArray(params);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("body", macro.body);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (macro.doc) |doc| {
                    try self.serializeDocString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("location");
                try self.serializeLocation(macro.location);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < macros.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Concept serialization
    // =========================================================================

    fn serializeConcepts(self: *Self, concepts: []const types.Concept) !void {
        try self.writeChar('[');
        if (concepts.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (concepts, 0..) |concept, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", concept.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("constraint", concept.constraint);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("namespace");
                if (concept.namespace) |ns| {
                    try self.writeJsonString(ns);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("template_params");
                try self.serializeTemplateParams(concept.template_params);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("doc");
                if (concept.docstring) |doc| {
                    try self.serializeDocString(doc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < concepts.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Group serialization
    // =========================================================================

    fn serializeGroups(self: *Self, groups: []const types.Group) !void {
        try self.writeChar('[');
        if (groups.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (groups, 0..) |group, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("id", group.id);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("name", group.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("brief");
                if (group.brief) |brief| {
                    try self.writeJsonString(brief);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < groups.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Common serializers
    // =========================================================================

    fn serializeLocation(self: *Self, loc: types.SourceLocation) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        try self.writeIndent();
        try self.writeKeyValue("file", loc.file);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("line");
        try self.writeUint(loc.line);
        try self.writeChar(',');
        try self.writeNewline();

        try self.writeIndent();
        try self.writeKey("column");
        try self.writeUint(loc.column);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeAttributes(self: *Self, attrs: []const types.Attribute) !void {
        try self.writeChar('[');
        if (attrs.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (attrs, 0..) |attr, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", attr.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("argument");
                if (attr.argument) |arg| {
                    try self.writeJsonString(arg);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < attrs.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeTemplateParams(self: *Self, params: []const types.TemplateParam) !void {
        try self.writeChar('[');
        if (params.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (params, 0..) |param, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", param.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("kind", param.kind);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyBool("is_variadic", param.is_variadic);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("default_value");
                if (param.default_value) |dv| {
                    try self.writeJsonString(dv);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < params.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeDocString(self: *Self, doc: types.DocString) !void {
        try self.writeChar('{');
        try self.writeNewline();
        self.indent_level += 1;

        // Brief
        try self.writeIndent();
        try self.writeKey("brief");
        if (doc.brief) |brief| {
            try self.writeJsonString(brief);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Details
        try self.writeIndent();
        try self.writeKey("details");
        if (doc.details) |details| {
            try self.writeJsonString(details);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Parameters
        try self.writeIndent();
        try self.writeKey("params");
        try self.serializeParamDocs(doc.params);
        try self.writeChar(',');
        try self.writeNewline();

        // Template parameters
        try self.writeIndent();
        try self.writeKey("tparams");
        try self.serializeParamDocs(doc.tparams);
        try self.writeChar(',');
        try self.writeNewline();

        // Returns
        try self.writeIndent();
        try self.writeKey("returns");
        if (doc.returns) |ret| {
            try self.writeJsonString(ret);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Return values
        try self.writeIndent();
        try self.writeKey("retvals");
        try self.serializeRetvalDocs(doc.retvals);
        try self.writeChar(',');
        try self.writeNewline();

        // Exceptions
        try self.writeIndent();
        try self.writeKey("exceptions");
        try self.serializeExceptionDocs(doc.exceptions);
        try self.writeChar(',');
        try self.writeNewline();

        // See also
        try self.writeIndent();
        try self.writeKey("see_also");
        try self.writeStringArray(doc.see_also);
        try self.writeChar(',');
        try self.writeNewline();

        // Deprecated
        try self.writeIndent();
        try self.writeKey("deprecated");
        if (doc.deprecated) |dep| {
            try self.writeJsonString(dep);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Since
        try self.writeIndent();
        try self.writeKey("since");
        if (doc.since) |since| {
            try self.writeJsonString(since);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Author
        try self.writeIndent();
        try self.writeKey("author");
        if (doc.author) |author| {
            try self.writeJsonString(author);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Version
        try self.writeIndent();
        try self.writeKey("version");
        if (doc.version) |version| {
            try self.writeJsonString(version);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Notes
        try self.writeIndent();
        try self.writeKey("notes");
        try self.writeStringArray(doc.notes);
        try self.writeChar(',');
        try self.writeNewline();

        // Warnings
        try self.writeIndent();
        try self.writeKey("warnings");
        try self.writeStringArray(doc.warnings);
        try self.writeChar(',');
        try self.writeNewline();

        // Examples
        try self.writeIndent();
        try self.writeKey("examples");
        try self.writeStringArray(doc.examples);
        try self.writeChar(',');
        try self.writeNewline();

        // Preconditions
        try self.writeIndent();
        try self.writeKey("preconditions");
        try self.writeStringArray(doc.preconditions);
        try self.writeChar(',');
        try self.writeNewline();

        // Postconditions
        try self.writeIndent();
        try self.writeKey("postconditions");
        try self.writeStringArray(doc.postconditions);
        try self.writeChar(',');
        try self.writeNewline();

        // Remarks
        try self.writeIndent();
        try self.writeKey("remarks");
        try self.writeStringArray(doc.remarks);
        try self.writeChar(',');
        try self.writeNewline();

        // Invariants
        try self.writeIndent();
        try self.writeKey("invariants");
        try self.writeStringArray(doc.invariants);
        try self.writeChar(',');
        try self.writeNewline();

        // Effects
        try self.writeIndent();
        try self.writeKey("effects");
        if (doc.effects) |effects| {
            try self.writeJsonString(effects);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Requires
        try self.writeIndent();
        try self.writeKey("requires");
        if (doc.requires) |requires| {
            try self.writeJsonString(requires);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Complexity
        try self.writeIndent();
        try self.writeKey("complexity");
        if (doc.complexity) |complexity| {
            try self.writeJsonString(complexity);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Sync/thread safety
        try self.writeIndent();
        try self.writeKey("sync");
        if (doc.sync) |sync| {
            try self.writeJsonString(sync);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Ingroup
        try self.writeIndent();
        try self.writeKey("ingroup");
        if (doc.ingroup) |ingroup| {
            try self.writeJsonString(ingroup);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Module
        try self.writeIndent();
        try self.writeKey("module");
        if (doc.module) |mod| {
            try self.writeJsonString(mod);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Snippets
        try self.writeIndent();
        try self.writeKey("snippets");
        try self.serializeSnippetRefs(doc.snippets);
        try self.writeChar(',');
        try self.writeNewline();

        // Attention
        try self.writeIndent();
        try self.writeKey("attention");
        try self.writeStringArray(doc.attention);
        try self.writeChar(',');
        try self.writeNewline();

        // Important
        try self.writeIndent();
        try self.writeKey("important");
        try self.writeStringArray(doc.important);
        try self.writeChar(',');
        try self.writeNewline();

        // Dates
        try self.writeIndent();
        try self.writeKey("dates");
        try self.serializeDateInfos(doc.dates);
        try self.writeChar(',');
        try self.writeNewline();

        // Copyright
        try self.writeIndent();
        try self.writeKey("copyright");
        if (doc.copyright) |copyright| {
            try self.writeJsonString(copyright);
        } else {
            try self.writeString("null");
        }
        try self.writeChar(',');
        try self.writeNewline();

        // Mermaid diagrams
        try self.writeIndent();
        try self.writeKey("mermaid_diagrams");
        try self.serializeMermaidDiagrams(doc.mermaid_diagrams);
        try self.writeChar(',');
        try self.writeNewline();

        // Code blocks
        try self.writeIndent();
        try self.writeKey("code_blocks");
        try self.serializeCodeBlocks(doc.code_blocks);
        try self.writeNewline();

        self.indent_level -= 1;
        try self.writeIndent();
        try self.writeChar('}');
    }

    fn serializeCodeBlocks(self: *Self, blocks: []const types.CodeBlock) !void {
        try self.writeChar('[');
        if (blocks.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (blocks, 0..) |block, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("content", block.content);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("language");
                if (block.language) |lang| {
                    try self.writeJsonString(lang);
                } else {
                    try self.writeString("null");
                }
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyBool("show_line_numbers", block.show_line_numbers);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < blocks.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeMermaidDiagrams(self: *Self, diagrams: []const types.MermaidDiagram) !void {
        try self.writeChar('[');
        if (diagrams.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (diagrams, 0..) |diagram, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("content", diagram.content);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("caption");
                if (diagram.caption) |caption| {
                    try self.writeJsonString(caption);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < diagrams.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeSnippetRefs(self: *Self, snippets: []const types.SnippetRef) !void {
        try self.writeChar('[');
        if (snippets.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (snippets, 0..) |snip, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("file", snip.file);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("anchor", snip.anchor);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("language");
                if (snip.language) |lang| {
                    try self.writeJsonString(lang);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < snippets.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeDateInfos(self: *Self, dates: []const types.DateInfo) !void {
        try self.writeChar('[');
        if (dates.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (dates, 0..) |date_info, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("date", date_info.date);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKey("description");
                if (date_info.description) |desc| {
                    try self.writeJsonString(desc);
                } else {
                    try self.writeString("null");
                }
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < dates.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeParamDocs(self: *Self, params: []const types.ParamDoc) !void {
        try self.writeChar('[');
        if (params.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (params, 0..) |param, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("name", param.name);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("description", param.description);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < params.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeRetvalDocs(self: *Self, retvals: []const types.RetvalDoc) !void {
        try self.writeChar('[');
        if (retvals.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (retvals, 0..) |retval, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("value", retval.value);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("description", retval.description);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < retvals.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn serializeExceptionDocs(self: *Self, exceptions: []const types.ExceptionDoc) !void {
        try self.writeChar('[');
        if (exceptions.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (exceptions, 0..) |exc, i| {
                try self.writeIndent();
                try self.writeChar('{');
                try self.writeNewline();
                self.indent_level += 1;

                try self.writeIndent();
                try self.writeKeyValue("exception_type", exc.exception_type);
                try self.writeChar(',');
                try self.writeNewline();

                try self.writeIndent();
                try self.writeKeyValue("description", exc.description);
                try self.writeNewline();

                self.indent_level -= 1;
                try self.writeIndent();
                try self.writeChar('}');

                if (i < exceptions.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    // =========================================================================
    // Low-level writing utilities
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

    fn writeKeyBool(self: *Self, key: []const u8, value: bool) !void {
        try self.writeKey(key);
        if (value) {
            try self.writeString("true");
        } else {
            try self.writeString("false");
        }
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
                0x08 => try self.buffer.appendSlice(self.allocator, "\\b"),
                0x0C => try self.buffer.appendSlice(self.allocator, "\\f"),
                else => {
                    if (c < 0x20) {
                        // Control character - encode as \u00XX
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

    fn writeStringArray(self: *Self, arr: []const []const u8) !void {
        try self.writeChar('[');
        if (arr.len > 0) {
            try self.writeNewline();
            self.indent_level += 1;

            for (arr, 0..) |s, i| {
                try self.writeIndent();
                try self.writeJsonString(s);
                if (i < arr.len - 1) {
                    try self.writeChar(',');
                }
                try self.writeNewline();
            }

            self.indent_level -= 1;
            try self.writeIndent();
        }
        try self.writeChar(']');
    }

    fn writeInt(self: *Self, value: i64) !void {
        var buf: [21]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, result);
    }

    fn writeUint(self: *Self, value: u32) !void {
        var buf: [11]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.buffer.appendSlice(self.allocator, result);
    }

    fn writeTimestamp(self: *Self) !void {
        // Write ISO 8601 timestamp in UTC
        const timestamp = std.time.timestamp();
        const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_seconds.getDaySeconds();

        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch unreachable;

        try self.writeJsonString(result);
    }
};

// =========================================================================
// Tests
// =========================================================================

test "generate json for empty module" {
    var gen = JsonGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{},
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    const output = try gen.generate(&modules);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"generator\": \"stig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\": \"test.h\"") != null);
}

test "generate json for function" {
    var gen = JsonGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{
                .{
                    .name = "add",
                    .return_type = "int",
                    .params = &[_]types.Parameter{
                        .{ .name = "a", .type_str = "int" },
                        .{ .name = "b", .type_str = "int" },
                    },
                    .location = .{ .file = "test.h", .line = 10, .column = 1 },
                },
            },
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    const output = try gen.generate(&modules);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\": \"add\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"return_type\": \"int\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"signature\": \"int add(int a, int b)\"") != null);
}

test "json string escaping" {
    var gen = JsonGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try gen.writeJsonString("hello \"world\"\ntest\\path");
    try std.testing.expectEqualStrings("\"hello \\\"world\\\"\\ntest\\\\path\"", gen.buffer.items);
}

test "compact mode" {
    var gen = JsonGenerator.initCompact(std.testing.allocator);
    defer gen.deinit();

    const modules = [_]types.Module{
        types.Module{
            .name = "test.h",
            .functions = &[_]types.Function{},
            .structs = &[_]types.Struct{},
            .enums = &[_]types.Enum{},
            .typedefs = &[_]types.Typedef{},
        },
    };

    const output = try gen.generate(&modules);
    // Compact mode should not have newlines (except possibly at the very end)
    var newline_count: usize = 0;
    for (output) |c| {
        if (c == '\n') newline_count += 1;
    }
    // Should have at most 1 newline (at the end)
    try std.testing.expect(newline_count <= 1);
}
