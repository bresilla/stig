const std = @import("std");
const types = @import("../model/types.zig");

/// Markdown output generator
pub const MarkdownGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Generates markdown documentation for a module
    pub fn generate(self: *Self, module: types.Module) ![]const u8 {
        const writer = self.buffer.writer();

        try writer.print("# {s}\n\n", .{module.name});

        // Functions section
        if (module.functions.len > 0) {
            try writer.print("## Functions\n\n", .{});
            for (module.functions) |func| {
                try self.writeFunction(writer, func);
            }
        }

        // Structs section
        if (module.structs.len > 0) {
            try writer.print("## Structures\n\n", .{});
            for (module.structs) |s| {
                try self.writeStruct(writer, s);
            }
        }

        // Enums section
        if (module.enums.len > 0) {
            try writer.print("## Enumerations\n\n", .{});
            for (module.enums) |e| {
                try self.writeEnum(writer, e);
            }
        }

        return self.buffer.items;
    }

    fn writeFunction(self: *Self, writer: anytype, func: types.Function) !void {
        _ = self;

        try writer.print("### `{s}`\n\n", .{func.name});
        try writer.print("```c\n{s} {s}(", .{ func.return_type, func.name });

        for (func.params, 0..) |param, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{s} {s}", .{ param.type_str, param.name });
        }
        try writer.print(");\n```\n\n", .{});

        if (func.doc) |doc| {
            if (doc.brief) |brief| {
                try writer.print("{s}\n\n", .{brief});
            }

            if (doc.params.len > 0) {
                try writer.print("**Parameters:**\n", .{});
                for (doc.params) |param| {
                    try writer.print("- `{s}`: {s}\n", .{ param.name, param.description });
                }
                try writer.print("\n", .{});
            }

            if (doc.returns) |ret| {
                try writer.print("**Returns:** {s}\n\n", .{ret});
            }
        }

        try writer.print("---\n\n", .{});
    }

    fn writeStruct(self: *Self, writer: anytype, s: types.Struct) !void {
        _ = self;

        try writer.print("### `{s}`\n\n", .{s.name});
        try writer.print("```c\nstruct {s} {{\n", .{s.name});

        for (s.fields) |field| {
            try writer.print("    {s} {s};\n", .{ field.type_str, field.name });
        }
        try writer.print("}};\n```\n\n", .{});

        if (s.doc) |doc| {
            if (doc.brief) |brief| {
                try writer.print("{s}\n\n", .{brief});
            }
        }

        if (s.fields.len > 0) {
            try writer.print("**Fields:**\n", .{});
            for (s.fields) |field| {
                if (field.doc) |doc| {
                    try writer.print("- `{s}`: {s}\n", .{ field.name, doc });
                } else {
                    try writer.print("- `{s}`\n", .{field.name});
                }
            }
            try writer.print("\n", .{});
        }

        try writer.print("---\n\n", .{});
    }

    fn writeEnum(self: *Self, writer: anytype, e: types.Enum) !void {
        _ = self;

        try writer.print("### `{s}`\n\n", .{e.name});
        try writer.print("```c\nenum {s} {{\n", .{e.name});

        for (e.values) |val| {
            if (val.value) |v| {
                try writer.print("    {s} = {d},\n", .{ val.name, v });
            } else {
                try writer.print("    {s},\n", .{val.name});
            }
        }
        try writer.print("}};\n```\n\n", .{});

        if (e.doc) |doc| {
            if (doc.brief) |brief| {
                try writer.print("{s}\n\n", .{brief});
            }
        }

        try writer.print("---\n\n", .{});
    }
};
