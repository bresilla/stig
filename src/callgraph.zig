const std = @import("std");
const types = @import("model/types.zig");

/// Call graph builder and renderer
pub const CallGraph = struct {
    allocator: std.mem.Allocator,
    /// Map of function name to list of functions it calls
    calls: std.StringHashMap(std.ArrayList([]const u8)),
    /// All function names in the graph
    nodes: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .calls = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .nodes = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.calls.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.calls.deinit();
        self.nodes.deinit();
    }

    /// Builds call graph from parsed modules
    pub fn buildFromModules(self: *Self, modules: []const types.Module) !void {
        for (modules) |module| {
            // Process functions
            for (module.functions) |func| {
                try self.addNode(func.name);
                for (func.calls) |callee| {
                    try self.addEdge(func.name, callee);
                }
            }

            // Process class methods
            for (module.classes) |class| {
                for (class.methods) |method| {
                    // Use qualified name: ClassName::methodName
                    const qualified_name = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}::{s}",
                        .{ class.name, method.name },
                    );
                    defer self.allocator.free(qualified_name);

                    try self.addNode(qualified_name);
                    for (method.calls) |callee| {
                        try self.addEdge(qualified_name, callee);
                    }
                }
            }
        }
    }

    /// Adds a node (function) to the graph
    fn addNode(self: *Self, name: []const u8) !void {
        // Check if already exists
        for (self.nodes.items) |node| {
            if (std.mem.eql(u8, node, name)) return;
        }
        try self.nodes.append(name);
    }

    /// Adds an edge (function call) to the graph
    fn addEdge(self: *Self, caller: []const u8, callee: []const u8) !void {
        const gop = try self.calls.getOrPut(caller);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }

        // Check if edge already exists
        for (gop.value_ptr.items) |existing_callee| {
            if (std.mem.eql(u8, existing_callee, callee)) return;
        }

        try gop.value_ptr.append(callee);
    }

    /// Generates a Mermaid flowchart diagram
    pub fn generateMermaid(self: *Self, title: ?[]const u8) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        // Header
        try buffer.appendSlice("```mermaid\n");
        try buffer.appendSlice("graph TD\n");

        if (title) |t| {
            try buffer.appendSlice("    %% ");
            try buffer.appendSlice(t);
            try buffer.appendSlice("\n");
        }

        // Nodes (sanitize names for Mermaid)
        for (self.nodes.items) |node| {
            try buffer.appendSlice("    ");
            const node_id = try self.sanitizeNodeId(node);
            defer self.allocator.free(node_id);
            try buffer.appendSlice(node_id);
            try buffer.appendSlice("[\"");
            try buffer.appendSlice(node);
            try buffer.appendSlice("\"]\n");
        }

        // Edges
        var iter = self.calls.iterator();
        while (iter.next()) |entry| {
            const caller = entry.key_ptr.*;
            const callees = entry.value_ptr.*;

            const caller_id = try self.sanitizeNodeId(caller);
            defer self.allocator.free(caller_id);

            for (callees.items) |callee| {
                const callee_id = try self.sanitizeNodeId(callee);
                defer self.allocator.free(callee_id);

                try buffer.appendSlice("    ");
                try buffer.appendSlice(caller_id);
                try buffer.appendSlice(" --> ");
                try buffer.appendSlice(callee_id);
                try buffer.appendSlice("\n");
            }
        }

        try buffer.appendSlice("```\n");
        return try buffer.toOwnedSlice();
    }

    /// Generates an ASCII tree diagram for a specific function
    pub fn generateAsciiTree(self: *Self, root_function: []const u8, max_depth: usize) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        try self.generateAsciiTreeRecursive(&buffer, root_function, 0, max_depth, &visited, "");

        return try buffer.toOwnedSlice();
    }

    fn generateAsciiTreeRecursive(
        self: *Self,
        buffer: *std.ArrayList(u8),
        function: []const u8,
        depth: usize,
        max_depth: usize,
        visited: *std.StringHashMap(void),
        prefix: []const u8,
    ) !void {
        // Write current function
        try buffer.appendSlice(function);
        try buffer.appendSlice("\n");

        if (depth >= max_depth) return;

        // Check for cycles
        if (visited.contains(function)) {
            try buffer.appendSlice(prefix);
            try buffer.appendSlice("└── (cycle detected)\n");
            return;
        }

        try visited.put(function, {});
        defer _ = visited.remove(function);

        // Get callees
        const callees = self.calls.get(function) orelse return;
        if (callees.items.len == 0) return;

        for (callees.items, 0..) |callee, i| {
            const is_last = i == callees.items.len - 1;
            const branch = if (is_last) "└── " else "├── ";
            const new_prefix = if (is_last) "    " else "│   ";

            try buffer.appendSlice(prefix);
            try buffer.appendSlice(branch);

            // Build new prefix for recursion
            var next_prefix = std.ArrayList(u8).init(self.allocator);
            defer next_prefix.deinit();
            try next_prefix.appendSlice(prefix);
            try next_prefix.appendSlice(new_prefix);

            try self.generateAsciiTreeRecursive(
                buffer,
                callee,
                depth + 1,
                max_depth,
                visited,
                next_prefix.items,
            );
        }
    }

    /// Sanitizes a function name to be a valid Mermaid node ID
    /// Replaces special characters with underscores
    fn sanitizeNodeId(self: *Self, name: []const u8) ![]const u8 {
        var result = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            result[i] = switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9' => c,
                else => '_',
            };
        }
        return result;
    }

    /// Gets the list of functions called by a specific function
    pub fn getCallees(self: *Self, function: []const u8) ?[]const []const u8 {
        const callees = self.calls.get(function) orelse return null;
        return callees.items;
    }

    /// Gets the list of functions that call a specific function (reverse lookup)
    pub fn getCallers(self: *Self, function: []const u8) ![]const []const u8 {
        var callers = std.ArrayList([]const u8).init(self.allocator);
        errdefer callers.deinit();

        var iter = self.calls.iterator();
        while (iter.next()) |entry| {
            const caller = entry.key_ptr.*;
            const callees = entry.value_ptr.*;

            for (callees.items) |callee| {
                if (std.mem.eql(u8, callee, function)) {
                    try callers.append(caller);
                    break;
                }
            }
        }

        return try callers.toOwnedSlice();
    }
};

// Tests
test "call graph basic" {
    var graph = CallGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addNode("main");
    try graph.addNode("init");
    try graph.addNode("process");

    try graph.addEdge("main", "init");
    try graph.addEdge("main", "process");

    try std.testing.expectEqual(@as(usize, 3), graph.nodes.items.len);

    const main_callees = graph.getCallees("main");
    try std.testing.expect(main_callees != null);
    try std.testing.expectEqual(@as(usize, 2), main_callees.?.len);
}

test "call graph mermaid generation" {
    var graph = CallGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addNode("main");
    try graph.addNode("init");
    try graph.addEdge("main", "init");

    const mermaid = try graph.generateMermaid("Test Graph");
    defer std.testing.allocator.free(mermaid);

    try std.testing.expect(std.mem.indexOf(u8, mermaid, "graph TD") != null);
    try std.testing.expect(std.mem.indexOf(u8, mermaid, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, mermaid, "init") != null);
    try std.testing.expect(std.mem.indexOf(u8, mermaid, "-->") != null);
}

test "call graph ascii tree" {
    var graph = CallGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addNode("main");
    try graph.addNode("init");
    try graph.addNode("process");
    try graph.addEdge("main", "init");
    try graph.addEdge("main", "process");

    const tree = try graph.generateAsciiTree("main", 2);
    defer std.testing.allocator.free(tree);

    try std.testing.expect(std.mem.indexOf(u8, tree, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree, "init") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree, "process") != null);
}
