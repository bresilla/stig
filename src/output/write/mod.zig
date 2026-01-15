//! Output Writers
//!
//! This module provides writers that output rendered documentation to files.
//! Writers handle file I/O and directory structure, not content generation.

pub const single = @import("single.zig");
pub const SingleFileWriter = single.SingleFileWriter;
pub const SingleFileOptions = single.SingleFileOptions;

pub const multi = @import("multi.zig");
pub const MultiFileWriter = multi.MultiFileWriter;
pub const MultiFileOptions = multi.MultiFileOptions;
pub const GroupingStrategy = multi.GroupingStrategy;
