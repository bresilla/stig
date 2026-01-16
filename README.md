# stig

**S**tatic **T**echnical **I**nterface **G**enerator - A modern C/C++ documentation generator written in Zig.

Stig parses C/C++ header files using tree-sitter and generates beautiful mdbook documentation with support for Doxygen-style documentation comments.

## Features

- **Tree-sitter powered parsing** - Fast, accurate C/C++ parsing without requiring compilation
- **Doxygen compatibility** - Supports standard `@param`, `@return`, `@brief` and many more tags
- **Two-stage pipeline** - SARIF intermediate format enables custom tooling integration
- **mdbook output** - Generates clean, searchable documentation books
- **LSP support** - Real-time documentation checking in your editor
- **Documentation linting** - Catch missing documentation, broken references, and style issues
- **Cross-references** - Automatic linking between documented entities
- **External links** - Automatic links to cppreference for `std::` types
- **Flexible grouping** - Organize documentation by header, prefix, module, or flat

## Installation

### Building from Source

Requires Zig 0.15 or later:

```bash
git clone https://github.com/bresilla/stig
cd stig
zig build -Doptimize=ReleaseFast
```

The binary will be at `./zig-out/bin/stig`.

## Quick Start

### 1. Generate SARIF from source files

```bash
# Parse headers and output SARIF to stdout
stig generate include/*.h

# Parse headers and output SARIF to file
stig generate -o docs.sarif include/*.h include/*.hpp
```

### 2. Render mdbook from SARIF

```bash
# Generate mdbook documentation
stig render docs.sarif -o docs/

# Build the book (requires mdbook)
mdbook build docs/
```

### 3. View the documentation

Open `docs/book/index.html` in your browser.

## Commands

### `stig generate`

Parse C/C++ sources and output SARIF documentation model.

```
Usage: stig generate [OPTIONS] <INPUT_FILES>...

Options:
  -o, --output <FILE>    Output SARIF file (default: stdout)
  -c, --config <FILE>    Config file path (default: stig.toml)
  --force                Force full rebuild, ignore cache
  -h, --help             Show help
```

**Examples:**
```bash
stig generate input.h                    # Output to stdout
stig generate -o docs.sarif src/*.h      # Output to file
stig generate -c myconfig.toml *.h       # Use custom config
```

### `stig render`

Generate mdbook documentation from a SARIF file.

```
Usage: stig render [OPTIONS] <SARIF_FILE>

Options:
  -o, --output <DIR>     Output directory for mdbook (required)
  --title <TITLE>        Override book title
  -h, --help             Show help
```

**Examples:**
```bash
stig render docs.sarif -o docs/
stig render docs.sarif -o book/ --title "My API Reference"
```

### `stig check`

Check documentation coverage and quality.

```
Usage: stig check [OPTIONS] <INPUT_FILES>...

Options:
  -o, --output <FILE>       Output SARIF to file (default: compiler output)
  -c, --config <FILE>       Config file path (default: stig.toml)
  --min-coverage <N>        Minimum coverage percentage (0-100)
  --strict                  Treat warnings as errors
  -h, --help                Show help
```

**Output:**
- Without `-o`: Compiler-style output (`file:line:col: severity: message`)
- With `-o`: SARIF format for GitHub code scanning and CI/CD

**Examples:**
```bash
stig check src/*.h                       # Compiler output to terminal
stig check -o check.sarif src/*.h        # SARIF to file
stig check --min-coverage 80 src/*.h     # Fail if < 80% coverage
stig check --strict src/*.h              # Treat warnings as errors
```

### `stig lsp`

Run as LSP server for editor integration.

```bash
stig lsp
```

Provides real-time documentation checking and diagnostics in supported editors (VS Code, Neovim, etc.).

### `stig init`

Initialize a new stig project with default configuration.

```bash
stig init
```

Creates a `stig.toml` configuration file in the current directory.

### `stig test`

Run pre-compiled test binaries with documentation integration.

```bash
stig test ./build/test_*
```

## Configuration

Stig uses a TOML configuration file (`stig.toml`) for project settings.

### Basic Configuration

```toml
# Project title for documentation
title = "My API Reference"

# Output directory
output_dir = "docs"

# Output format: "mdbook" or "markdown"
format = "mdbook"

# Input file patterns (glob patterns)
input_patterns = ["include/**/*.hpp", "include/**/*.h"]

# Language for mdbook
language = "en"

# Grouping strategy: "by_header", "by_prefix", "flat", "by_module"
grouping = "by_header"

# Authors list
authors = ["Your Name"]
```

### Filtering Options

```toml
# Exclude entities in these namespaces
blacklist_namespace = ["detail", "internal", "impl"]

# Exclude entities matching these patterns (glob)
blacklist_pattern = ["*_internal", "*_impl"]

# Extract private members (default: false)
extract_private = false

# Extract protected members (default: true)
extract_protected = true
```

### Lint Options

```toml
[lint]
enabled = true
treat_warnings_as_errors = false

# Maximum length for @brief descriptions
max_brief_length = 80

# Require documentation elements
require_brief = true
require_param_docs = true
require_return_docs = true
require_tparam_docs = true

# Validate cross-references (@see, @copydoc)
check_cross_references = true

# Require period at end of @brief
require_brief_period = false

# Exclude patterns from linting
exclude_patterns = ["*_test.h"]

# Per-rule severity overrides
[[lint.rules]]
code = "W001"           # Missing documentation
severity = "warning"    # Options: ignore, info, warning, error
```

### Coverage Options

```toml
[coverage]
min_coverage = 80
exclude_patterns = ["*_internal.h"]
require_param_docs = true
require_return_docs = true
require_tparam_docs = true
```

### External Documentation Links

```toml
# Link std:: types to cppreference automatically
[[external_docs]]
prefix = "std::"
url_template = "https://en.cppreference.com/w/cpp/$$"

[[external_docs]]
prefix = "boost::"
url_template = "https://www.boost.org/doc/libs/release/doc/html/$$"
```

### Module Organization

```toml
# Group documentation into logical modules
[[modules]]
name = "core"
patterns = ["include/core/*.hpp"]
title = "Core Module"
description = "Core functionality"

[[modules]]
name = "utils"
patterns = ["include/utils/*.hpp"]
title = "Utilities"
description = "Utility functions and helpers"
```

### Output Options

```toml
[output]
show_source_location = true
show_access_specifiers = true
code_language = "cpp"

# Synopsis style: full, compact, minimal
synopsis_style = "full"
```

### Godbolt Integration

```toml
[godbolt]
enabled = true
compiler = "g132"              # GCC 13.2
options = "-O2 -std=c++20"
link_text = "Run on Compiler Explorer"
```

### Resource Limits

```toml
[limits]
max_file_size = 10485760       # 10 MB
max_include_size = 1048576     # 1 MB
max_json_size = 104857600      # 100 MB
```

## Documentation Syntax

Stig supports Doxygen-style documentation comments with both `@` and `\` command prefixes.

### Comment Styles

```cpp
/**
 * @brief Block comment style
 * @param x Parameter description
 */
void function(int x);

/// Triple-slash style
/// @brief Brief description
void another_function();

//! Alternative triple-slash style
//! @param y Parameter description
void yet_another(int y);
```

### Basic Tags

| Tag | Description |
|-----|-------------|
| `@brief` | Brief one-line description |
| `@details` | Detailed description |
| `@param name` | Parameter documentation |
| `@return` | Return value description |
| `@tparam name` | Template parameter documentation |

### Code Examples

| Tag | Description |
|-----|-------------|
| `@code` / `@endcode` | Code block |
| `@snippet file id` | Include code snippet from file |
| `@example` | Example code |

### Semantic Documentation

| Tag | Description |
|-----|-------------|
| `@pre` | Precondition |
| `@post` | Postcondition |
| `@throws type` | Exception documentation |
| `@retval value` | Specific return value documentation |
| `@requires` | Semantic requirements |
| `@effects` | Effects description (C++ standard style) |
| `@complexity` | Time/space complexity |
| `@invariant` | Class invariant |

### Cross-References

| Tag | Description |
|-----|-------------|
| `@see target` | See also reference |
| `@sa target` | Alias for @see |
| `@ref target` | Cross-reference link |
| `@copydoc target` | Copy documentation from another entity |

### Metadata

| Tag | Description |
|-----|-------------|
| `@author` | Author information |
| `@version` | Version string |
| `@since` | Since version |
| `@date` | Date information |
| `@copyright` | Copyright notice |
| `@deprecated` | Deprecation notice |

### Notes and Warnings

| Tag | Description |
|-----|-------------|
| `@note` | Note/remark |
| `@warning` | Warning message |
| `@attention` | Attention notice |
| `@important` | Important notice |
| `@todo` | TODO item |
| `@bug` | Known bug |

### Organization

| Tag | Description |
|-----|-------------|
| `@file` | File-level documentation |
| `@ingroup name` | Add to documentation group |
| `@defgroup name title` | Define a documentation group |
| `@group name heading` | Group related entities |
| `@module name` | Logical module membership |
| `@exclude` | Exclude from documentation |

### Advanced

| Tag | Description |
|-----|-------------|
| `@synopsis` | Override generated synopsis |
| `@unique_name` | Custom link target name |
| `@entity target` | Remote documentation for another entity |
| `@output_section` | Section header in synopsis |
| `@mermaid` / `@endmermaid` | Mermaid diagram |
| `@threadsafety` / `@sync` | Thread safety documentation |

### Example

```cpp
/**
 * @file math.hpp
 * @brief Mathematical utility functions
 * @author John Doe
 * @version 1.0.0
 */

/**
 * @brief Computes the factorial of a non-negative integer
 *
 * Uses an iterative algorithm to compute n!.
 *
 * @tparam T Integral type (must be unsigned)
 * @param n The input value (must be >= 0)
 * @return The factorial n!
 *
 * @pre n >= 0
 * @post result >= 1
 * @throws std::overflow_error if result would overflow
 *
 * @complexity O(n)
 * @since 1.0
 *
 * @code
 * auto result = factorial(5);  // returns 120
 * @endcode
 *
 * @see combination, permutation
 */
template<typename T>
T factorial(T n);
```

## Lint Rules

Stig includes a documentation linter with the following rules:

| Code | Severity | Description |
|------|----------|-------------|
| `W001` | Warning | Missing documentation |
| `W002` | Warning | Empty @brief description |
| `W003` | Warning | Missing @param for parameter |
| `W004` | Warning | Missing @return for non-void function |
| `W005` | Warning | @return present for void function |
| `W006` | Warning | Missing @tparam for template parameter |
| `W007` | Warning | @brief exceeds max length |
| `W008` | Warning | Duplicate @param documentation |
| `W009` | Warning | Empty @param description |
| `W010` | Warning | Duplicate @tparam documentation |
| `W011` | Warning | Empty @tparam description |
| `W012` | Warning | @brief missing period at end |
| `E001` | Error | Unknown @param name |
| `E002` | Error | Unknown @tparam name |
| `E003` | Error | Unresolved @see/@copydoc reference |

Configure rule severity in `stig.toml`:

```toml
[[lint.rules]]
code = "W001"
severity = "ignore"    # Disable this rule

[[lint.rules]]
code = "W007"
severity = "error"     # Make this an error
```

## Supported C/C++ Constructs

Stig extracts documentation from:

- **Functions** - Free functions, static functions, inline functions
- **Classes** - Class definitions with methods and members
- **Structs** - Struct definitions with fields
- **Enums** - Enum definitions with values
- **Typedefs** - Type aliases
- **Type Aliases** - C++11 `using` declarations
- **Macros** - Function-like and object-like macros
- **Templates** - Function and class templates
- **Concepts** - C++20 concepts
- **Namespaces** - Namespace-qualified names

## Editor Integration

### VS Code

Install the stig LSP extension or configure a generic LSP client:

```json
{
  "languageServerExample.serverPath": "stig",
  "languageServerExample.serverArgs": ["lsp"]
}
```

### Neovim (nvim-lspconfig)

```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

configs.stig = {
  default_config = {
    cmd = {'stig', 'lsp'},
    filetypes = {'c', 'cpp'},
    root_dir = lspconfig.util.root_pattern('stig.toml', '.git'),
  }
}

lspconfig.stig.setup{}
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Documentation Check
on: [push, pull_request]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install stig
        run: |
          # Install stig (adjust for your setup)

      - name: Check documentation
        run: stig check -o results.sarif --min-coverage 80 src/*.h

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: results.sarif
```

### GitLab CI

```yaml
docs:check:
  script:
    - stig check -o check.sarif --strict src/*.h
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## SARIF Output Format

Stig's SARIF output includes custom extensions for the documentation model:

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [{
    "tool": {
      "driver": {
        "name": "stig",
        "version": "0.0.2"
      }
    },
    "results": [],
    "properties": {
      "stig:version": "1.0",
      "stig:config": {
        "title": "API Reference",
        "grouping": "by_header"
      },
      "stig:modules": [
        {
          "name": "math.h",
          "functions": [...],
          "classes": [...],
          "structs": [...],
          "enums": [...],
          "typedefs": [...],
          "macros": [...]
        }
      ]
    }
  }]
}
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please read CONTRIBUTING.md for guidelines.

## Acknowledgments

- [tree-sitter](https://tree-sitter.github.io/) - Parsing library
- [mdbook](https://rust-lang.github.io/mdBook/) - Book generation
- [Zig](https://ziglang.org/) - Implementation language
