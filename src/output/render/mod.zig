//! Output Renderers
//!
//! This module provides renderers that transform DocumentModel to various output formats.
//! Renderers are pure transformations - they don't do cross-reference resolution or filtering.

pub const markdown = @import("markdown.zig");
pub const MarkdownRenderer = markdown.MarkdownRenderer;
