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

/// A parsed module (typically one header file)
pub const Module = struct {
    name: []const u8,
    functions: []const Function,
    structs: []const Struct,
    enums: []const Enum,
    typedefs: []const Typedef,
    macros: []const Macro = &[_]Macro{},
};
