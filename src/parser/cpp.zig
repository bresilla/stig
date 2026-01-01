const std = @import("std");
const ts = @import("tree-sitter");
const ts_cpp = @import("tree-sitter-cpp");
const types = @import("../model/types.zig");
const DocstringExtractor = @import("../docstring/extractor.zig").DocstringExtractor;

/// C++ language parser using tree-sitter
pub const CppParser = struct {
    parser: *ts.Parser,
    language: *ts.Language,
    allocator: std.mem.Allocator,
    source: []const u8 = "",
    docstring_extractor: DocstringExtractor,

    const Self = @This();

    /// Creates a new C++ parser
    pub fn init(allocator: std.mem.Allocator) !Self {
        const language: *ts.Language = @ptrCast(@constCast(ts_cpp.language()));
        const parser = ts.Parser.create();
        try parser.setLanguage(language);

        return Self{
            .parser = parser,
            .language = language,
            .allocator = allocator,
            .docstring_extractor = DocstringExtractor.init(allocator),
        };
    }

    /// Destroys the parser and frees resources
    pub fn deinit(self: *Self) void {
        self.parser.destroy();
        self.language.destroy();
    }

    /// Sets the base path for resolving include directives in docstrings
    pub fn setBasePath(self: *Self, path: []const u8) void {
        self.docstring_extractor.setBasePath(path);
    }

    /// Parses C++ source code and extracts documentation
    pub fn parse(self: *Self, source: []const u8, filename: []const u8) !types.Module {
        self.source = source;

        const tree = self.parser.parseString(source, null);
        if (tree == null) {
            return types.Module{
                .name = filename,
                .functions = &[_]types.Function{},
                .structs = &[_]types.Struct{},
                .enums = &[_]types.Enum{},
                .typedefs = &[_]types.Typedef{},
                .macros = &[_]types.Macro{},
            };
        }
        defer tree.?.destroy();

        var functions: std.ArrayList(types.Function) = .empty;
        var structs: std.ArrayList(types.Struct) = .empty;
        var enums: std.ArrayList(types.Enum) = .empty;
        var typedefs: std.ArrayList(types.Typedef) = .empty;
        var macros: std.ArrayList(types.Macro) = .empty;
        var classes: std.ArrayList(types.Class) = .empty;
        var namespaces: std.ArrayList(types.Namespace) = .empty;
        var concepts: std.ArrayList(types.Concept) = .empty;
        var type_aliases: std.ArrayList(types.TypeAlias) = .empty;
        var pages: std.ArrayList(types.Page) = .empty;
        var includes: std.ArrayList(types.IncludeInfo) = .empty;

        const root = tree.?.rootNode();
        try self.walkNode(root, &functions, &structs, &enums, &typedefs, &macros, &classes, &namespaces, &concepts, &type_aliases, &includes, filename, null);

        // Extract custom pages (@page, @mainpage) from standalone doc comments
        try self.extractPages(root, &pages);

        return types.Module{
            .name = filename,
            .functions = try functions.toOwnedSlice(self.allocator),
            .structs = try structs.toOwnedSlice(self.allocator),
            .enums = try enums.toOwnedSlice(self.allocator),
            .typedefs = try typedefs.toOwnedSlice(self.allocator),
            .macros = try macros.toOwnedSlice(self.allocator),
            .classes = try classes.toOwnedSlice(self.allocator),
            .namespaces = try namespaces.toOwnedSlice(self.allocator),
            .concepts = try concepts.toOwnedSlice(self.allocator),
            .type_aliases = try type_aliases.toOwnedSlice(self.allocator),
            .pages = try pages.toOwnedSlice(self.allocator),
            .includes = try includes.toOwnedSlice(self.allocator),
        };
    }

    /// Gets text for a node from source
    fn getNodeText(self: *Self, node: ts.Node) []const u8 {
        const start = node.startByte();
        const end = node.endByte();
        if (start < self.source.len and end <= self.source.len and start < end) {
            return self.source[start..end];
        }
        return "";
    }

    /// Walks the AST and extracts declarations
    fn walkNode(
        self: *Self,
        node: ts.Node,
        functions: *std.ArrayList(types.Function),
        structs: *std.ArrayList(types.Struct),
        enums: *std.ArrayList(types.Enum),
        typedefs: *std.ArrayList(types.Typedef),
        macros: *std.ArrayList(types.Macro),
        classes: *std.ArrayList(types.Class),
        namespaces: *std.ArrayList(types.Namespace),
        concepts: *std.ArrayList(types.Concept),
        type_aliases: *std.ArrayList(types.TypeAlias),
        includes: *std.ArrayList(types.IncludeInfo),
        filename: []const u8,
        current_namespace: ?[]const u8,
    ) !void {
        const node_kind = node.kind();

        if (std.mem.eql(u8, node_kind, "template_declaration")) {
            // Template declaration - extract docstring at this level and pass to child
            const template_doc = self.findPrecedingDocstring(node);
            try self.extractTemplateContents(node, functions, structs, enums, classes, concepts, type_aliases, filename, current_namespace, template_doc);
            return; // Don't recurse normally for template nodes
        } else if (std.mem.eql(u8, node_kind, "function_definition") or
            std.mem.eql(u8, node_kind, "declaration"))
        {
            if (try self.extractFunctionPrototype(node, filename, current_namespace)) |func| {
                try functions.append(self.allocator, func);
            }
        } else if (std.mem.eql(u8, node_kind, "class_specifier")) {
            if (try self.extractClass(node, filename, current_namespace)) |class| {
                try classes.append(self.allocator, class);
            }
            return; // Don't recurse into class body - nested classes are handled by extractClassBody
        } else if (std.mem.eql(u8, node_kind, "struct_specifier")) {
            if (try self.extractStruct(node, filename, current_namespace)) |s| {
                try structs.append(self.allocator, s);
            }
        } else if (std.mem.eql(u8, node_kind, "enum_specifier")) {
            if (try self.extractEnum(node, filename, current_namespace)) |e| {
                try enums.append(self.allocator, e);
            }
        } else if (std.mem.eql(u8, node_kind, "namespace_definition")) {
            // Extract namespace and process its body with updated namespace context
            const ns_info = self.extractNamespaceInfo(node, current_namespace);
            try namespaces.append(self.allocator, types.Namespace{
                .name = ns_info.full_name,
                .doc = self.findPrecedingDocstring(node),
            });
            // Process namespace body with new namespace context
            var i: u32 = 0;
            while (i < node.childCount()) : (i += 1) {
                if (node.child(i)) |child| {
                    if (std.mem.eql(u8, child.kind(), "declaration_list")) {
                        var j: u32 = 0;
                        while (j < child.childCount()) : (j += 1) {
                            if (child.child(j)) |body_child| {
                                try self.walkNode(body_child, functions, structs, enums, typedefs, macros, classes, namespaces, concepts, type_aliases, includes, filename, ns_info.full_name);
                            }
                        }
                    }
                }
            }
            return; // Don't recurse normally for namespace nodes
        } else if (std.mem.eql(u8, node_kind, "type_definition")) {
            if (try self.extractTypedef(node, filename)) |td| {
                try typedefs.append(self.allocator, td);
            }
        } else if (std.mem.eql(u8, node_kind, "preproc_def") or
            std.mem.eql(u8, node_kind, "preproc_function_def"))
        {
            if (try self.extractMacro(node, filename)) |m| {
                try macros.append(self.allocator, m);
            }
        } else if (std.mem.eql(u8, node_kind, "preproc_include")) {
            if (self.extractInclude(node)) |inc| {
                try includes.append(self.allocator, inc);
            }
        }

        // Recurse into children
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkNode(child, functions, structs, enums, typedefs, macros, classes, namespaces, concepts, type_aliases, includes, filename, current_namespace);
            }
        }
    }

    /// Extracts namespace info (name and full path)
    const NamespaceInfo = struct {
        name: []const u8,
        full_name: []const u8,
    };

    fn extractNamespaceInfo(self: *Self, node: ts.Node, parent_namespace: ?[]const u8) NamespaceInfo {
        var ns_name: []const u8 = "anonymous";

        // Find namespace name
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "namespace_identifier") or
                    std.mem.eql(u8, child_kind, "identifier"))
                {
                    ns_name = self.getNodeText(child);
                    break;
                }
            }
        }

        // Build full namespace path
        const full_ns = if (parent_namespace) |parent|
            std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ parent, ns_name }) catch ns_name
        else
            ns_name;

        return NamespaceInfo{
            .name = ns_name,
            .full_name = full_ns,
        };
    }

    /// Extracts contents from a template_declaration node
    /// The docstring is found at the template level and passed down
    fn extractTemplateContents(
        self: *Self,
        node: ts.Node,
        functions: *std.ArrayList(types.Function),
        structs: *std.ArrayList(types.Struct),
        enums: *std.ArrayList(types.Enum),
        classes: *std.ArrayList(types.Class),
        concepts: *std.ArrayList(types.Concept),
        type_aliases: *std.ArrayList(types.TypeAlias),
        filename: []const u8,
        namespace: ?[]const u8,
        template_doc: ?types.DocString,
    ) !void {
        // First, extract template parameters from this template_declaration
        const template_params = try self.extractTemplateParams(node);

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "function_definition") or
                    std.mem.eql(u8, child_kind, "declaration"))
                {
                    // Extract function and add template params
                    if (try self.extractFunctionPrototypeWithDoc(child, filename, namespace, template_doc)) |func| {
                        var template_func = func;
                        template_func.template_params = template_params;
                        try functions.append(self.allocator, template_func);
                    }
                } else if (std.mem.eql(u8, child_kind, "class_specifier")) {
                    // Extract class and add template params
                    if (try self.extractClassWithDoc(child, filename, namespace, template_doc)) |class| {
                        var template_class = class;
                        template_class.template_params = template_params;
                        try classes.append(self.allocator, template_class);
                    }
                } else if (std.mem.eql(u8, child_kind, "struct_specifier")) {
                    if (try self.extractStructWithDoc(child, filename, namespace, template_doc)) |s| {
                        try structs.append(self.allocator, s);
                    }
                } else if (std.mem.eql(u8, child_kind, "concept_definition")) {
                    // C++20 concept definition
                    if (try self.extractConcept(child, namespace, template_doc, template_params)) |concept| {
                        try concepts.append(self.allocator, concept);
                    }
                } else if (std.mem.eql(u8, child_kind, "alias_declaration")) {
                    // Template type alias: template<typename T> using Vec = std::vector<T>;
                    if (self.extractTypeAlias(child, namespace)) |alias| {
                        var template_alias = alias;
                        template_alias.template_params = template_params;
                        if (template_alias.docstring == null and template_doc != null) {
                            template_alias.docstring = template_doc;
                        }
                        try type_aliases.append(self.allocator, template_alias);
                    }
                } else if (std.mem.eql(u8, child_kind, "template_declaration")) {
                    // Nested template - recurse with the outer docstring if inner has none
                    const inner_doc = self.findPrecedingDocstring(child) orelse template_doc;
                    try self.extractTemplateContents(child, functions, structs, enums, classes, concepts, type_aliases, filename, namespace, inner_doc);
                }
            }
        }
    }

    /// Extracts template parameters from a template_declaration node
    /// Returns a slice of TemplateParam for parameters like "typename T", "class U", "size_t N"
    fn extractTemplateParams(self: *Self, node: ts.Node) ![]const types.TemplateParam {
        var params: std.ArrayList(types.TemplateParam) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "template_parameter_list")) {
                    // Iterate through template parameters
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |param_node| {
                            const param_kind = param_node.kind();

                            if (std.mem.eql(u8, param_kind, "type_parameter_declaration")) {
                                // typename T or class T
                                if (self.extractTypeParameter(param_node, false)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            } else if (std.mem.eql(u8, param_kind, "optional_type_parameter_declaration")) {
                                // typename T = DefaultType (with default value)
                                if (self.extractTypeParameterWithDefault(param_node)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            } else if (std.mem.eql(u8, param_kind, "variadic_type_parameter_declaration")) {
                                // typename... Args (variadic type parameter)
                                if (self.extractTypeParameter(param_node, true)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            } else if (std.mem.eql(u8, param_kind, "parameter_declaration") or
                                std.mem.eql(u8, param_kind, "optional_parameter_declaration"))
                            {
                                // Non-type template parameter like "size_t N" or "size_t N = 10"
                                if (self.extractNonTypeTemplateParam(param_node, false)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            } else if (std.mem.eql(u8, param_kind, "variadic_parameter_declaration")) {
                                // auto... Values (variadic non-type parameter)
                                if (self.extractNonTypeTemplateParam(param_node, true)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            } else if (std.mem.eql(u8, param_kind, "template_template_parameter_declaration")) {
                                // template<typename> class Container
                                if (self.extractTemplateTemplateParam(param_node)) |param| {
                                    try params.append(self.allocator, param);
                                }
                            }
                        }
                    }
                }
            }
        }

        return try params.toOwnedSlice(self.allocator);
    }

    /// Extracts a type template parameter (typename T or class T)
    fn extractTypeParameter(self: *Self, node: ts.Node, is_variadic: bool) ?types.TemplateParam {
        var name: ?[]const u8 = null;
        var kind: []const u8 = "typename";

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                const child_text = self.getNodeText(child);

                if (std.mem.eql(u8, child_kind, "typename") or std.mem.eql(u8, child_text, "typename")) {
                    kind = "typename";
                } else if (std.mem.eql(u8, child_kind, "class") or std.mem.eql(u8, child_text, "class")) {
                    kind = "class";
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "identifier"))
                {
                    name = child_text;
                }
            }
        }

        if (name == null) return null;

        return types.TemplateParam{
            .name = name.?,
            .kind = kind,
            .is_variadic = is_variadic,
        };
    }

    /// Extracts a type template parameter with default value (typename T = int)
    fn extractTypeParameterWithDefault(self: *Self, node: ts.Node) ?types.TemplateParam {
        var name: ?[]const u8 = null;
        var kind: []const u8 = "typename";
        var default_value: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                const child_text = self.getNodeText(child);

                if (std.mem.eql(u8, child_kind, "typename") or std.mem.eql(u8, child_text, "typename")) {
                    kind = "typename";
                } else if (std.mem.eql(u8, child_kind, "class") or std.mem.eql(u8, child_text, "class")) {
                    kind = "class";
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "identifier"))
                {
                    if (name == null) {
                        name = child_text;
                    } else {
                        // Second type_identifier is the default value
                        default_value = child_text;
                    }
                } else if (std.mem.eql(u8, child_kind, "type_descriptor") or
                    std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "template_type"))
                {
                    // Default value can be a complex type
                    default_value = child_text;
                }
            }
        }

        if (name == null) return null;

        return types.TemplateParam{
            .name = name.?,
            .kind = kind,
            .default_value = default_value,
        };
    }

    /// Extracts a non-type template parameter (e.g., size_t N, int Value)
    fn extractNonTypeTemplateParam(self: *Self, node: ts.Node, is_variadic: bool) ?types.TemplateParam {
        var name: ?[]const u8 = null;
        var param_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "sized_type_specifier") or
                    std.mem.eql(u8, child_kind, "placeholder_type_specifier"))
                {
                    if (param_type == null) {
                        param_type = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "variadic_declarator")) {
                    // For variadic non-type params like "int... Values"
                    // The name is inside the variadic_declarator
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |inner| {
                            if (std.mem.eql(u8, inner.kind(), "identifier")) {
                                name = self.getNodeText(inner);
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        return types.TemplateParam{
            .name = name.?,
            .kind = param_type orelse "auto",
            .is_variadic = is_variadic,
        };
    }

    /// Extracts a template template parameter (e.g., template<typename> class Container)
    fn extractTemplateTemplateParam(self: *Self, node: ts.Node) ?types.TemplateParam {
        var name: ?[]const u8 = null;

        // The structure is:
        // template_template_parameter_declaration
        //   - template (keyword)
        //   - template_parameter_list (<typename>)
        //   - type_parameter_declaration (class Container)
        //       - class (keyword)
        //       - type_identifier (Container)

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "type_parameter_declaration")) {
                    // Look inside type_parameter_declaration for the name
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |inner_child| {
                            const inner_kind = inner_child.kind();
                            if (std.mem.eql(u8, inner_kind, "type_identifier") or
                                std.mem.eql(u8, inner_kind, "identifier"))
                            {
                                name = self.getNodeText(inner_child);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "identifier"))
                {
                    // Direct child (fallback)
                    name = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        return types.TemplateParam{
            .name = name.?,
            .kind = "template",
        };
    }

    /// Extracts a C++20 concept definition
    fn extractConcept(self: *Self, node: ts.Node, namespace: ?[]const u8, doc_override: ?types.DocString, template_params: []const types.TemplateParam) !?types.Concept {
        var name: ?[]const u8 = null;
        var constraint: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier") or
                    std.mem.eql(u8, child_kind, "type_identifier"))
                {
                    if (name == null) {
                        name = self.getNodeText(child);
                    }
                }
            }
        }

        if (name == null) return null;

        // Extract constraint expression - everything after the '='
        // The constraint is typically the last significant child
        const full_text = self.getNodeText(node);
        if (std.mem.indexOf(u8, full_text, "=")) |eq_pos| {
            const after_eq = std.mem.trim(u8, full_text[eq_pos + 1 ..], " \t\n\r");
            // Remove trailing semicolon if present
            constraint = if (std.mem.endsWith(u8, after_eq, ";"))
                std.mem.trimRight(u8, after_eq[0 .. after_eq.len - 1], " \t\n\r")
            else
                after_eq;
        }

        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Concept{
            .name = full_name,
            .constraint = constraint orelse "",
            .template_params = template_params,
            .docstring = doc_override orelse self.findPrecedingDocstring(node),
            .namespace = namespace,
        };
    }

    /// Checks if a class/struct specifier has a field_declaration_list (body)
    /// Forward declarations like `class Foo;` do not have a body and should be skipped
    fn hasFieldDeclarationList(_: *Self, node: ts.Node) bool {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "field_declaration_list")) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Extracts a class definition
    fn extractClass(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) std.mem.Allocator.Error!?types.Class {
        // Skip forward declarations (no body)
        if (!self.hasFieldDeclarationList(node)) return null;

        var name: ?[]const u8 = null;
        var methods: std.ArrayList(types.Method) = .empty;
        var fields: std.ArrayList(types.ClassField) = .empty;
        var nested_classes: std.ArrayList(types.Class) = .empty;
        var nested_enums: std.ArrayList(types.Enum) = .empty;
        var base_classes: std.ArrayList(types.BaseClass) = .empty;
        var attributes: std.ArrayList(types.Attribute) = .empty;
        var friends: std.ArrayList(types.Friend) = .empty;
        var current_access: types.AccessSpecifier = .private;

        // First pass: find the class name, base classes, and attributes
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "base_class_clause")) {
                    // Extract base classes from the base_class_clause
                    try self.extractBaseClasses(child, &base_classes);
                } else if (std.mem.eql(u8, child_kind, "attribute_declaration")) {
                    // Parse C++ attributes like [[nodiscard]], [[deprecated("msg")]]
                    try self.parseAttributeDeclaration(child, &attributes);
                }
            }
        }

        // Second pass: extract body with class name context
        i = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "field_declaration_list")) {
                    try self.extractClassBody(child, &methods, &fields, &nested_classes, &nested_enums, &friends, &current_access, name, filename, namespace);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findPrecedingDocstring(node);
        const start = node.startPoint();

        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Class{
            .name = full_name,
            .doc = doc,
            .methods = try methods.toOwnedSlice(self.allocator),
            .fields = try fields.toOwnedSlice(self.allocator),
            .nested_classes = try nested_classes.toOwnedSlice(self.allocator),
            .nested_enums = try nested_enums.toOwnedSlice(self.allocator),
            .base_classes = try base_classes.toOwnedSlice(self.allocator),
            .namespace = namespace,
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
            .attributes = try attributes.toOwnedSlice(self.allocator),
            .friends = try friends.toOwnedSlice(self.allocator),
        };
    }

    /// Extracts base classes from a base_class_clause node
    /// Handles: class Derived : public Base, protected Other, private virtual Third { }
    fn extractBaseClasses(self: *Self, node: ts.Node, base_classes: *std.ArrayList(types.BaseClass)) !void {
        // The base_class_clause structure:
        // - ":" punctuation
        // - access_specifier (text: "public", "protected", "private")
        // - optional "virtual" keyword
        // - type_identifier/qualified_identifier/template_type
        // - "," for additional base classes

        var i: u32 = 0;
        var current_access: types.AccessSpecifier = .private;
        var current_virtual: bool = false;

        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                const child_text = self.getNodeText(child);

                // Skip punctuation
                if (std.mem.eql(u8, child_kind, ":") or std.mem.eql(u8, child_kind, ",")) {
                    // Reset for next base class after comma
                    if (std.mem.eql(u8, child_kind, ",")) {
                        current_access = .private;
                        current_virtual = false;
                    }
                    continue;
                }

                // Check for access specifier (node kind is "access_specifier", text is the actual specifier)
                if (std.mem.eql(u8, child_kind, "access_specifier")) {
                    if (std.mem.eql(u8, child_text, "public")) {
                        current_access = .public;
                    } else if (std.mem.eql(u8, child_text, "protected")) {
                        current_access = .protected;
                    } else if (std.mem.eql(u8, child_text, "private")) {
                        current_access = .private;
                    }
                } else if (std.mem.eql(u8, child_kind, "virtual")) {
                    current_virtual = true;
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "qualified_identifier") or
                    std.mem.eql(u8, child_kind, "template_type"))
                {
                    // Found a base class type
                    try base_classes.append(self.allocator, types.BaseClass{
                        .name = child_text,
                        .access = current_access,
                        .is_virtual = current_virtual,
                    });
                    // Reset for next base class
                    current_access = .private;
                    current_virtual = false;
                }
            }
        }
    }

    /// Extracts a class definition with an optional docstring override (for templates)
    fn extractClassWithDoc(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8, doc_override: ?types.DocString) !?types.Class {
        if (try self.extractClass(node, filename, namespace)) |class| {
            var result = class;
            if (result.doc == null and doc_override != null) {
                result.doc = doc_override;
            }
            return result;
        }
        return null;
    }

    /// Extracts class body
    fn extractClassBody(
        self: *Self,
        node: ts.Node,
        methods: *std.ArrayList(types.Method),
        fields: *std.ArrayList(types.ClassField),
        nested_classes: *std.ArrayList(types.Class),
        nested_enums: *std.ArrayList(types.Enum),
        friends: *std.ArrayList(types.Friend),
        current_access: *types.AccessSpecifier,
        class_name: ?[]const u8,
        filename: []const u8,
        parent_namespace: ?[]const u8,
    ) std.mem.Allocator.Error!void {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "access_specifier")) {
                    const spec_text = self.getNodeText(child);
                    if (std.mem.indexOf(u8, spec_text, "public") != null) {
                        current_access.* = .public;
                    } else if (std.mem.indexOf(u8, spec_text, "protected") != null) {
                        current_access.* = .protected;
                    } else if (std.mem.indexOf(u8, spec_text, "private") != null) {
                        current_access.* = .private;
                    }
                } else if (std.mem.eql(u8, child_kind, "friend_declaration")) {
                    // Friend class or function declaration
                    if (self.extractFriend(child)) |friend| {
                        try friends.append(self.allocator, friend);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_definition") or
                    std.mem.eql(u8, child_kind, "declaration"))
                {
                    if (try self.extractMethod(child, current_access.*, class_name)) |method| {
                        try methods.append(self.allocator, method);
                    }
                } else if (std.mem.eql(u8, child_kind, "field_declaration")) {
                    if (self.extractClassField(child, current_access.*)) |field| {
                        try fields.append(self.allocator, field);
                    }
                } else if (std.mem.eql(u8, child_kind, "class_specifier")) {
                    // Nested class definition
                    // Build namespace for nested class: parent_namespace::class_name or just class_name
                    const nested_namespace = if (parent_namespace) |ns|
                        if (class_name) |cn|
                            std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, cn }) catch null
                        else
                            ns
                    else
                        class_name;

                    if (try self.extractClass(child, filename, nested_namespace)) |nested_class| {
                        try nested_classes.append(self.allocator, nested_class);
                    }
                } else if (std.mem.eql(u8, child_kind, "enum_specifier")) {
                    // Nested enum definition
                    // Build namespace for nested enum: parent_namespace::class_name or just class_name
                    const nested_namespace = if (parent_namespace) |ns|
                        if (class_name) |cn|
                            std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, cn }) catch null
                        else
                            ns
                    else
                        class_name;

                    if (try self.extractEnum(child, filename, nested_namespace)) |nested_enum| {
                        try nested_enums.append(self.allocator, nested_enum);
                    }
                }
            }
        }
    }

    /// Extracts a friend declaration (friend class or friend function)
    fn extractFriend(self: *Self, node: ts.Node) ?types.Friend {
        const full_text = self.getNodeText(node);

        // Check if it's a friend class or friend function
        var is_class = false;
        var friend_name: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "class") or std.mem.eql(u8, child_kind, "struct")) {
                    is_class = true;
                } else if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    // Friend class name (only if we've seen "class" or "struct")
                    if (is_class and friend_name == null) {
                        friend_name = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    // Friend function - extract the function name
                    friend_name = self.extractFunctionNameFromDeclarator(child);
                } else if (std.mem.eql(u8, child_kind, "declaration")) {
                    // Friend function might be wrapped in a declaration node
                    friend_name = self.extractFunctionNameFromDeclaration(child);
                }
            }
        }

        if (friend_name == null) return null;

        // Extract signature for friend functions (everything after "friend ")
        var signature: ?[]const u8 = null;
        if (!is_class) {
            if (std.mem.indexOf(u8, full_text, "friend ")) |friend_pos| {
                var sig = full_text[friend_pos + 7 ..];
                // Remove trailing semicolon
                if (std.mem.endsWith(u8, sig, ";")) {
                    sig = sig[0 .. sig.len - 1];
                }
                sig = std.mem.trim(u8, sig, " \t\n\r");
                if (sig.len > 0) {
                    signature = sig;
                }
            }
        }

        return types.Friend{
            .kind = if (is_class) .class else .function,
            .name = friend_name.?,
            .signature = signature,
        };
    }

    /// Extracts function name from a function_declarator node
    fn extractFunctionNameFromDeclarator(self: *Self, node: ts.Node) ?[]const u8 {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier") or
                    std.mem.eql(u8, child_kind, "operator_name") or
                    std.mem.eql(u8, child_kind, "qualified_identifier"))
                {
                    return self.getNodeText(child);
                }
            }
        }
        return null;
    }

    /// Extracts function name from a declaration node (for friend functions)
    fn extractFunctionNameFromDeclaration(self: *Self, node: ts.Node) ?[]const u8 {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    return self.extractFunctionNameFromDeclarator(child);
                }
            }
        }
        return null;
    }

    /// Extracts a method
    fn extractMethod(self: *Self, node: ts.Node, access: types.AccessSpecifier, class_name: ?[]const u8) !?types.Method {
        var name: ?[]const u8 = null;
        var return_type: ?[]const u8 = null;
        var params: std.ArrayList(types.Parameter) = .empty;
        var attributes: std.ArrayList(types.Attribute) = .empty;
        var is_virtual = false;
        var is_static = false;
        var is_const = false;
        var is_defaulted = false;
        var is_deleted = false;
        var is_constexpr = false;
        var is_consteval = false;
        var is_explicit = false;
        var is_noexcept = false;
        var is_conversion_operator = false;
        var is_operator_overload = false;
        var operator_symbol: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "virtual")) {
                    is_virtual = true;
                } else if (std.mem.eql(u8, child_kind, "explicit_function_specifier")) {
                    is_explicit = true;
                } else if (std.mem.eql(u8, child_kind, "attribute_declaration")) {
                    // Parse C++ attributes like [[nodiscard]], [[deprecated("msg")]]
                    try self.parseAttributeDeclaration(child, &attributes);
                } else if (std.mem.eql(u8, child_kind, "storage_class_specifier")) {
                    const spec_text = self.getNodeText(child);
                    if (std.mem.eql(u8, spec_text, "static")) {
                        is_static = true;
                    } else if (std.mem.eql(u8, spec_text, "constexpr")) {
                        is_constexpr = true;
                    } else if (std.mem.eql(u8, spec_text, "consteval")) {
                        is_consteval = true;
                    }
                } else if (std.mem.eql(u8, child_kind, "default")) {
                    is_defaulted = true;
                } else if (std.mem.eql(u8, child_kind, "delete")) {
                    is_deleted = true;
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "placeholder_type_specifier"))
                {
                    // Handle regular types and 'auto' (placeholder_type_specifier for C++20)
                    if (return_type == null) {
                        return_type = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |fd_child| {
                            const fd_kind = fd_child.kind();
                            if (std.mem.eql(u8, fd_kind, "identifier") or
                                std.mem.eql(u8, fd_kind, "field_identifier"))
                            {
                                name = self.getNodeText(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "operator_name")) {
                                // Regular operator overload: operator+, operator==, operator<=>, etc.
                                is_operator_overload = true;
                                const op_text = self.getNodeText(fd_child);
                                name = op_text;
                                // Extract the operator symbol from "operator X"
                                if (std.mem.indexOf(u8, op_text, "operator")) |_| {
                                    const after_op = std.mem.trimLeft(u8, op_text[8..], " ");
                                    if (after_op.len > 0) {
                                        operator_symbol = after_op;
                                    }
                                }
                            } else if (std.mem.eql(u8, fd_kind, "operator_cast")) {
                                // Conversion operator: operator Type()
                                is_conversion_operator = true;
                                const conv_result = self.extractConversionOperator(fd_child);
                                name = conv_result.name;
                                operator_symbol = conv_result.target_type;
                            } else if (std.mem.eql(u8, fd_kind, "parameter_list")) {
                                params = try self.extractParameters(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "type_qualifier")) {
                                if (std.mem.eql(u8, self.getNodeText(fd_child), "const")) {
                                    is_const = true;
                                }
                            } else if (std.mem.eql(u8, fd_kind, "noexcept")) {
                                // noexcept specifier (handles both noexcept and noexcept(expr))
                                is_noexcept = true;
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const params_slice = try params.toOwnedSlice(self.allocator);

        // Determine method kind - conversion operators and operator overloads take precedence
        const kind: types.MethodKind = if (is_conversion_operator)
            .conversion_operator
        else if (is_operator_overload)
            .operator_overload
        else
            self.categorizeMethodKind(name.?, return_type, params_slice, class_name);

        return types.Method{
            .name = name.?,
            .return_type = return_type orelse "void",
            .params = params_slice,
            .doc = self.findPrecedingDocstring(node),
            .access = access,
            .kind = kind,
            .operator_symbol = operator_symbol,
            .is_virtual = is_virtual,
            .is_static = is_static,
            .is_const = is_const,
            .is_defaulted = is_defaulted,
            .is_deleted = is_deleted,
            .is_constexpr = is_constexpr,
            .is_consteval = is_consteval,
            .is_explicit = is_explicit,
            .is_noexcept = is_noexcept,
            .attributes = try attributes.toOwnedSlice(self.allocator),
        };
    }

    /// Extracts conversion operator information (e.g., operator bool(), operator int())
    /// Returns the method name and the target type for the conversion
    const ConversionOperatorInfo = struct {
        name: []const u8,
        target_type: []const u8,
    };

    fn extractConversionOperator(self: *Self, node: ts.Node) ConversionOperatorInfo {
        // The operator_cast node contains the full "operator Type" text
        const full_text = self.getNodeText(node);

        // Look for child nodes to extract the type
        var target_type: []const u8 = "";
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                // The type can be primitive_type, type_identifier, qualified_identifier, or template_type
                if (std.mem.eql(u8, child_kind, "primitive_type") or
                    std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "qualified_identifier") or
                    std.mem.eql(u8, child_kind, "template_type"))
                {
                    target_type = self.getNodeText(child);
                    break;
                }
            }
        }

        // If we couldn't find the type from children, extract from full text
        if (target_type.len == 0) {
            if (std.mem.indexOf(u8, full_text, "operator ")) |op_start| {
                target_type = std.mem.trim(u8, full_text[op_start + 9 ..], " \t");
            }
        }

        return ConversionOperatorInfo{
            .name = full_text, // Keep full "operator bool" as the name
            .target_type = target_type,
        };
    }

    /// Categorizes method kind (regular, constructor, copy_constructor, move_constructor, destructor)
    fn categorizeMethodKind(
        _: *Self,
        method_name: []const u8,
        return_type: ?[]const u8,
        params: []const types.Parameter,
        class_name: ?[]const u8,
    ) types.MethodKind {
        const cn = class_name orelse return .regular;

        // Check for destructor: ~ClassName
        if (method_name.len > 1 and method_name[0] == '~') {
            if (std.mem.eql(u8, method_name[1..], cn)) {
                return .destructor;
            }
        }

        // Check for constructor: method name matches class name and no return type
        // (or return type is the class name itself in some cases)
        if (!std.mem.eql(u8, method_name, cn)) {
            return .regular;
        }

        // Constructor detected - return type should be null/void for constructors
        // (tree-sitter may or may not capture return type for constructors)
        if (return_type != null and !std.mem.eql(u8, return_type.?, cn)) {
            // Has a return type that's not the class name - might be a method with same name
            // (unusual but possible in some parsing scenarios)
            return .regular;
        }

        // Now categorize the constructor type based on parameters
        if (params.len == 0) {
            // Default constructor: no parameters
            return .constructor;
        }

        if (params.len == 1) {
            const param_type = params[0].type_str;

            // Check for copy constructor: const ClassName& or ClassName const&
            if (isCopyConstructorType(param_type, cn)) {
                return .copy_constructor;
            }

            // Check for move constructor: ClassName&&
            if (isMoveConstructorType(param_type, cn)) {
                return .move_constructor;
            }

            // Single parameter of other type - converting constructor (keep as .constructor)
            return .constructor;
        }

        // Multiple parameters - regular constructor
        return .constructor;
    }

    /// Checks if a parameter type represents a copy constructor parameter (const ClassName&)
    fn isCopyConstructorType(param_type: []const u8, class_name: []const u8) bool {
        // Trim whitespace
        const trimmed = std.mem.trim(u8, param_type, " \t");

        // Pattern: "const ClassName&" or "ClassName const&" or "const ClassName &"
        // Also handle with extra spaces

        // Check for "const" at start
        if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "const\t")) {
            // After "const ", should have "ClassName" followed by "&"
            const after_const = std.mem.trimLeft(u8, trimmed[5..], " \t");
            if (std.mem.startsWith(u8, after_const, class_name)) {
                const after_name = std.mem.trimLeft(u8, after_const[class_name.len..], " \t");
                if (std.mem.startsWith(u8, after_name, "&") and !std.mem.startsWith(u8, after_name, "&&")) {
                    return true;
                }
            }
        }

        // Check for "ClassName const&" pattern
        if (std.mem.startsWith(u8, trimmed, class_name)) {
            const after_name = std.mem.trimLeft(u8, trimmed[class_name.len..], " \t");
            if (std.mem.startsWith(u8, after_name, "const")) {
                const after_const = std.mem.trimLeft(u8, after_name[5..], " \t");
                if (std.mem.startsWith(u8, after_const, "&") and !std.mem.startsWith(u8, after_const, "&&")) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Checks if a parameter type represents a move constructor parameter (ClassName&&)
    fn isMoveConstructorType(param_type: []const u8, class_name: []const u8) bool {
        // Trim whitespace
        const trimmed = std.mem.trim(u8, param_type, " \t");

        // Pattern: "ClassName&&" or "ClassName &&"
        if (std.mem.startsWith(u8, trimmed, class_name)) {
            const after_name = std.mem.trimLeft(u8, trimmed[class_name.len..], " \t");
            if (std.mem.startsWith(u8, after_name, "&&")) {
                return true;
            }
        }

        return false;
    }

    /// Extracts a class field
    fn extractClassField(self: *Self, node: ts.Node, access: types.AccessSpecifier) ?types.ClassField {
        var name: ?[]const u8 = null;
        var field_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    field_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.ClassField{
            .name = name.?,
            .type_str = field_type orelse "unknown",
            .doc = if (doc) |d| d.brief else null,
            .access = access,
        };
    }

    /// Extracts function prototype
    fn extractFunctionPrototype(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Function {
        var name: ?[]const u8 = null;
        var return_type: ?[]const u8 = null;
        var params: std.ArrayList(types.Parameter) = .empty;
        var is_constexpr = false;
        var is_consteval = false;
        var is_noexcept = false;
        var attributes: std.ArrayList(types.Attribute) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "storage_class_specifier")) {
                    const spec_text = self.getNodeText(child);
                    if (std.mem.eql(u8, spec_text, "constexpr")) {
                        is_constexpr = true;
                    } else if (std.mem.eql(u8, spec_text, "consteval")) {
                        is_consteval = true;
                    }
                } else if (std.mem.eql(u8, child_kind, "attribute_declaration")) {
                    // Parse C++ attributes like [[nodiscard]], [[deprecated("msg")]]
                    try self.parseAttributeDeclaration(child, &attributes);
                } else if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    if (return_type == null) {
                        return_type = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "function_declarator")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |fd_child| {
                            const fd_kind = fd_child.kind();
                            if (std.mem.eql(u8, fd_kind, "identifier")) {
                                name = self.getNodeText(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "parameter_list")) {
                                params = try self.extractParameters(fd_child);
                            } else if (std.mem.eql(u8, fd_kind, "noexcept")) {
                                // noexcept specifier (handles both noexcept and noexcept(expr))
                                is_noexcept = true;
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Function{
            .name = full_name,
            .return_type = return_type orelse "void",
            .params = try params.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
            .is_constexpr = is_constexpr,
            .is_consteval = is_consteval,
            .is_noexcept = is_noexcept,
            .attributes = try attributes.toOwnedSlice(self.allocator),
        };
    }

    /// Extracts function prototype with an optional docstring override (for templates)
    fn extractFunctionPrototypeWithDoc(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8, doc_override: ?types.DocString) !?types.Function {
        if (try self.extractFunctionPrototype(node, filename, namespace)) |func| {
            // Use override doc if provided and function has no doc of its own
            var result = func;
            if (result.doc == null and doc_override != null) {
                result.doc = doc_override;
            }
            return result;
        }
        return null;
    }

    /// Extracts parameters
    fn extractParameters(self: *Self, node: ts.Node) !std.ArrayList(types.Parameter) {
        var params: std.ArrayList(types.Parameter) = .empty;
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "parameter_declaration")) {
                    if (self.extractParameter(child)) |param| {
                        try params.append(self.allocator, param);
                    }
                }
            }
        }
        return params;
    }

    /// Extracts a single parameter
    fn extractParameter(self: *Self, node: ts.Node) ?types.Parameter {
        // Get the full text of the parameter declaration
        const full_text = self.getNodeText(node);

        // Try to find the parameter name - it's usually the last identifier
        // For "const Point2<T>& a" we want name="a", type="const Point2<T>&"
        var name: ?[]const u8 = null;
        var last_identifier_end: usize = 0;

        // Walk children to find identifiers (skip type_identifier which is part of type)
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                // Look for the parameter name in various declarator types
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                    last_identifier_end = child.endByte();
                } else if (std.mem.eql(u8, child_kind, "reference_declarator") or
                    std.mem.eql(u8, child_kind, "pointer_declarator"))
                {
                    // The name is inside the declarator
                    if (self.findIdentifierInNode(child)) |id| {
                        name = id;
                        last_identifier_end = child.endByte();
                    }
                }
            }
        }

        // Extract type by removing the parameter name from the end
        var param_type: []const u8 = full_text;
        if (name) |n| {
            // Find where the name starts in the full text and take everything before it
            if (std.mem.lastIndexOf(u8, full_text, n)) |name_start| {
                param_type = std.mem.trimRight(u8, full_text[0..name_start], " \t&*");
            }
        }

        return types.Parameter{
            .name = name orelse "unnamed",
            .type_str = if (param_type.len > 0) param_type else "unknown",
            .doc = null,
        };
    }

    /// Recursively finds an identifier node within a node
    fn findIdentifierInNode(self: *Self, node: ts.Node) ?[]const u8 {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "identifier")) {
                    return self.getNodeText(child);
                }
                // Recurse into child nodes
                if (self.findIdentifierInNode(child)) |id| {
                    return id;
                }
            }
        }
        return null;
    }

    /// Extracts struct
    fn extractStruct(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Struct {
        // Skip forward declarations (no body)
        if (!self.hasFieldDeclarationList(node)) return null;

        var name: ?[]const u8 = null;
        var fields: std.ArrayList(types.StructField) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_declaration_list")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |body_child| {
                            if (std.mem.eql(u8, body_child.kind(), "field_declaration")) {
                                if (self.extractStructField(body_child)) |field| {
                                    try fields.append(self.allocator, field);
                                }
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Struct{
            .name = full_name,
            .fields = try fields.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts a struct with an optional docstring override (for templates)
    fn extractStructWithDoc(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8, doc_override: ?types.DocString) !?types.Struct {
        if (try self.extractStruct(node, filename, namespace)) |s| {
            var result = s;
            if (result.doc == null and doc_override != null) {
                result.doc = doc_override;
            }
            return result;
        }
        return null;
    }

    /// Extracts a struct field
    fn extractStructField(self: *Self, node: ts.Node) ?types.StructField {
        var name: ?[]const u8 = null;
        var field_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier") or
                    std.mem.eql(u8, child_kind, "primitive_type"))
                {
                    field_type = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "field_identifier")) {
                    name = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.StructField{
            .name = name.?,
            .type_str = field_type orelse "unknown",
            .doc = if (doc) |d| d.brief else null,
        };
    }

    /// Extracts enum
    fn extractEnum(self: *Self, node: ts.Node, filename: []const u8, namespace: ?[]const u8) !?types.Enum {
        var name: ?[]const u8 = null;
        var values: std.ArrayList(types.EnumValue) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "enumerator_list")) {
                    var j: u32 = 0;
                    while (j < child.childCount()) : (j += 1) {
                        if (child.child(j)) |list_child| {
                            if (std.mem.eql(u8, list_child.kind(), "enumerator")) {
                                if (self.extractEnumValue(list_child)) |val| {
                                    try values.append(self.allocator, val);
                                }
                            }
                        }
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        const full_name = if (namespace) |ns|
            try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ ns, name.? })
        else
            name.?;

        return types.Enum{
            .name = full_name,
            .values = try values.toOwnedSlice(self.allocator),
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts enum value
    fn extractEnumValue(self: *Self, node: ts.Node) ?types.EnumValue {
        var name: ?[]const u8 = null;
        var value: ?i64 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "number_literal")) {
                    value = std.fmt.parseInt(i64, self.getNodeText(child), 0) catch null;
                }
            }
        }

        if (name == null) return null;

        const doc = self.findTrailingDocstring(node);
        return types.EnumValue{
            .name = name.?,
            .value = value,
            .doc = if (doc) |d| d.brief else null,
        };
    }

    /// Extracts typedef
    fn extractTypedef(self: *Self, node: ts.Node, filename: []const u8) !?types.Typedef {
        var name: ?[]const u8 = null;
        var underlying: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "type_identifier")) {
                    if (underlying == null) {
                        underlying = self.getNodeText(child);
                    } else {
                        name = self.getNodeText(child);
                    }
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        return types.Typedef{
            .name = name.?,
            .underlying = underlying orelse "unknown",
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts macro
    fn extractMacro(self: *Self, node: ts.Node, filename: []const u8) !?types.Macro {
        var name: ?[]const u8 = null;
        var body: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "identifier")) {
                    name = self.getNodeText(child);
                } else if (std.mem.eql(u8, child_kind, "preproc_arg")) {
                    body = std.mem.trim(u8, self.getNodeText(child), " \t");
                }
            }
        }

        if (name == null) return null;

        const start = node.startPoint();
        return types.Macro{
            .name = name.?,
            .params = null,
            .body = body orelse "",
            .doc = self.findPrecedingDocstring(node),
            .location = types.SourceLocation{
                .file = filename,
                .line = start.row + 1,
                .column = start.column + 1,
            },
        };
    }

    /// Extracts include directive information
    /// Handles both #include <...> and #include "..."
    fn extractInclude(self: *Self, node: ts.Node) ?types.IncludeInfo {
        var path: ?[]const u8 = null;
        var is_system = false;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "system_lib_string")) {
                    // #include <...>
                    const text = self.getNodeText(child);
                    // Remove < and >
                    if (text.len >= 2) {
                        path = text[1 .. text.len - 1];
                        is_system = true;
                    }
                } else if (std.mem.eql(u8, child_kind, "string_literal")) {
                    // #include "..."
                    const text = self.getNodeText(child);
                    // Remove quotes
                    if (text.len >= 2) {
                        path = text[1 .. text.len - 1];
                        is_system = false;
                    }
                }
            }
        }

        if (path == null) return null;

        const start = node.startPoint();
        return types.IncludeInfo{
            .path = path.?,
            .is_system = is_system,
            .line = start.row + 1,
        };
    }

    /// Extracts C++ attributes from attribute_declaration nodes
    /// Handles [[nodiscard]], [[deprecated("reason")]], [[maybe_unused]], etc.
    fn extractAttributes(self: *Self, node: ts.Node) ![]const types.Attribute {
        var attrs: std.ArrayList(types.Attribute) = .empty;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "attribute_declaration")) {
                    // Parse the attribute_declaration node
                    try self.parseAttributeDeclaration(child, &attrs);
                }
            }
        }

        return try attrs.toOwnedSlice(self.allocator);
    }

    /// Parses a single attribute_declaration node (e.g., [[nodiscard]] or [[deprecated("msg")]])
    fn parseAttributeDeclaration(self: *Self, node: ts.Node, attrs: *std.ArrayList(types.Attribute)) !void {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "attribute")) {
                    // Parse individual attribute
                    if (self.parseAttribute(child)) |attr| {
                        try attrs.append(self.allocator, attr);
                    }
                }
            }
        }
    }

    /// Parses a single attribute node (e.g., nodiscard or deprecated("msg"))
    fn parseAttribute(self: *Self, node: ts.Node) ?types.Attribute {
        var name: ?[]const u8 = null;
        var argument: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "identifier")) {
                    if (name == null) {
                        name = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "argument_list")) {
                    // Extract the argument from the argument list
                    argument = self.extractAttributeArgument(child);
                }
            }
        }

        // If no children found, the attribute text might be directly in the node
        if (name == null) {
            const text = self.getNodeText(node);
            if (text.len > 0) {
                name = text;
            }
        }

        if (name == null) return null;

        return types.Attribute{
            .name = name.?,
            .argument = argument,
        };
    }

    /// Extracts the argument from an attribute argument list
    fn extractAttributeArgument(self: *Self, node: ts.Node) ?[]const u8 {
        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "string_literal")) {
                    // Get the string content without quotes
                    const text = self.getNodeText(child);
                    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
                        return text[1 .. text.len - 1];
                    }
                    return text;
                }
            }
        }
        return null;
    }

    /// Extracts a type alias (using Name = Type)
    fn extractTypeAlias(self: *Self, node: ts.Node, namespace: ?[]const u8) ?types.TypeAlias {
        var name: ?[]const u8 = null;
        var underlying_type: ?[]const u8 = null;

        var i: u32 = 0;
        while (i < node.childCount()) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();
                if (std.mem.eql(u8, child_kind, "type_identifier")) {
                    // First type_identifier is the alias name
                    if (name == null) {
                        name = self.getNodeText(child);
                    }
                } else if (std.mem.eql(u8, child_kind, "type_descriptor")) {
                    // type_descriptor contains the underlying type
                    underlying_type = self.getNodeText(child);
                }
            }
        }

        if (name == null) return null;

        return types.TypeAlias{
            .name = name.?,
            .underlying_type = underlying_type orelse "unknown",
            .docstring = self.findPrecedingDocstring(node),
            .namespace = namespace,
        };
    }

    /// Finds preceding docstring
    /// Handles both /** */ block comments and consecutive /// line comments
    fn findPrecedingDocstring(self: *Self, node: ts.Node) ?types.DocString {
        var prev = node.prevSibling();

        // Collect consecutive /// comments (they appear in reverse order)
        var triple_slash_comments: std.ArrayList([]const u8) = .empty;
        defer triple_slash_comments.deinit(self.allocator);

        while (prev != null) {
            const prev_kind = prev.?.kind();
            if (std.mem.eql(u8, prev_kind, "comment")) {
                const text = self.getNodeText(prev.?);

                // Block comment - return immediately
                if (std.mem.startsWith(u8, text, "/**")) {
                    return self.parseDocComment(text);
                }

                // Triple-slash comment - collect it
                if (std.mem.startsWith(u8, text, "///")) {
                    triple_slash_comments.append(self.allocator, text) catch break;
                    prev = prev.?.prevSibling();
                    continue;
                }

                // Regular comment (// or /*) - stop collecting
                break;
            } else if (!std.mem.eql(u8, prev_kind, "preproc_ifdef") and
                !std.mem.eql(u8, prev_kind, "preproc_ifndef"))
            {
                break;
            }
            prev = prev.?.prevSibling();
        }

        // If we collected /// comments, merge them (they're in reverse order)
        if (triple_slash_comments.items.len > 0) {
            var merged: std.ArrayList(u8) = .empty;
            defer merged.deinit(self.allocator);

            // Reverse iterate to get correct order
            var i = triple_slash_comments.items.len;
            while (i > 0) {
                i -= 1;
                const comment = triple_slash_comments.items[i];
                // Strip /// prefix
                var content = comment;
                if (std.mem.startsWith(u8, content, "/// ")) {
                    content = content[4..];
                } else if (std.mem.startsWith(u8, content, "///")) {
                    content = content[3..];
                }
                merged.appendSlice(self.allocator, content) catch break;
                if (i > 0) {
                    merged.append(self.allocator, '\n') catch break;
                }
            }

            if (merged.items.len > 0) {
                return self.docstring_extractor.parse(merged.items) catch null;
            }
        }

        return null;
    }

    /// Finds trailing docstring
    fn findTrailingDocstring(self: *Self, node: ts.Node) ?types.DocString {
        const next = node.nextSibling();
        if (next != null and std.mem.eql(u8, next.?.kind(), "comment")) {
            const text = self.getNodeText(next.?);
            if (std.mem.startsWith(u8, text, "/**<") or std.mem.startsWith(u8, text, "///<")) {
                return self.parseDocComment(text);
            }
        }
        return null;
    }

    /// Parses doc comment
    fn parseDocComment(self: *Self, text: []const u8) ?types.DocString {
        var result = text;
        if (std.mem.startsWith(u8, result, "/**<")) result = result[4..] else if (std.mem.startsWith(u8, result, "/**")) result = result[3..] else if (std.mem.startsWith(u8, result, "///<")) result = result[4..] else if (std.mem.startsWith(u8, result, "///")) result = result[3..];
        if (std.mem.endsWith(u8, result, "*/")) result = result[0 .. result.len - 2];
        result = std.mem.trim(u8, result, " \t\n\r");
        return self.docstring_extractor.parse(result) catch null;
    }

    /// Extracts custom pages from standalone doc comments containing @page or @mainpage
    fn extractPages(self: *Self, root: ts.Node, pages: *std.ArrayList(types.Page)) !void {
        var i: u32 = 0;
        while (i < root.childCount()) : (i += 1) {
            if (root.child(i)) |child| {
                const child_kind = child.kind();

                if (std.mem.eql(u8, child_kind, "comment")) {
                    const text = self.getNodeText(child);

                    // Only process doc comments (/** or ///)
                    if (!std.mem.startsWith(u8, text, "/**") and !std.mem.startsWith(u8, text, "///")) {
                        continue;
                    }

                    // Strip comment delimiters
                    var stripped = text;
                    if (std.mem.startsWith(u8, stripped, "/**")) {
                        stripped = stripped[3..];
                    } else if (std.mem.startsWith(u8, stripped, "///")) {
                        stripped = stripped[3..];
                    }
                    if (std.mem.endsWith(u8, stripped, "*/")) {
                        stripped = stripped[0 .. stripped.len - 2];
                    }
                    stripped = std.mem.trim(u8, stripped, " \t\n\r");

                    // Check if this comment contains @page or @mainpage
                    if (self.docstring_extractor.containsPageCommand(stripped)) {
                        // Check if this comment is NOT attached to a declaration
                        // (standalone page comments should not be followed by a declaration)
                        const next = child.nextSibling();
                        const is_standalone = next == null or
                            std.mem.eql(u8, next.?.kind(), "comment") or
                            std.mem.eql(u8, next.?.kind(), "preproc_ifdef") or
                            std.mem.eql(u8, next.?.kind(), "preproc_ifndef") or
                            std.mem.eql(u8, next.?.kind(), "preproc_endif");

                        if (is_standalone) {
                            if (try self.docstring_extractor.parsePage(stripped)) |page| {
                                try pages.append(self.allocator, page);
                            }
                        }
                    }
                }
            }
        }
    }
};

test "cpp parser init" {
    var parser = try CppParser.init(std.testing.allocator);
    defer parser.deinit();
}
