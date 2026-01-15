//! JSON Schema v2 for Stig Documentation
//!
//! This module defines the canonical intermediate representation for all documentation.
//! The DocumentModel is the single source of truth - all output formats (markdown, HTML, etc.)
//! are rendered FROM this model.
//!
//! ## Design Principles
//!
//! 1. **Pre-computed Everything**: All cross-references are resolved, all anchors are computed,
//!    all filtering is applied. Renderers should be pure template-like transformations.
//!
//! 2. **Self-contained**: The JSON output can be saved, version-controlled, and consumed by
//!    external tools. It's human-readable and diffable.
//!
//! 3. **No Logic in Renderers**: Renderers (markdown, HTML) should NOT do:
//!    - Cross-reference resolution (already done)
//!    - Anchor generation (already done)
//!    - Filtering/blacklisting (already done)
//!    - Symbol table lookups (already done)
//!
//! 4. **Extensible**: Easy to add new fields without breaking existing renderers.
//!
//! ## Architecture
//!
//! ```
//! Parser → types.Module → JSON Generator → DocumentModel → JSON
//!                                                             ↓
//!                                           JSON Reader ← JSON file
//!                                                             ↓
//!                                           Renderer (markdown/HTML)
//!                                                             ↓
//!                                           Writer (single/multi-file)
//! ```
//!
//! ## Example JSON Structure
//!
//! ```json
//! {
//!   "schema_version": "2.0",
//!   "generator": { "name": "stig", "version": "0.3.0" },
//!   "project": { "title": "My Library" },
//!   "statistics": { "coverage_percent": 85.0 },
//!   "index": [
//!     { "name": "Point2", "anchor": "spatial-point2", "path": "types/point" }
//!   ],
//!   "modules": [
//!     {
//!       "name": "include/point.hpp",
//!       "functions": [
//!         {
//!           "name": "distance",
//!           "anchor": "spatial-distance",
//!           "signature": "T distance(Point2<T> a, Point2<T> b)",
//!           "doc": {
//!             "brief": "Calculate distance",
//!             "refs": [
//!               {
//!                 "target": "Point2",
//!                 "resolved_url": "../types/point#spatial-point2"
//!               }
//!             ]
//!           }
//!         }
//!       ]
//!     }
//!   ]
//! }
//! ```

const std = @import("std");

// ============================================================================
// Top-level Document Model
// ============================================================================

pub const DocumentModel = struct {
    schema_version: []const u8 = "2.0",
    generator: GeneratorInfo,
    generated_at: []const u8, // ISO 8601 timestamp
    project: ProjectInfo,
    config: ConfigInfo,
    statistics: Statistics,
    index: []const IndexEntry,
    modules: []const ModuleDoc,
    pages: []const PageDoc,
    appendix: Appendix,
};

// ============================================================================
// Metadata
// ============================================================================

pub const GeneratorInfo = struct {
    name: []const u8, // "stig"
    version: []const u8, // "0.3.0"
};

pub const ProjectInfo = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    version: ?[]const u8 = null,
    authors: []const []const u8 = &[_][]const u8{},
    license: ?[]const u8 = null,
    repository: ?[]const u8 = null,
};

pub const ConfigInfo = struct {
    language: []const u8 = "en",
    /// Template for source code links: {file} and {line} are replaced
    source_url_template: ?[]const u8 = null,
};

pub const Statistics = struct {
    modules: u32,
    functions: u32,
    classes: u32,
    structs: u32,
    enums: u32,
    macros: u32,
    typedefs: u32,
    type_aliases: u32,
    concepts: u32,
    documented: u32,
    undocumented: u32,
    coverage_percent: f64,
};

// ============================================================================
// Index
// ============================================================================

pub const IndexEntry = struct {
    name: []const u8,
    qualified_name: []const u8, // e.g., "spatial::Point2"
    kind: SymbolKind,
    brief: ?[]const u8 = null,
    module: []const u8, // module name
    anchor: []const u8, // pre-computed anchor
    path: []const u8, // for multi-file: "types/point"
};

pub const SymbolKind = enum {
    function,
    class_,
    struct_,
    union_,
    enum_,
    typedef,
    type_alias,
    macro,
    concept,
    namespace,
    method,
    field,
};

// ============================================================================
// Module Documentation
// ============================================================================

pub const ModuleDoc = struct {
    id: []const u8, // unique identifier
    name: []const u8, // file path
    path: []const u8, // for multi-file output: "types/point"
    title: ?[]const u8 = null, // display title
    file_doc: ?DocStringDoc = null,
    includes: []const IncludeDoc = &[_]IncludeDoc{},
    functions: []const FunctionDoc = &[_]FunctionDoc{},
    classes: []const ClassDoc = &[_]ClassDoc{},
    structs: []const StructDoc = &[_]StructDoc{},
    unions: []const UnionDoc = &[_]UnionDoc{},
    enums: []const EnumDoc = &[_]EnumDoc{},
    typedefs: []const TypedefDoc = &[_]TypedefDoc{},
    type_aliases: []const TypeAliasDoc = &[_]TypeAliasDoc{},
    macros: []const MacroDoc = &[_]MacroDoc{},
    concepts: []const ConceptDoc = &[_]ConceptDoc{},
    namespaces: []const NamespaceDoc = &[_]NamespaceDoc{},
};

// ============================================================================
// Documentation Entities
// ============================================================================

pub const FunctionDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    signature: []const u8, // full signature for display
    return_type: []const u8,
    parameters: []const ParameterDoc,
    template_params: []const TemplateParamDoc = &[_]TemplateParamDoc{},
    requires_clause: ?[]const u8 = null,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
    qualifiers: FunctionQualifiers,
    calls: []const []const u8 = &[_][]const u8{}, // for call graphs
};

pub const FunctionQualifiers = struct {
    is_static: bool = false,
    is_inline: bool = false,
    is_constexpr: bool = false,
    is_consteval: bool = false,
    is_noexcept: bool = false,
    attributes: []const AttributeDoc = &[_]AttributeDoc{},
};

pub const ClassDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    template_params: []const TemplateParamDoc = &[_]TemplateParamDoc{},
    requires_clause: ?[]const u8 = null,
    base_classes: []const BaseClassDoc = &[_]BaseClassDoc{},
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
    attributes: []const AttributeDoc = &[_]AttributeDoc{},

    // Members organized by access
    members: ClassMembers,

    // Nested types
    nested_classes: []const ClassDoc = &[_]ClassDoc{},
    nested_enums: []const EnumDoc = &[_]EnumDoc{},

    friends: []const FriendDoc = &[_]FriendDoc{},
};

pub const ClassMembers = struct {
    public: MemberGroup,
    protected: MemberGroup,
    private: MemberGroup,
};

pub const MemberGroup = struct {
    methods: []const MethodDoc = &[_]MethodDoc{},
    fields: []const FieldDoc = &[_]FieldDoc{},
};

pub const MethodDoc = struct {
    id: []const u8,
    name: []const u8,
    anchor: []const u8,
    signature: []const u8,
    return_type: []const u8,
    parameters: []const ParameterDoc,
    kind: MethodKind,
    operator_symbol: ?[]const u8 = null, // for operators
    doc: ?DocStringDoc = null,
    qualifiers: MethodQualifiers,
    calls: []const []const u8 = &[_][]const u8{},
    location: LocationDoc,
};

pub const MethodKind = enum {
    regular,
    constructor,
    copy_constructor,
    move_constructor,
    destructor,
    operator_overload,
    conversion_operator,
};

pub const MethodQualifiers = struct {
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
    attributes: []const AttributeDoc = &[_]AttributeDoc{},
};

pub const FieldDoc = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
};

pub const StructDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    fields: []const FieldDoc,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const UnionDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    fields: []const FieldDoc,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const EnumDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    values: []const EnumValueDoc,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const EnumValueDoc = struct {
    name: []const u8,
    value: ?i64 = null,
    doc: ?[]const u8 = null,
};

pub const TypedefDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    underlying: []const u8,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const TypeAliasDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    underlying_type: []const u8,
    template_params: []const TemplateParamDoc = &[_]TemplateParamDoc{},
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const MacroDoc = struct {
    id: []const u8,
    name: []const u8,
    anchor: []const u8,
    params: ?[]const []const u8 = null,
    body: []const u8,
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const ConceptDoc = struct {
    id: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    anchor: []const u8,
    constraint: []const u8,
    template_params: []const TemplateParamDoc = &[_]TemplateParamDoc{},
    doc: ?DocStringDoc = null,
    location: LocationDoc,
    source_url: ?[]const u8 = null,
};

pub const NamespaceDoc = struct {
    name: []const u8,
    qualified_name: []const u8,
    doc: ?DocStringDoc = null,
};

// ============================================================================
// Supporting Types
// ============================================================================

pub const ParameterDoc = struct {
    name: []const u8,
    type_str: []const u8,
    doc: ?[]const u8 = null,
};

pub const TemplateParamDoc = struct {
    name: []const u8,
    kind: []const u8, // "typename", "class", or type for non-type params
    is_variadic: bool = false,
    default_value: ?[]const u8 = null,
    doc: ?[]const u8 = null,
};

pub const BaseClassDoc = struct {
    name: []const u8,
    access: AccessSpecifier,
    is_virtual: bool = false,
    /// Resolved link to base class documentation
    resolved_link: ?[]const u8 = null,
};

pub const AccessSpecifier = enum {
    public,
    protected,
    private,
};

pub const AttributeDoc = struct {
    name: []const u8,
    argument: ?[]const u8 = null,
};

pub const FriendDoc = struct {
    kind: FriendKind,
    name: []const u8,
    signature: ?[]const u8 = null,
};

pub const FriendKind = enum {
    class_,
    function,
};

pub const LocationDoc = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

pub const IncludeDoc = struct {
    path: []const u8,
    is_system: bool,
    resolved: ?[]const u8 = null, // resolved file path
};

// ============================================================================
// DocString (Enhanced with Resolved References)
// ============================================================================

pub const DocStringDoc = struct {
    raw: []const u8,
    brief: ?[]const u8 = null,
    details: ?[]const u8 = null,
    params: []const ParamDoc = &[_]ParamDoc{},
    tparams: []const ParamDoc = &[_]ParamDoc{},
    returns: ?[]const u8 = null,
    retvals: []const RetvalDoc = &[_]RetvalDoc{},
    exceptions: []const ExceptionDoc = &[_]ExceptionDoc{},
    examples: []const []const u8 = &[_][]const u8{},
    code_blocks: []const CodeBlockDoc = &[_]CodeBlockDoc{},
    notes: []const []const u8 = &[_][]const u8{},
    warnings: []const []const u8 = &[_][]const u8{},
    attention: []const []const u8 = &[_][]const u8{},
    important: []const []const u8 = &[_][]const u8{},
    deprecated: ?[]const u8 = null,
    see_also: []const ResolvedRefDoc = &[_]ResolvedRefDoc{},
    preconditions: []const []const u8 = &[_][]const u8{},
    postconditions: []const []const u8 = &[_][]const u8{},
    since: ?[]const u8 = null,
    author: ?[]const u8 = null,
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,
    copyright: ?[]const u8 = null,

    // C++ standard-style sections
    effects: ?[]const u8 = null,
    requires: ?[]const u8 = null,
    complexity: ?[]const u8 = null,
    remarks: []const []const u8 = &[_][]const u8{},
    sync: ?[]const u8 = null,
    invariants: []const []const u8 = &[_][]const u8{},

    // Organizational
    ingroup: ?[]const u8 = null,
    module: ?[]const u8 = null,

    // Diagrams
    mermaid_diagrams: []const MermaidDiagramDoc = &[_]MermaidDiagramDoc{},

    // Cross-references (resolved)
    refs: []const ResolvedRefDoc = &[_]ResolvedRefDoc{},
};

pub const ParamDoc = struct {
    name: []const u8,
    description: []const u8,
};

pub const RetvalDoc = struct {
    value: []const u8,
    description: []const u8,
};

pub const ExceptionDoc = struct {
    exception_type: []const u8,
    description: []const u8,
};

pub const CodeBlockDoc = struct {
    content: []const u8,
    language: ?[]const u8 = null,
    show_line_numbers: bool = false,
};

pub const MermaidDiagramDoc = struct {
    content: []const u8,
    caption: ?[]const u8 = null,
};

pub const ResolvedRefDoc = struct {
    /// Original target from @see or @ref
    target: []const u8,
    /// Display text (if custom)
    display_text: ?[]const u8 = null,
    /// Resolved URL/path (relative for internal, absolute for external)
    resolved_url: ?[]const u8 = null,
    /// Whether this is an external link
    is_external: bool = false,
};

// ============================================================================
// Pages (Custom Documentation)
// ============================================================================

pub const PageDoc = struct {
    id: []const u8,
    title: []const u8,
    content: []const u8, // markdown content
    is_mainpage: bool = false,
};

// ============================================================================
// Appendix
// ============================================================================

pub const Appendix = struct {
    todos: []const TodoDoc = &[_]TodoDoc{},
    bugs: []const BugDoc = &[_]BugDoc{},
    tests: []const TestDoc = &[_]TestDoc{},
};

pub const TodoDoc = struct {
    description: []const u8,
    location: LocationDoc,
    entity_name: []const u8,
    entity_kind: SymbolKind,
};

pub const BugDoc = struct {
    description: []const u8,
    location: LocationDoc,
    entity_name: []const u8,
    entity_kind: SymbolKind,
};

pub const TestDoc = struct {
    name: []const u8,
    file: ?[]const u8 = null,
    line: ?u32 = null,
    tests_entity: []const u8, // which entity this tests
};
