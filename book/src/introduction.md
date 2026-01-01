# Stig

**C/C++ documentation generator using tree-sitter parsing**

Stig parses C and C++ source files using tree-sitter and extracts documentation from Doxygen-style comments. It generates clean markdown documentation that can be viewed standalone or built into an mdbook.

## Features

- **Tree-sitter Parsing** - Accurate AST-based extraction of functions, structs, classes, enums, typedefs, and macros
- **Doxygen Support** - Parses `/** */`, `///`, `@param`, `@return`, `@brief`, `@tparam`, `@code` and other tags
- **C++ Templates** - Full support for template classes, functions, and parameters
- **mdbook Integration** - Generates complete mdbook structure or works as an mdbook preprocessor
- **Watch Mode** - Auto-regenerates documentation on file changes with optional live preview
- **Cross-References** - Automatic linking between types and functions

## Quick Start

```bash
# Generate markdown to stdout
stig include/mylib.h

# Generate mdbook structure
stig include/*.h -f mdbook -o docs/

# Watch with live preview
stig include/*.h -f mdbook -o docs/ --serve
```

## Example Output

Given this C++ header:

```cpp
/**
 * @brief A 2D point in Cartesian coordinates
 * @tparam T The scalar type
 */
template<typename T>
class Point2 {
public:
    /**
     * @brief Constructs a point from coordinates
     * @param x X coordinate
     * @param y Y coordinate
     */
    constexpr Point2(T x, T y);
    
    /// Gets the x coordinate
    T x() const;
    
    /// Gets the y coordinate  
    T y() const;
};
```

Stig generates structured markdown with:
- Template parameter documentation
- Method signatures with return types
- Grouped sections (Constructors, Methods, Operators)
- Cross-reference links to related types
