# Stig

Tree-sitter based C/C++ documentation generator with Standardese-compatible features and mdbook output

## Overview

Stig is a documentation generator for C and C++ codebases that parses source files using tree-sitter and extracts documentation from Doxygen-style comments. It generates clean markdown documentation that can be viewed standalone or built into an mdbook.

Unlike traditional documentation generators that rely on libclang, Stig uses tree-sitter for fast, accurate AST-based parsing. This makes it lightweight, portable, and easy to integrate into any build system. Stig aims for feature parity with Standardese while focusing exclusively on Markdown and mdbook output formats.

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
│  │  Grammar  │  │  │   Tags    │  │  │   Table   │  │  │  /Book  │  │
│  └───────────┘  │  └───────────┘  │  └───────────┘  │  └─────────┘  │
└─────────────────┴─────────────────┴─────────────────┴───────────────┘
         │                 │                 │                │
         └─────────────────┴─────────────────┴────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │     stig.toml (Config)      │
                    └─────────────────────────────┘
```

## Features

### Parsing Capabilities

- **Tree-sitter Parsing**: Accurate AST-based extraction of functions, structs, classes, enums, typedefs, and macros
- **C++ Support**: Classes, inheritance, templates, namespaces, concepts, type aliases
- **Attributes**: Parses `[[nodiscard]]`, `[[deprecated]]`, `[[maybe_unused]]` and custom attributes
- **Friend Declarations**: Extracts friend functions and classes
- **Variadic Templates**: Full support for parameter packs (`Args...`)

### Docstring Tags

**Standard Doxygen Tags:**
- `@brief`, `@param`, `@return`, `@throws`, `@see`, `@note`, `@warning`
- `@deprecated`, `@since`, `@author`, `@version`
- `@pre`, `@post`, `@example`, `@code`/`@endcode`

**Template & Return Value Tags:**
- `@tparam` - Template parameter documentation
- `@retval` - Specific return value documentation

**C++ Standard-Style Sections:**
- `@effects`, `@requires`, `@complexity`
- `@remarks`, `@sync`/`@threadsafety`, `@invariant`

**Entity Commands (Standardese-compatible):**
- `@exclude` - Exclude entities from documentation (supports `@exclude return`, `@exclude target`)
- `@group` - Group related functions together with custom headings
- `@synopsis` - Override the displayed function signature
- `@unique_name` - Custom link target names
- `@module` - Logical module organization
- `@entity` - Remote documentation for other entities
- `@file` - File-level documentation
- `@output_section` - Section headers in synopsis
- `@copydoc` - Copy documentation from another entity
- `@ingroup`/`@defgroup` - Group membership

**Command Prefix:**
- Both `@command` and `\command` syntax supported

### Output & Integration

- **mdbook Integration**: Generates complete mdbook structure or works as preprocessor
- **Cross-References**: Automatic linking between types and functions
- **External Links**: Configurable links to cppreference for `std::` types
- **Watch Mode**: Auto-regenerates documentation on file changes
- **Live Preview**: Optional mdbook serve integration

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

## Usage

### Basic Usage

```bash
# Generate markdown to stdout
stig include/mylib.h

# Generate markdown to file
stig include/mylib.h -o api.md

# Generate mdbook structure
stig include/*.h -f mdbook -o docs/

# Generate with custom title
stig include/*.h -f mdbook -o docs/ --title "My Library API"
```

### Watch Mode

```bash
# Watch for changes and regenerate
stig include/*.h -f mdbook -o docs/ --watch

# Watch with live preview (spawns mdbook serve)
stig include/*.h -f mdbook -o docs/ --serve
```

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

Stig looks for `stig.toml` in the current directory.

```toml
title = "My Library API"
output = "docs"
format = "mdbook"
inputs = ["include/*.h", "src/*.h"]
language = "en"
generate_intro = true
grouping = "by_header"  # by_header, by_prefix, or flat
authors = ["Your Name"]

# Filtering (actively applied)
blacklist_namespace = ["detail", "internal", "impl"]
blacklist_pattern = ["*_impl", "test_*"]
extract_private = false
extract_protected = true
```

### Filtering Behavior

**Namespace Blacklist:** Entities in blacklisted namespaces are automatically excluded from documentation. By default, `detail`, `internal`, and `impl` namespaces are blacklisted.

```cpp
namespace mylib::detail {
    void helper();  // Excluded from docs
}

namespace mylib {
    void public_api();  // Included in docs
}
```

**Pattern Blacklist:** Entity names matching glob patterns (with `*` and `?` wildcards) are excluded.

```toml
blacklist_pattern = ["*_impl", "test_*", "internal_*"]
```

## Documentation Examples

### Basic Function Documentation

```cpp
/**
 * @brief Adds two integers.
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 */
int add(int a, int b);
```

### Template Documentation

```cpp
/// @brief Generic container wrapper
/// @tparam T The element type
/// @tparam Allocator Memory allocator (default: std::allocator<T>)
template<typename T, typename Allocator = std::allocator<T>>
class Container { ... };
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

### Synopsis Override

```cpp
/// @brief Process variadic arguments
/// @synopsis void process(Args... args)
template<typename... Args>
void process(Args&&... args);
```

### Excluding Entities

```cpp
/// @exclude
void internal_helper();  // Not in documentation

/// @exclude return
/// @brief Factory function
/// @return Implementation-defined type
auto create_widget();  // Return type shown as "/* see below */"
```

### File-Level Documentation

```cpp
/**
 * @file geometry.hpp
 * @brief Core geometry types and algorithms.
 * @author John Doe
 * @since 1.0.0
 */
```

### Output Sections

```cpp
/// @output_section Getter Functions
int get_x();
int get_y();

/// @output_section Setter Functions
void set_x(int x);
void set_y(int y);
```

## CLI Reference

```
stig [OPTIONS] <INPUT_FILES>...

ARGS:
    <INPUT_FILES>...    C/C++ header files to process

OPTIONS:
    -o, --output <PATH>    Output file or directory (default: stdout)
    -f, --format <FMT>     Output format: markdown, mdbook (default: markdown)
    --title <TITLE>        Book title (for mdbook format)
    -c, --config <FILE>    Config file path (default: stig.toml)
    -w, --watch            Watch for file changes and regenerate
    --serve                Watch mode + spawn mdbook serve for live preview
    -h, --help             Show help message
    -v, --version          Show version information

SUBCOMMANDS:
    preprocessor    Run as mdbook preprocessor (reads JSON from stdin)
```

## Output Structure

When generating mdbook format:

```
docs/
  book.toml
  src/
    SUMMARY.md
    introduction.md
    functions/
      header1.md
      header2.md
    types/
      header1.md
      header2.md
    macros/
      header1.md
```

## Requirements

- Zig 0.14.0+ (for building)
- mdbook (optional, for building generated documentation)

## License

MIT License
