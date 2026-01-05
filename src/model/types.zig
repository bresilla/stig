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

/// Documentation for a return value (@retval)
pub const RetvalDoc = struct {
    value: []const u8,
    description: []const u8,
};

/// Exclusion mode for @exclude command
pub const ExcludeMode = enum {
    /// Normal - include in documentation
    none,
    /// Exclude entity entirely from documentation
    full,
    /// Hide return type in synopsis (function appears, return type hidden)
    return_type,
    /// Hide alias target or enum underlying type
    target,
};

/// Group information for @group command
pub const GroupInfo = struct {
    /// Group identifier (e.g., "getters")
    name: []const u8,
    /// Optional group heading (e.g., "Getter Functions")
    heading: ?[]const u8 = null,
};

/// Test case reference from @test tag
pub const TestRef = struct {
    /// Test case name (e.g., "test_factorial_basic")
    name: []const u8,
    /// Optional test file path (e.g., "test/test_math.cpp")
    file: ?[]const u8 = null,
    /// Optional line number in test file
    line: ?u32 = null,
};

/// Kind of reference target for @ref tag
pub const RefKind = enum {
    /// Reference to a symbol (function, class, etc.)
    symbol,
    /// Reference to a @page
    page,
    /// Reference to a @section
    section,
    /// Reference to an @anchor
    anchor,
};

/// Cross-reference link from @ref tag
pub const RefLink = struct {
    /// Target identifier (e.g., "MyClass::method()", "page_examples")
    target: []const u8,
    /// Optional custom display text (e.g., "the overview")
    display_text: ?[]const u8 = null,
    /// Kind of reference (inferred during parsing or resolution)
    kind: RefKind = .symbol,
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
    /// Template parameter documentation (@tparam)
    tparams: []const ParamDoc = &[_]ParamDoc{},
    /// Return value documentation (@retval)
    retvals: []const RetvalDoc = &[_]RetvalDoc{},
    /// Effects description (@effects) - C++ standard style
    effects: ?[]const u8 = null,
    /// Requirements description (@requires) - semantic preconditions
    requires: ?[]const u8 = null,
    /// Complexity description (@complexity) - time/space complexity
    complexity: ?[]const u8 = null,
    /// Remarks (@remarks) - additional remarks
    remarks: []const []const u8 = &[_][]const u8{},
    /// Thread safety (@sync, @threadsafety)
    sync: ?[]const u8 = null,
    /// Class invariants (@invariant)
    invariants: []const []const u8 = &[_][]const u8{},
    /// Group membership (@ingroup)
    ingroup: ?[]const u8 = null,
    /// Exclusion mode (@exclude)
    exclude: ExcludeMode = .none,
    /// Synopsis override (@synopsis) - replaces generated synopsis
    synopsis_override: ?[]const u8 = null,
    /// Group membership (@group) - groups related entities together
    group: ?GroupInfo = null,
    /// Unique name override (@unique_name) - custom link target name
    unique_name_override: ?[]const u8 = null,
    /// Module membership (@module) - logical module organization
    module: ?[]const u8 = null,
    /// Entity target (@entity) - remote documentation for another entity
    entity_target: ?[]const u8 = null,
    /// Whether this is file-level documentation (@file)
    is_file_doc: bool = false,
    /// Output section header (@output_section) - adds section comment in synopsis
    output_section: ?[]const u8 = null,
    /// Copy documentation from another entity (@copydoc)
    copydoc_target: ?[]const u8 = null,
    /// TODO items (@todo)
    todos: []const TodoItem = &[_]TodoItem{},
    /// Known bugs (@bug)
    bugs: []const BugItem = &[_]BugItem{},
    /// External code snippets (@snippet)
    snippets: []const SnippetRef = &[_]SnippetRef{},
    /// Attention notices (@attention)
    attention: []const []const u8 = &[_][]const u8{},
    /// Important notices (@important)
    important: []const []const u8 = &[_][]const u8{},
    /// Date information (@date)
    dates: []const DateInfo = &[_]DateInfo{},
    /// Copyright notice (@copyright)
    copyright: ?[]const u8 = null,
    /// Mermaid diagrams (@mermaid/@endmermaid)
    mermaid_diagrams: []const MermaidDiagram = &[_]MermaidDiagram{},
    /// Code blocks (@code/@endcode)
    code_blocks: []const CodeBlock = &[_]CodeBlock{},
    /// Test references (@test)
    tests: []const TestRef = &[_]TestRef{},
    /// Cross-references (@ref)
    refs: []const RefLink = &[_]RefLink{},
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
    attributes: []const Attribute = &[_]Attribute{},
    /// Functions called by this function (for call graph)
    calls: []const []const u8 = &[_][]const u8{},
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

/// Union definition
/// Unions are similar to structs but all fields share the same memory location
pub const Union = struct {
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
    is_final: bool = false,
    is_pure_virtual: bool = false,
    is_defaulted: bool = false,
    is_deleted: bool = false,
    is_constexpr: bool = false,
    is_consteval: bool = false,
    is_explicit: bool = false,
    is_noexcept: bool = false,
    attributes: []const Attribute = &[_]Attribute{},
    /// Functions/methods called by this method (for call graph)
    calls: []const []const u8 = &[_][]const u8{},
    /// Source location of the method declaration
    location: SourceLocation = .{ .file = "", .line = 0, .column = 0 },
};

/// C++ class field with access specifier
pub const ClassField = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
    access: AccessSpecifier = .private,
};

/// Kind of friend declaration
pub const FriendKind = enum {
    class,
    function,
};

/// C++ friend declaration
pub const Friend = struct {
    /// Kind of friend (class or function)
    kind: FriendKind,
    /// Name of the friend class or function
    name: []const u8,
    /// Full signature for friend functions (e.g., "void helper(Foo&)")
    signature: ?[]const u8 = null,
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
    attributes: []const Attribute = &[_]Attribute{},
    friends: []const Friend = &[_]Friend{},
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
    is_variadic: bool = false, // true for parameter packs (typename... Args)
    default_value: ?[]const u8 = null, // default value (e.g., "int" for typename T = int)
};

/// C++ attribute (e.g., [[nodiscard]], [[deprecated("reason")]])
pub const Attribute = struct {
    /// Attribute name (e.g., "nodiscard", "deprecated", "maybe_unused")
    name: []const u8,
    /// Optional argument (e.g., "Use the return value" for [[nodiscard("...")]])
    argument: ?[]const u8 = null,
};

/// C++20 concept definition
pub const Concept = struct {
    name: []const u8,
    constraint: []const u8, // The constraint expression
    template_params: []const TemplateParam = &[_]TemplateParam{},
    docstring: ?DocString = null,
    namespace: ?[]const u8 = null,
};

/// Custom documentation page from @page or @mainpage
pub const Page = struct {
    /// Page identifier (e.g., "examples" or "mainpage")
    id: []const u8,
    /// Page title (e.g., "Example Code")
    title: []const u8,
    /// Full content after title
    content: []const u8,
    /// true for @mainpage
    is_mainpage: bool,
};

/// Doxygen-style group definition (@defgroup)
pub const Group = struct {
    /// Group identifier (e.g., "math_utils")
    id: []const u8,
    /// Group display name (e.g., "Math Utilities")
    name: []const u8,
    /// Brief description
    brief: ?[]const u8 = null,
};

/// TODO item from @todo tag
pub const TodoItem = struct {
    /// Description of the TODO
    description: []const u8,
    /// Source file where this appears (filled in by caller)
    source_file: []const u8 = "",
    /// Line number (filled in by caller)
    line: u32 = 0,
    /// Entity name (function/class) where it appears (filled in by caller)
    entity_name: []const u8 = "",
};

/// Bug item from @bug tag
pub const BugItem = struct {
    /// Description of the bug
    description: []const u8,
    /// Source file where this appears (filled in by caller)
    source_file: []const u8 = "",
    /// Line number (filled in by caller)
    line: u32 = 0,
    /// Entity name (function/class) where it appears (filled in by caller)
    entity_name: []const u8 = "",
};

/// Reference to an external code snippet (@snippet)
pub const SnippetRef = struct {
    /// Path to the snippet file (e.g., "examples/vector_usage.cpp")
    file: []const u8,
    /// Anchor name to extract (e.g., "basic_example")
    anchor: []const u8,
    /// Optional language override for syntax highlighting (default inferred from extension)
    language: ?[]const u8 = null,
};

/// Date information from @date tag
pub const DateInfo = struct {
    /// The date string (e.g., "2024-01-15")
    date: []const u8,
    /// Optional description (e.g., "updated", "created", etc.)
    description: ?[]const u8 = null,
};

/// Mermaid diagram from @mermaid/@endmermaid block
pub const MermaidDiagram = struct {
    /// Diagram content (mermaid syntax)
    content: []const u8,
    /// Optional caption/title for the diagram
    caption: ?[]const u8 = null,
};

/// Code block from @code/@endcode
pub const CodeBlock = struct {
    /// Code content
    content: []const u8,
    /// Language hint (e.g., "cpp", "python", etc.)
    language: ?[]const u8 = null,
    /// Whether to show line numbers
    show_line_numbers: bool = false,
};

/// Include directive information
pub const IncludeInfo = struct {
    /// Include path (e.g., "vector.hpp" or "spatial/point.hpp")
    path: []const u8,
    /// Whether this is a system include (<...>) vs local include ("...")
    is_system: bool,
    /// Line number where the include appears
    line: u32,
};

/// Function call information for call graph generation
pub const CallInfo = struct {
    /// Name of the function making the call
    caller: []const u8,
    /// Name of the function being called
    callee: []const u8,
    /// Location where the call occurs
    call_site: SourceLocation,
    /// Whether this is a method call (obj.method())
    is_method_call: bool = false,
};

/// A parsed module (typically one header file)
pub const Module = struct {
    name: []const u8,
    functions: []const Function,
    structs: []const Struct,
    unions: []const Union = &[_]Union{},
    enums: []const Enum,
    typedefs: []const Typedef,
    macros: []const Macro = &[_]Macro{},
    // C++ specific
    classes: []const Class = &[_]Class{},
    namespaces: []const Namespace = &[_]Namespace{},
    type_aliases: []const TypeAlias = &[_]TypeAlias{},
    concepts: []const Concept = &[_]Concept{},
    groups: []const Group = &[_]Group{},
    /// File-level documentation (@file)
    file_doc: ?DocString = null,
    /// Custom pages (@page, @mainpage)
    pages: []const Page = &[_]Page{},
    /// Include directives found in this file
    includes: []const IncludeInfo = &[_]IncludeInfo{},
};
