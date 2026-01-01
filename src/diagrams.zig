const std = @import("std");
const types = @import("model/types.zig");

/// Configuration for diagram generation
pub const DiagramConfig = struct {
    /// Whether to generate inheritance diagrams
    inheritance_diagrams: bool = true,
    /// Output format for diagrams
    format: DiagramFormat = .mermaid,
    /// Maximum depth of inheritance to show
    max_depth: u32 = 5,
    /// Whether to show class members in diagrams
    show_members: bool = false,
    /// Whether to show abstract stereotype
    show_abstract: bool = true,
    /// Whether to show access specifiers on inheritance
    show_access: bool = true,
};

/// Diagram output format
pub const DiagramFormat = enum {
    /// Mermaid syntax for mdbook
    mermaid,
    /// ASCII art for plain markdown
    ascii,
    /// PlantUML syntax
    plantuml,
};

/// Node in the inheritance graph
pub const InheritanceNode = struct {
    /// Class name
    name: []const u8,
    /// Whether this class is abstract (has pure virtual methods)
    is_abstract: bool = false,
    /// Template parameters if any
    template_params: []const types.TemplateParam = &[_]types.TemplateParam{},
    /// Public methods (for display in diagram)
    public_methods: []const types.Method = &[_]types.Method{},
    /// Whether this is an external class (not defined in our codebase)
    is_external: bool = false,
};

/// Edge in the inheritance graph
pub const InheritanceEdge = struct {
    /// Child class name
    child: []const u8,
    /// Parent class name
    parent: []const u8,
    /// Access specifier for inheritance
    access: types.AccessSpecifier = .public,
    /// Whether this is virtual inheritance
    is_virtual: bool = false,
};

/// Inheritance graph for diagram generation
pub const InheritanceGraph = struct {
    allocator: std.mem.Allocator,
    /// All nodes (classes) in the graph
    nodes: std.StringHashMap(InheritanceNode),
    /// All edges (inheritance relationships)
    edges: std.ArrayList(InheritanceEdge),
    /// Configuration
    config: DiagramConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .nodes = std.StringHashMap(InheritanceNode).init(allocator),
            .edges = .empty,
            .config = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: DiagramConfig) Self {
        return Self{
            .allocator = allocator,
            .nodes = std.StringHashMap(InheritanceNode).init(allocator),
            .edges = .empty,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.edges.deinit(self.allocator);
    }

    /// Builds the inheritance graph from parsed modules
    pub fn buildFromModules(self: *Self, modules: []const types.Module) !void {
        for (modules) |module| {
            for (module.classes) |class| {
                try self.addClass(class);
            }
        }
    }

    /// Adds a class and its inheritance relationships to the graph
    pub fn addClass(self: *Self, class: types.Class) !void {
        // Check if class is abstract (has pure virtual methods)
        var is_abstract = false;
        for (class.methods) |method| {
            if (method.is_pure_virtual) {
                is_abstract = true;
                break;
            }
        }

        // Collect public methods for display
        var public_methods: std.ArrayList(types.Method) = .empty;
        defer public_methods.deinit(self.allocator);

        if (self.config.show_members) {
            for (class.methods) |method| {
                if (method.access == .public) {
                    try public_methods.append(self.allocator, method);
                }
            }
        }

        // Add node
        try self.nodes.put(class.name, InheritanceNode{
            .name = class.name,
            .is_abstract = is_abstract,
            .template_params = class.template_params,
            .public_methods = if (public_methods.items.len > 0)
                try self.allocator.dupe(types.Method, public_methods.items)
            else
                &[_]types.Method{},
            .is_external = false,
        });

        // Add edges for base classes
        for (class.base_classes) |base| {
            // Add parent node if not already present (as external)
            if (!self.nodes.contains(base.name)) {
                try self.nodes.put(base.name, InheritanceNode{
                    .name = base.name,
                    .is_abstract = false,
                    .is_external = true,
                });
            }

            // Add edge
            try self.edges.append(self.allocator, InheritanceEdge{
                .child = class.name,
                .parent = base.name,
                .access = base.access,
                .is_virtual = base.is_virtual,
            });
        }
    }

    /// Gets all root classes (classes with no parents)
    pub fn getRoots(self: *Self) ![][]const u8 {
        var roots: std.ArrayList([]const u8) = .empty;
        defer roots.deinit(self.allocator);

        var iter = self.nodes.keyIterator();
        while (iter.next()) |name| {
            var has_parent = false;
            for (self.edges.items) |edge| {
                if (std.mem.eql(u8, edge.child, name.*)) {
                    has_parent = true;
                    break;
                }
            }
            if (!has_parent) {
                try roots.append(self.allocator, name.*);
            }
        }

        return try roots.toOwnedSlice(self.allocator);
    }

    /// Gets all children of a class
    pub fn getChildren(self: *Self, parent_name: []const u8) ![][]const u8 {
        var children: std.ArrayList([]const u8) = .empty;
        defer children.deinit(self.allocator);

        for (self.edges.items) |edge| {
            if (std.mem.eql(u8, edge.parent, parent_name)) {
                try children.append(self.allocator, edge.child);
            }
        }

        return try children.toOwnedSlice(self.allocator);
    }

    /// Gets all parents of a class
    pub fn getParents(self: *Self, child_name: []const u8) ![]InheritanceEdge {
        var parents: std.ArrayList(InheritanceEdge) = .empty;
        defer parents.deinit(self.allocator);

        for (self.edges.items) |edge| {
            if (std.mem.eql(u8, edge.child, child_name)) {
                try parents.append(self.allocator, edge);
            }
        }

        return try parents.toOwnedSlice(self.allocator);
    }
};

/// Diagram generator for inheritance hierarchies
pub const DiagramGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,
    config: DiagramConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: DiagramConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Generates a diagram for a single class and its hierarchy
    pub fn generateForClass(self: *Self, graph: *InheritanceGraph, class_name: []const u8) ![]const u8 {
        self.buffer.clearRetainingCapacity();

        return switch (self.config.format) {
            .mermaid => try self.generateMermaidForClass(graph, class_name),
            .ascii => try self.generateAsciiForClass(graph, class_name),
            .plantuml => try self.generatePlantUmlForClass(graph, class_name),
        };
    }

    /// Generates a full project-wide inheritance diagram
    pub fn generateFullDiagram(self: *Self, graph: *InheritanceGraph) ![]const u8 {
        self.buffer.clearRetainingCapacity();

        return switch (self.config.format) {
            .mermaid => try self.generateMermaidFull(graph),
            .ascii => try self.generateAsciiFull(graph),
            .plantuml => try self.generatePlantUmlFull(graph),
        };
    }

    // =========================================================================
    // Mermaid generation
    // =========================================================================

    fn generateMermaidForClass(self: *Self, graph: *InheritanceGraph, class_name: []const u8) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```mermaid\nclassDiagram\n");

        // Generate class definitions and relationships
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        try self.writeMermaidClassHierarchy(graph, class_name, &visited, 0);

        try self.buffer.appendSlice(self.allocator, "```\n");
        return self.buffer.items;
    }

    fn generateMermaidFull(self: *Self, graph: *InheritanceGraph) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```mermaid\nclassDiagram\n");

        // Write all class definitions
        var node_iter = graph.nodes.iterator();
        while (node_iter.next()) |entry| {
            try self.writeMermaidClassDef(entry.value_ptr.*);
        }

        try self.buffer.appendSlice(self.allocator, "\n");

        // Write all inheritance relationships
        for (graph.edges.items) |edge| {
            try self.writeMermaidInheritance(edge);
        }

        try self.buffer.appendSlice(self.allocator, "```\n");
        return self.buffer.items;
    }

    fn writeMermaidClassHierarchy(
        self: *Self,
        graph: *InheritanceGraph,
        class_name: []const u8,
        visited: *std.StringHashMap(void),
        depth: u32,
    ) !void {
        if (depth > self.config.max_depth) return;
        if (visited.contains(class_name)) return;

        try visited.put(class_name, {});

        // Write class definition
        if (graph.nodes.get(class_name)) |node| {
            try self.writeMermaidClassDef(node);
        }

        // Write parent relationships and recurse up
        const parents = try graph.getParents(class_name);
        defer self.allocator.free(parents);

        for (parents) |edge| {
            try self.writeMermaidInheritance(edge);
            try self.writeMermaidClassHierarchy(graph, edge.parent, visited, depth + 1);
        }

        // Write child relationships and recurse down
        const children = try graph.getChildren(class_name);
        defer self.allocator.free(children);

        for (children) |child| {
            // Find the edge for this child
            for (graph.edges.items) |edge| {
                if (std.mem.eql(u8, edge.child, child) and std.mem.eql(u8, edge.parent, class_name)) {
                    try self.writeMermaidInheritance(edge);
                    break;
                }
            }
            try self.writeMermaidClassHierarchy(graph, child, visited, depth + 1);
        }
    }

    fn writeMermaidClassDef(self: *Self, node: InheritanceNode) !void {
        try self.buffer.appendSlice(self.allocator, "    class ");
        try self.buffer.appendSlice(self.allocator, node.name);

        // Add template parameters
        if (node.template_params.len > 0) {
            try self.buffer.appendSlice(self.allocator, "~");
            for (node.template_params, 0..) |param, i| {
                if (i > 0) try self.buffer.appendSlice(self.allocator, ",");
                try self.buffer.appendSlice(self.allocator, param.name);
            }
            try self.buffer.appendSlice(self.allocator, "~");
        }

        // Add members if configured
        if (self.config.show_members and node.public_methods.len > 0) {
            try self.buffer.appendSlice(self.allocator, " {\n");
            for (node.public_methods) |method| {
                try self.buffer.appendSlice(self.allocator, "        +");
                try self.buffer.appendSlice(self.allocator, method.name);
                try self.buffer.appendSlice(self.allocator, "(");
                for (method.params, 0..) |param, i| {
                    if (i > 0) try self.buffer.appendSlice(self.allocator, ", ");
                    try self.buffer.appendSlice(self.allocator, param.name);
                }
                try self.buffer.appendSlice(self.allocator, ") ");
                try self.buffer.appendSlice(self.allocator, method.return_type);
                try self.buffer.appendSlice(self.allocator, "\n");
            }
            try self.buffer.appendSlice(self.allocator, "    }\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "\n");
        }

        // Add stereotype for abstract classes
        if (self.config.show_abstract and node.is_abstract) {
            try self.buffer.appendSlice(self.allocator, "    <<abstract>> ");
            try self.buffer.appendSlice(self.allocator, node.name);
            try self.buffer.appendSlice(self.allocator, "\n");
        }

        // Mark external classes
        if (node.is_external) {
            try self.buffer.appendSlice(self.allocator, "    <<external>> ");
            try self.buffer.appendSlice(self.allocator, node.name);
            try self.buffer.appendSlice(self.allocator, "\n");
        }
    }

    fn writeMermaidInheritance(self: *Self, edge: InheritanceEdge) !void {
        try self.buffer.appendSlice(self.allocator, "    ");
        try self.buffer.appendSlice(self.allocator, edge.parent);

        // Use different arrow styles for virtual inheritance
        if (edge.is_virtual) {
            try self.buffer.appendSlice(self.allocator, " <|.. ");
        } else {
            try self.buffer.appendSlice(self.allocator, " <|-- ");
        }

        try self.buffer.appendSlice(self.allocator, edge.child);

        // Add access specifier as note if configured
        if (self.config.show_access and edge.access != .public) {
            try self.buffer.appendSlice(self.allocator, " : ");
            switch (edge.access) {
                .protected => try self.buffer.appendSlice(self.allocator, "protected"),
                .private => try self.buffer.appendSlice(self.allocator, "private"),
                .public => {},
            }
        }

        try self.buffer.appendSlice(self.allocator, "\n");
    }

    // =========================================================================
    // ASCII generation
    // =========================================================================

    fn generateAsciiForClass(self: *Self, graph: *InheritanceGraph, class_name: []const u8) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```\n");

        // Build tree structure
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        // Find root(s) for this class
        const roots = try self.findRootsForClass(graph, class_name);
        defer self.allocator.free(roots);

        for (roots) |root| {
            try self.writeAsciiTree(graph, root, &visited, 0, true);
        }

        try self.buffer.appendSlice(self.allocator, "```\n");
        return self.buffer.items;
    }

    fn generateAsciiFull(self: *Self, graph: *InheritanceGraph) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```\n");

        const roots = try graph.getRoots();
        defer self.allocator.free(roots);

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        for (roots) |root| {
            try self.writeAsciiTree(graph, root, &visited, 0, true);
            try self.buffer.appendSlice(self.allocator, "\n");
        }

        try self.buffer.appendSlice(self.allocator, "```\n");
        return self.buffer.items;
    }

    fn findRootsForClass(self: *Self, graph: *InheritanceGraph, class_name: []const u8) ![][]const u8 {
        var roots: std.ArrayList([]const u8) = .empty;
        defer roots.deinit(self.allocator);

        var current = class_name;
        var depth: u32 = 0;

        while (depth < self.config.max_depth) {
            const parents = try graph.getParents(current);
            defer self.allocator.free(parents);

            if (parents.len == 0) {
                try roots.append(self.allocator, current);
                break;
            }

            // For simplicity, follow first parent (could be extended for multiple inheritance)
            current = parents[0].parent;
            depth += 1;
        }

        if (roots.items.len == 0) {
            try roots.append(self.allocator, class_name);
        }

        return try roots.toOwnedSlice(self.allocator);
    }

    fn writeAsciiTree(
        self: *Self,
        graph: *InheritanceGraph,
        class_name: []const u8,
        visited: *std.StringHashMap(void),
        indent: u32,
        is_last: bool,
    ) !void {
        if (visited.contains(class_name)) return;
        try visited.put(class_name, {});

        // Write indent
        if (indent > 0) {
            for (0..indent - 1) |_| {
                try self.buffer.appendSlice(self.allocator, "│   ");
            }
            if (is_last) {
                try self.buffer.appendSlice(self.allocator, "└── ");
            } else {
                try self.buffer.appendSlice(self.allocator, "├── ");
            }
        }

        // Write class name
        try self.buffer.appendSlice(self.allocator, class_name);

        // Add abstract marker
        if (graph.nodes.get(class_name)) |node| {
            if (node.is_abstract) {
                try self.buffer.appendSlice(self.allocator, " (abstract)");
            }
            if (node.is_external) {
                try self.buffer.appendSlice(self.allocator, " [external]");
            }
        }

        try self.buffer.appendSlice(self.allocator, "\n");

        // Write children
        const children = try graph.getChildren(class_name);
        defer self.allocator.free(children);

        for (children, 0..) |child, i| {
            const child_is_last = (i == children.len - 1);
            try self.writeAsciiTree(graph, child, visited, indent + 1, child_is_last);
        }
    }

    // =========================================================================
    // PlantUML generation
    // =========================================================================

    fn generatePlantUmlForClass(self: *Self, graph: *InheritanceGraph, class_name: []const u8) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```plantuml\n@startuml\n");

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        try self.writePlantUmlClassHierarchy(graph, class_name, &visited, 0);

        try self.buffer.appendSlice(self.allocator, "@enduml\n```\n");
        return self.buffer.items;
    }

    fn generatePlantUmlFull(self: *Self, graph: *InheritanceGraph) ![]const u8 {
        try self.buffer.appendSlice(self.allocator, "```plantuml\n@startuml\n");

        // Write all class definitions
        var node_iter = graph.nodes.iterator();
        while (node_iter.next()) |entry| {
            try self.writePlantUmlClassDef(entry.value_ptr.*);
        }

        // Write all inheritance relationships
        for (graph.edges.items) |edge| {
            try self.writePlantUmlInheritance(edge);
        }

        try self.buffer.appendSlice(self.allocator, "@enduml\n```\n");
        return self.buffer.items;
    }

    fn writePlantUmlClassHierarchy(
        self: *Self,
        graph: *InheritanceGraph,
        class_name: []const u8,
        visited: *std.StringHashMap(void),
        depth: u32,
    ) !void {
        if (depth > self.config.max_depth) return;
        if (visited.contains(class_name)) return;

        try visited.put(class_name, {});

        // Write class definition
        if (graph.nodes.get(class_name)) |node| {
            try self.writePlantUmlClassDef(node);
        }

        // Write parent relationships and recurse up
        const parents = try graph.getParents(class_name);
        defer self.allocator.free(parents);

        for (parents) |edge| {
            try self.writePlantUmlInheritance(edge);
            try self.writePlantUmlClassHierarchy(graph, edge.parent, visited, depth + 1);
        }

        // Write child relationships and recurse down
        const children = try graph.getChildren(class_name);
        defer self.allocator.free(children);

        for (children) |child| {
            for (graph.edges.items) |edge| {
                if (std.mem.eql(u8, edge.child, child) and std.mem.eql(u8, edge.parent, class_name)) {
                    try self.writePlantUmlInheritance(edge);
                    break;
                }
            }
            try self.writePlantUmlClassHierarchy(graph, child, visited, depth + 1);
        }
    }

    fn writePlantUmlClassDef(self: *Self, node: InheritanceNode) !void {
        if (node.is_abstract) {
            try self.buffer.appendSlice(self.allocator, "abstract ");
        }
        try self.buffer.appendSlice(self.allocator, "class ");
        try self.buffer.appendSlice(self.allocator, node.name);

        // Add template parameters
        if (node.template_params.len > 0) {
            try self.buffer.appendSlice(self.allocator, "<");
            for (node.template_params, 0..) |param, i| {
                if (i > 0) try self.buffer.appendSlice(self.allocator, ", ");
                try self.buffer.appendSlice(self.allocator, param.name);
            }
            try self.buffer.appendSlice(self.allocator, ">");
        }

        // Add members if configured
        if (self.config.show_members and node.public_methods.len > 0) {
            try self.buffer.appendSlice(self.allocator, " {\n");
            for (node.public_methods) |method| {
                try self.buffer.appendSlice(self.allocator, "    +");
                try self.buffer.appendSlice(self.allocator, method.name);
                try self.buffer.appendSlice(self.allocator, "()\n");
            }
            try self.buffer.appendSlice(self.allocator, "}\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "\n");
        }
    }

    fn writePlantUmlInheritance(self: *Self, edge: InheritanceEdge) !void {
        try self.buffer.appendSlice(self.allocator, edge.parent);

        // Use different arrow styles
        if (edge.is_virtual) {
            try self.buffer.appendSlice(self.allocator, " <|.. ");
        } else {
            try self.buffer.appendSlice(self.allocator, " <|-- ");
        }

        try self.buffer.appendSlice(self.allocator, edge.child);
        try self.buffer.appendSlice(self.allocator, "\n");
    }
};

// Tests
test "create inheritance graph" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    try std.testing.expect(graph.nodes.count() == 0);
    try std.testing.expect(graph.edges.items.len == 0);
}

test "add class to graph" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const class = types.Class{
        .name = "Shape",
        .methods = &[_]types.Method{
            .{
                .name = "area",
                .return_type = "double",
                .params = &[_]types.Parameter{},
                .is_pure_virtual = true,
                .access = .public,
            },
        },
    };

    try graph.addClass(class);

    try std.testing.expect(graph.nodes.contains("Shape"));
    const node = graph.nodes.get("Shape").?;
    try std.testing.expect(node.is_abstract);
}

test "add class with inheritance" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const base = types.Class{
        .name = "Shape",
    };

    const derived = types.Class{
        .name = "Circle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    try graph.addClass(base);
    try graph.addClass(derived);

    try std.testing.expect(graph.nodes.contains("Shape"));
    try std.testing.expect(graph.nodes.contains("Circle"));
    try std.testing.expectEqual(@as(usize, 1), graph.edges.items.len);
    try std.testing.expectEqualStrings("Circle", graph.edges.items[0].child);
    try std.testing.expectEqualStrings("Shape", graph.edges.items[0].parent);
}

test "generate mermaid diagram" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const base = types.Class{
        .name = "Shape",
        .methods = &[_]types.Method{
            .{
                .name = "area",
                .return_type = "double",
                .params = &[_]types.Parameter{},
                .is_pure_virtual = true,
                .access = .public,
            },
        },
    };

    const derived = types.Class{
        .name = "Circle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    try graph.addClass(base);
    try graph.addClass(derived);

    var gen = DiagramGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const diagram = try gen.generateFullDiagram(&graph);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "```mermaid") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "classDiagram") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "Shape") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "Circle") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "<|--") != null);
}

test "generate ascii diagram" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const base = types.Class{
        .name = "Shape",
    };

    const derived = types.Class{
        .name = "Circle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    try graph.addClass(base);
    try graph.addClass(derived);

    var gen = DiagramGenerator.initWithConfig(std.testing.allocator, .{ .format = .ascii });
    defer gen.deinit();

    const diagram = try gen.generateFullDiagram(&graph);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "Shape") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "Circle") != null);
}

test "get roots" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const base = types.Class{
        .name = "Shape",
    };

    const derived = types.Class{
        .name = "Circle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    try graph.addClass(base);
    try graph.addClass(derived);

    const roots = try graph.getRoots();
    defer std.testing.allocator.free(roots);

    try std.testing.expectEqual(@as(usize, 1), roots.len);
    try std.testing.expectEqualStrings("Shape", roots[0]);
}

test "get children" {
    var graph = InheritanceGraph.init(std.testing.allocator);
    defer graph.deinit();

    const base = types.Class{
        .name = "Shape",
    };

    const circle = types.Class{
        .name = "Circle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    const rect = types.Class{
        .name = "Rectangle",
        .base_classes = &[_]types.BaseClass{
            .{ .name = "Shape", .access = .public },
        },
    };

    try graph.addClass(base);
    try graph.addClass(circle);
    try graph.addClass(rect);

    const children = try graph.getChildren("Shape");
    defer std.testing.allocator.free(children);

    try std.testing.expectEqual(@as(usize, 2), children.len);
}
