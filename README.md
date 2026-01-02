# Stig

**Tree-sitter based C/C++ documentation generator with Doxygen-style comments and mdbook output**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.14.0+-orange.svg)](https://ziglang.org/)

## Overview

Stig is a modern documentation generator for C and C++ codebases that parses source files using tree-sitter and extracts documentation from Doxygen-style comments. It generates clean markdown documentation that can be viewed standalone, built into an mdbook, or exported as JSON/HTML.

Unlike traditional documentation generators that rely on libclang, Stig uses tree-sitter for fast, accurate AST-based parsing. This makes it lightweight, portable, and easy to integrate into any build system.

### Key Features

- 🚀 **Fast Tree-sitter Parsing** - No libclang dependency
- 📚 **Multiple Output Formats** - Markdown, mdbook, JSON, HTML
- 🔗 **Smart Cross-References** - Automatic linking with `@ref` tags
- 📊 **Coverage Reports** - Track documentation completeness
- 🔍 **Linting** - Validate documentation quality
- 👀 **Watch Mode** - Auto-regenerate on file changes
- 🔧 **CMake Integration** - Easy build system integration
- 🎯 **GitHub Actions** - CI/CD ready
- 🌐 **Compiler Explorer** - Interactive code examples

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                              STIG                                    │
├─────────────────┬─────────────────┬─────────────────┬───────────────┤
│   Tree-sitter   │    Docstring    │     Cross-      │    Output     │
│     Parser      │    Extractor    │   Reference     │   Generator   │
│                 │                 │                 │               │
│  ┌───────────┐  │  ┌───────────┐  │  ┌───────────┐  │  ┌─────────┐  │
│  │  C/C++    │  │  │  Doxygen  │  │  │  Symbol   │  │  │Markdown │  │
│  │  Grammar  │  │  │   Tags    │  │  │   Table   │  │  │ /mdbook │  │
│  └───────────┘  │  └───────────┘  │  └───────────┘  │  │  JSON   │  │
│                 │                 │                 │  │  HTML   │  │
│                 │                 │                 │  └─────────┘  │
└─────────────────┴─────────────────┴─────────────────┴───────────────┘
         │                 │                 │                │
         └─────────────────┴─────────────────┴────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │     stig.toml (Config)      │
                    └─────────────────────────────┘
```

## Installation

### Build from Source

Requires Zig 0.14.0 or later.

```bash
git clone https://github.com/bresilla/stig.git
cd stig
zig build -Doptimize=ReleaseFast
```

The binary will be at `zig-out/bin/stig`.

### Development Environment (Nix + Devbox)

```bash
curl -fsSL https://get.jetpack.io/devbox | bash
cd stig
devbox shell
```

## Quick Start

```bash
# Generate markdown to stdout
stig include/mylib.h

# Generate mdbook structure
stig generate include/*.h -f mdbook -o docs/ --title "My Library API"

# Check documentation coverage (human-readable)
stig check include/*.h

# Check with CI/CD-friendly output (file:line:col: severity: message)
stig check -f compiler include/*.h

# Watch mode with live preview
stig generate include/*.h -f mdbook -o docs/ --serve
```

> **Note:** Following standardese and doxygen conventions, stig only processes **header files** (`.h`, `.hpp`, `.hxx`, `.hh`). Implementation files (`.cpp`, `.cc`, `.cxx`) are automatically skipped, as documentation should be in headers where declarations are, not in source files where implementations are.

## Features

### Parsing Capabilities

- **Tree-sitter Parsing**: Accurate AST-based extraction of functions, structs, classes, enums, typedefs, and macros
- **C++ Support**: Classes, inheritance, templates, namespaces, concepts, type aliases
- **C++20 Features**: Concepts, requires clauses, spaceship operator, consteval
- **Attributes**: Parses `[[nodiscard]]`, `[[deprecated]]`, `[[maybe_unused]]` and custom attributes
- **Friend Declarations**: Extracts friend functions and classes
- **Variadic Templates**: Full support for parameter packs (`Args...`)
- **Operator Overloading**: All C++ operators including conversion operators

### Docstring Tags

**Standard Doxygen Tags:**
- `@brief`, `@details` - Brief and detailed descriptions
- `@param`, `@tparam` - Parameter and template parameter documentation
- `@return`, `@retval` - Return value documentation
- `@throws`, `@exception` - Exception documentation
- `@see`, `@note`, `@warning`, `@attention` - Cross-references and notices
- `@deprecated`, `@since`, `@author`, `@version` - Metadata
- `@pre`, `@post` - Preconditions and postconditions
- `@example`, `@code`/`@endcode` - Code examples

**Advanced Tags:**
- `@ref` - Explicit cross-references with optional display text
- `@snippet` - Include external code snippets
- `@test` - Link to test cases
- `@todo`, `@bug` - Track issues (generates separate pages)
- `@copydoc` - Copy documentation from another entity
- `@mermaid`/`@endmermaid` - Embed Mermaid diagrams

**C++ Standard-Style Sections:**
- `@effects`, `@requires`, `@complexity`
- `@remarks`, `@sync`/`@threadsafety`, `@invariant`

**Entity Commands (Standardese-compatible):**
- `@exclude` - Exclude entities from documentation (supports `@exclude return`, `@exclude target`)
- `@group` - Group related functions together with custom headings
- `@synopsis` - Override the displayed function signature
- `@unique_name` - Custom link target names for overloads
- `@module` - Logical module organization
- `@entity` - Remote documentation for other entities
- `@file` - File-level documentation
- `@output_section` - Section headers in synopsis
- `@ingroup`/`@defgroup` - Group membership
- `@page`, `@mainpage` - Custom documentation pages

**Command Prefix:**
- Both `@command` and `\command` syntax supported

### Output Formats

#### Markdown (`-f markdown`)
Single markdown file with all documentation. Perfect for GitHub wikis or simple projects.

```bash
stig include/*.h -o api.md
```

#### mdbook (`-f mdbook`)
Complete mdbook structure with:
- Automatic SUMMARY.md generation
- Organized by modules/files
- Cross-reference links
- Alphabetical index
- Custom pages support

```bash
stig include/*.h -f mdbook -o docs/ --title "My API"
mdbook build docs
```

#### JSON (`-f json`)
Structured JSON output for custom processing or integration with other tools.

```bash
stig include/*.h -f json -o api.json
```

#### HTML (`-f html`)
Single-page HTML documentation with styling.

```bash
stig include/*.h -f html -o api.html --title "My API"
```

### Cross-References

Automatic linking between types and functions:

```cpp
/**
 * @brief Processes a point
 * @param p A @ref Point to process
 * @return See @ref Result for details
 * 
 * This function uses @ref Point::transform() internally.
 * For more info, see @ref geometry_page "the geometry guide".
 */
Result process(Point p);
```

Generates: `[Point](#point)`, `[the geometry guide](geometry_page.md)`

### Documentation Checking

The `stig check` command combines coverage analysis and linting into a single command with multiple output formats:

**Human-Readable Report (default):**
```bash
stig check include/*.h
```

Output:
```
Documentation Coverage Report
=============================
Overall: 85% (42/50 entities documented)

By Type:
  Functions:    90% (27/30) [3 missing params, 2 missing returns]
  Classes:      80% (8/10)
  Structs:      100% (4/4)

Missing Documentation:
  include/api.h:
    - process() [line 42] - missing @param for 'flags'
    - validate() [line 58] - missing @return
```

**Compiler-Style Output (for CI/CD):**
```bash
stig check -f compiler include/*.h
```

Output:
```
include/api.h:42:1: warning: missing @param for 'flags' 'process' (function)
include/api.h:58:1: warning: missing @return 'validate' (function)
include/api.h:75:1: warning: no documentation 'helper' (function)

stig: 3 documentation issue(s) found
stig: coverage 85% (42/50 entities documented)
```

**JSON Output (for tooling):**
```bash
stig check -f json include/*.h
```

**Additional Options:**
```bash
# Set minimum coverage threshold (exit code 2 if below)
stig check --min-coverage 80 include/*.h

# Treat warnings as errors (exit code 2 if warnings found)
stig check --strict include/*.h
```

**Exit Codes:**
- `0` - All checks passed
- `1` - Errors found (invalid references, etc.)
- `2` - Warnings found (with `--strict`) or coverage below threshold

Checks for:
- Missing `@brief` descriptions
- Undocumented parameters
- Missing return documentation
- Broken cross-references
- Brief description length

### Watch Mode

Auto-regenerate documentation on file changes:

```bash
# Watch and regenerate
stig include/*.h -f mdbook -o docs/ --watch

# Watch with live preview (spawns mdbook serve)
stig include/*.h -f mdbook -o docs/ --serve
```

### CMake Integration

Add to your `CMakeLists.txt`:

```cmake
find_package(Stig REQUIRED)

stig_add_docs(
    TARGET my_docs
    SOURCES include/*.hpp
    OUTPUT docs
    FORMAT mdbook
    TITLE "My Library API"
)
```

Then build:
```bash
cmake --build . --target my_docs
```

See [cmake/README.md](cmake/README.md) for details.

### GitHub Actions

Use the provided action in your workflow:

```yaml
- name: Generate Documentation
  uses: ./.github/actions/stig-docs
  with:
    input: 'include/*.hpp'
    output: 'docs'
    format: 'mdbook'
    coverage: 'true'
    coverage-threshold: '80'
```

See [.github/actions/stig-docs/README.md](.github/actions/stig-docs/README.md) for details.

### mdbook Preprocessor

Add to your `book.toml`:

```toml
[preprocessor.stig]
command = "stig preprocessor"
```

Use in markdown files:

```markdown
{{#stig api ../include/mylib.h}}
{{#stig function my_function}}
{{#stig struct MyStruct}}
```

## Configuration

Create `stig.toml` in your project root:

```toml
title = "My Library API"
output = "docs"
format = "mdbook"
inputs = ["include/*.h", "src/*.h"]
language = "en"
generate_intro = true
grouping = "by_module"  # by_header, by_prefix, by_module, or flat
authors = ["Your Name"]

# Filtering
blacklist_namespace = ["detail", "internal", "impl"]
blacklist_pattern = ["*_impl", "test_*"]
extract_private = false
extract_protected = true

# External documentation links
[[external_docs]]
prefix = "std::"
url_template = "https://en.cppreference.com/w/cpp/$$"

# Coverage options
[coverage]
min_coverage = 80
require_param_docs = true
require_return_docs = true

# Output options
[output]
show_source_location = true
code_language = "cpp"

# Module organization
[[modules]]
name = "Core"
patterns = ["include/core/*.hpp"]
title = "Core Components"

[[modules]]
name = "Utils"
patterns = ["include/util/*.hpp"]
title = "Utility Functions"
```

### Filtering Behavior

**Namespace Blacklist:** Entities in blacklisted namespaces are automatically excluded.

```cpp
namespace mylib::detail {
    void helper();  // Excluded from docs
}

namespace mylib {
    void public_api();  // Included in docs
}
```

**Pattern Blacklist:** Entity names matching glob patterns are excluded.

```toml
blacklist_pattern = ["*_impl", "test_*", "internal_*"]
```

## Documentation Examples

### Basic Function

```cpp
/**
 * @brief Adds two integers.
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 */
int add(int a, int b);
```

### Template Class

```cpp
/// @brief Generic container wrapper
/// @tparam T The element type
/// @tparam Allocator Memory allocator (default: std::allocator<T>)
template<typename T, typename Allocator = std::allocator<T>>
class Container {
public:
    /// @brief Adds an element
    /// @param value The value to add
    void push(const T& value);
};
```

### Cross-References

```cpp
/**
 * @brief Processes a @ref Point using @ref Transform
 * @param p Input @ref Point "point"
 * @param t The @ref Transform to apply
 * @return Transformed point
 * 
 * See @ref geometry_page for more details.
 */
Point process(Point p, Transform t);
```

### Grouping Functions

```cpp
/// @group getters Getter Functions
/// @brief Gets the X coordinate
int get_x();

/// @group getters
/// @brief Gets the Y coordinate
int get_y();

/// @group setters Setter Functions
/// @brief Sets the X coordinate
void set_x(int x);
```

### Code Examples

```cpp
/**
 * @brief Calculates factorial
 * @param n Input number
 * @return Factorial of n
 * 
 * @code{.cpp}
 * int result = factorial(5);  // Returns 120
 * @endcode
 */
int factorial(int n);
```

### External Snippets

```cpp
/**
 * @brief Example usage
 * @snippet examples/basic.cpp basic_usage
 */
void example();
```

In `examples/basic.cpp`:
```cpp
//! [basic_usage]
Point p{10, 20};
p.transform(Matrix::identity());
//! [basic_usage]
```

### Custom Pages

```cpp
/**
 * @page getting_started Getting Started Guide
 * 
 * ## Installation
 * 
 * Download and install the library...
 * 
 * ## Basic Usage
 * 
 * See @ref Point and @ref Transform for core types.
 */
```

### TODO/Bug Tracking

```cpp
/// @brief Process data
/// @todo Optimize for large datasets
/// @bug Crashes with empty input (issue #123)
void process(const Data& data);
```

Generates separate `TODO.md` and `BUGS.md` pages.

### Test References

```cpp
/**
 * @brief Validates input
 * @test test_validate_basic
 * @test test_validate_edge_cases
 */
bool validate(const Input& input);
```

Generates `TESTS.md` with links to test files.

## CLI Reference

```
stig <COMMAND> [OPTIONS] <INPUT_FILES>...

COMMANDS:
    generate        Generate documentation (default if no subcommand)
    check           Check documentation coverage and quality
    preprocessor    Run as mdbook preprocessor
    help            Show help message
    version         Show version information

GENERATE OPTIONS:
    -o, --output <PATH>    Output file or directory (default: stdout)
    -f, --format <FMT>     Output format: markdown, mdbook, json, html
    --title <TITLE>        Book title (for mdbook/html format)
    -c, --config <FILE>    Config file path (default: stig.toml)
    -w, --watch            Watch for file changes and regenerate
    --serve                Watch mode + spawn mdbook serve for live preview
    --force                Force full rebuild, ignore cache
    -h, --help             Show help message

CHECK OPTIONS:
    -c, --config <FILE>    Config file path (default: stig.toml)
    -f, --format <FMT>     Output format: human, compiler, json
    --min-coverage <N>     Minimum coverage percentage (0-100)
    --strict               Treat warnings as errors
    -h, --help             Show help message

GLOBAL OPTIONS:
    -h, --help             Show help (use 'stig <command> --help' for details)
    -v, --version          Show version information

EXAMPLES:
    stig input.h                              # Generate markdown to stdout
    stig generate input.h -o output.md        # Generate to file
    stig generate src/*.h -f mdbook -o docs/  # Generate mdbook
    stig check src/*.h                        # Human-readable coverage report
    stig check -f compiler src/*.h            # CI/CD-friendly output
    stig check --min-coverage 80 src/*.h      # Fail if coverage < 80%
    stig check --strict src/*.h               # Treat warnings as errors
```

## Output Structure

When generating mdbook format:

```
docs/
  book.toml
  src/
    SUMMARY.md
    introduction.md
    modules/
      core.md
      utils.md
    appendix/
      INDEX.md          # Alphabetical index
      TODO.md           # TODO items
      BUGS.md           # Bug tracking
      TESTS.md          # Test references
      INCLUDES.md       # Include dependencies
```

## Advanced Features

### Include Dependency Graphs

Automatically generates include dependency diagrams:

```mermaid
graph TD
    vector.hpp --> types.hpp
    vector.hpp --> geometry.hpp
    geometry.hpp --> types.hpp
```

### Inheritance Diagrams

Class hierarchies visualized with Mermaid:

```mermaid
classDiagram
    Shape <|-- Circle
    Shape <|-- Rectangle
    Shape : +area()
    Circle : +radius
    Rectangle : +width
    Rectangle : +height
```

### Call Graphs

Function call relationships (infrastructure ready):

```mermaid
graph TD
    main --> initialize
    main --> process
    process --> validate
    process --> transform
```

### Compiler Explorer Integration

Add interactive "Run on Compiler Explorer" links to code examples (configurable):

```toml
[godbolt]
enabled = true
compiler = "g132"
options = "-O2 -std=c++20"
```

## Requirements

- **Build**: Zig 0.14.0+
- **Runtime**: None (static binary)
- **Optional**: mdbook (for building generated documentation)

## Project Status

**22/24 planned features complete (91.7%)**

✅ Implemented:
- Core parsing (C/C++, templates, concepts)
- All output formats (markdown, mdbook, JSON, HTML)
- Doxygen tag support (50+ tags)
- Cross-references (@ref)
- Coverage & linting
- Watch mode
- CMake integration
- GitHub Actions
- Godbolt integration
- Call graph infrastructure
- Include dependency graphs
- Inheritance diagrams
- Custom pages
- Module organization
- TODO/Bug tracking
- Test references
- External code snippets

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- Powered by [tree-sitter](https://tree-sitter.github.io/)
- Inspired by [Standardese](https://github.com/standardese/standardese)
- Compatible with [Doxygen](https://www.doxygen.nl/) syntax
