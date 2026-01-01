const std = @import("std");

/// Source location in a file
pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

/// Documentation for a parameter
pub const ParamDoc = struct {
    name: []const u8,
    description: []const u8,
};

/// Documentation for an exception/throw
pub const ExceptionDoc = struct {
    exception_type: []const u8,
    description: []const u8,
};

/// Parsed docstring with structured information
pub const DocString = struct {
    /// Raw docstring text
    raw: []const u8,
    /// Brief description (first line or @brief)
    brief: ?[]const u8 = null,
    /// Detailed description (text after brief, before tags)
    details: ?[]const u8 = null,
    /// Parameter documentation
    params: []const ParamDoc = &[_]ParamDoc{},
    /// Exception/throw documentation
    exceptions: []const ExceptionDoc = &[_]ExceptionDoc{},
    /// Return value documentation
    returns: ?[]const u8 = null,
    /// Example code blocks
    examples: []const []const u8 = &[_][]const u8{},
    /// Additional notes (@note)
    notes: []const []const u8 = &[_][]const u8{},
    /// Warning messages (@warning)
    warnings: []const []const u8 = &[_][]const u8{},
    /// Deprecation notice (@deprecated)
    deprecated: ?[]const u8 = null,
    /// See-also references (@see, @sa)
    see_also: []const []const u8 = &[_][]const u8{},
    /// Preconditions (@pre)
    preconditions: []const []const u8 = &[_][]const u8{},
    /// Postconditions (@post)
    postconditions: []const []const u8 = &[_][]const u8{},
    /// Since version (@since)
    since: ?[]const u8 = null,
    /// Author information (@author)
    author: ?[]const u8 = null,
    /// Version information (@version)
    version: ?[]const u8 = null,
};

/// Function parameter
pub const Parameter = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
};

/// Function declaration or definition
pub const Function = struct {
    name: []const u8,
    return_type: []const u8,
    params: []const Parameter,
    doc: ?DocString = null,
    location: SourceLocation,
    is_static: bool = false,
    is_inline: bool = false,
    is_constexpr: bool = false,
    is_consteval: bool = false,
    is_noexcept: bool = false,
    template_params: []const TemplateParam = &[_]TemplateParam{},
    requires_clause: ?[]const u8 = null,
};

/// Struct field
pub const StructField = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
};

/// Struct definition
pub const Struct = struct {
    name: []const u8,
    fields: []const StructField,
    doc: ?DocString = null,
    location: SourceLocation,
};

/// Enum value
pub const EnumValue = struct {
    name: []const u8,
    value: ?i64 = null,
    doc: ?[]const u8 = null,
};

/// Enum definition
pub const Enum = struct {
    name: []const u8,
    values: []const EnumValue,
    doc: ?DocString = null,
    location: SourceLocation,
};

/// Typedef
pub const Typedef = struct {
    name: []const u8,
    underlying: []const u8,
    doc: ?DocString = null,
    location: SourceLocation,
};

/// Macro definition
pub const Macro = struct {
    name: []const u8,
    params: ?[]const []const u8 = null, // null for object-like macros
    body: []const u8,
    doc: ?DocString = null,
    location: SourceLocation,
};

/// Access specifier for C++ class members
pub const AccessSpecifier = enum {
    public,
    protected,
    private,
};

/// Base class information for inheritance
pub const BaseClass = struct {
    /// Name of the base class (may include template parameters)
    name: []const u8,
    /// Access specifier for inheritance (public, protected, private)
    access: AccessSpecifier = .private,
    /// Whether this is virtual inheritance
    is_virtual: bool = false,
};

/// Kind of method (regular, constructor, destructor, etc.)
pub const MethodKind = enum {
    regular,
    constructor,
    copy_constructor,
    move_constructor,
    destructor,
    operator_overload,
    conversion_operator,
};

/// C++ class method
pub const Method = struct {
    name: []const u8,
    return_type: []const u8,
    params: []const Parameter,
    doc: ?DocString = null,
    access: AccessSpecifier = .private,
    kind: MethodKind = .regular,
    /// For operator_overload: the operator symbol (e.g., "+", "[]", "==")
    /// For conversion_operator: the target type (e.g., "bool", "int", "std::string")
    operator_symbol: ?[]const u8 = null,
    is_virtual: bool = false,
    is_static: bool = false,
    is_const: bool = false,
    is_override: bool = false,
    is_pure_virtual: bool = false,
    is_defaulted: bool = false,
    is_deleted: bool = false,
    is_constexpr: bool = false,
    is_consteval: bool = false,
    is_explicit: bool = false,
    is_noexcept: bool = false,
};

/// C++ class field with access specifier
pub const ClassField = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
    access: AccessSpecifier = .private,
};

/// C++ class definition
pub const Class = struct {
    name: []const u8,
    methods: []const Method = &[_]Method{},
    fields: []const ClassField = &[_]ClassField{},
    nested_classes: []const Class = &[_]Class{},
    nested_enums: []const Enum = &[_]Enum{},
    doc: ?DocString = null,
    location: SourceLocation = .{ .file = "", .line = 0, .column = 0 },
    namespace: ?[]const u8 = null,
    base_classes: []const BaseClass = &[_]BaseClass{},
    template_params: []const TemplateParam = &[_]TemplateParam{},
    requires_clause: ?[]const u8 = null,
};

/// C++ namespace
pub const Namespace = struct {
    name: []const u8,
    doc: ?DocString = null,
};

/// C++ type alias (using Name = Type)
pub const TypeAlias = struct {
    name: []const u8,
    underlying_type: []const u8,
    docstring: ?DocString = null,
    namespace: ?[]const u8 = null,
    template_params: []const TemplateParam = &[_]TemplateParam{},
};

/// Template parameter (typename T, class U, etc.)
pub const TemplateParam = struct {
    name: []const u8,
    kind: []const u8 = "typename", // "typename", "class", or a type for non-type params
};

/// C++20 concept definition
pub const Concept = struct {
    name: []const u8,
    constraint: []const u8, // The constraint expression
    template_params: []const TemplateParam = &[_]TemplateParam{},
    docstring: ?DocString = null,
    namespace: ?[]const u8 = null,
};

/// A parsed module (typically one header file)
pub const Module = struct {
    name: []const u8,
    functions: []const Function,
    structs: []const Struct,
    enums: []const Enum,
    typedefs: []const Typedef,
    macros: []const Macro = &[_]Macro{},
    // C++ specific
    classes: []const Class = &[_]Class{},
    namespaces: []const Namespace = &[_]Namespace{},
    type_aliases: []const TypeAlias = &[_]TypeAlias{},
    concepts: []const Concept = &[_]Concept{},
};
