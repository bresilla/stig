/// JSON output module
///
/// This module handles JSON serialization and deserialization of documentation.
/// JSON is the canonical intermediate representation for all output formats.
pub const schema = @import("schema.zig");

// Re-export main types
pub const DocumentModel = schema.DocumentModel;
pub const GeneratorInfo = schema.GeneratorInfo;
pub const ProjectInfo = schema.ProjectInfo;
pub const Statistics = schema.Statistics;
pub const IndexEntry = schema.IndexEntry;
pub const ModuleDoc = schema.ModuleDoc;
pub const FunctionDoc = schema.FunctionDoc;
pub const ClassDoc = schema.ClassDoc;

// Generator
pub const generator = @import("generator.zig");
pub const Generator = generator.Generator;

// Reader for deserializing JSON back to DocumentModel
pub const reader = @import("reader.zig");
pub const Reader = reader;
pub const ParseResult = reader.ParseResult;
pub const parse = reader.parse;
pub const parseFile = reader.parseFile;
