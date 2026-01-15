# Stig

[![Version](https://img.shields.io/badge/version-0.0.2-blue.svg)](VERSION)
[![Zig](https://img.shields.io/badge/Zig-0.15.0+-f1a73e.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Stig** is a modern, fast, and flexible documentation generator for C and C++ codebases. Built with Zig and powered by Tree-sitter, it extracts documentation from Doxygen-style comments in header files and produces multiple output formats including Markdown, mdBook, and JSON.

## Table of Contents

- [Overview](#overview)
- [Why Stig?](#why-stig)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Configuration](#configuration)
- [Doxygen Tags](#doxygen-tags)
- [Output Formats](#output-formats)
- [Language Server Protocol](#language-server-protocol)
- [Coverage & Linting](#coverage--linting)
- [Watch Mode](#watch-mode)
- [Integration](#integration)
- [Advanced Features](#advanced-features)
- [Examples](#examples)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

---

## Overview

Stig parses C and C++ header files using Tree-sitter grammars, extracting Doxygen-style documentation comments and associating them with declarations. Unlike traditional documentation generators that rely on libclang or complex build systems, Stig is:

- **Header-first**: Only processes header files (`.h`, `.hpp`, `.hxx`, `.hh`, `.H`), ensuring documentation stays alongside declarations
- **Fast**: Written in Zig with zero-copy parsing and efficient memory management
- **Modern**: Supports C++20 features including concepts, requires clauses, and templates
- **Flexible**: Multiple output formats, cross-reference resolution, and extensible via configuration
- **Developer-friendly**: LSP integration for real-time diagnostics in editors, watch mode for live updates

Stig is particularly suited for modern C++ projects that value documentation as a first-class citizen, providing both automated generation and interactive tooling for maintaining documentation quality.

---

## Why Stig?

### The Problem

Existing C++ documentation tools have significant limitations:

1. **Doxygen**: Heavy, slow, complex configuration, HTML-centric output, lacks modern integrations
2. **Standardese**: libclang dependency, Python-based, limited C++20 support, inactive development
3. **Sphinx/Breathe**: Requires Python, complex setup, slow for large codebases

### The Stig Solution

Stig addresses these limitations with a fresh approach:

| Feature | Doxygen | Standardese | Stig |
|---------|---------|-------------|------|
| Language | C++/Python | Python | Zig |
| Parser | Custom | libclang | Tree-sitter |
| Build System | CMake | None | Zig/Nix |
| LSP Support | ❌ | ❌ | ✅ |
| Watch Mode | ❌ | ❌ | ✅ |
| JSON Output | XML only | ✅ | ✅ |
| mdBook Support | ❌ | ❌ | ✅ |
| Speed | Slow | Medium | Fast |
| Dependencies | Many | Few | Minimal |

### Key Differentiators

- **No libclang dependency**: Uses Tree-sitter grammars for lighter weight and better cross-platform support
- **Header-only philosophy**: Documentation lives in headers, not implementation files
- **Modern C++**: Full support for C++20 concepts, requires clauses, and template syntax
- **Editor integration**: LSP server provides real-time feedback and code actions
- **Incremental builds**: Smart caching and file watching for fast iteration
- **Flexible output**: JSON intermediate format enables custom rendering pipelines

---

## Key Features

### Core Functionality

#### 🎯 Header-First Parsing
- Processes only header files (`.h`, `.hpp`, `.hxx`, `.hh`, `.H`)
- Skips implementation files automatically (`.cpp`, `.cc`, `.cxx`)
- Respects `#include` directives for accurate symbol resolution

#### 🌲 Tree-sitter Powered
- Grammar-based parsing for accurate syntax recognition
- Support for C and C++ languages with full grammar coverage
- Fast, incremental parsing with syntax tree caching

#### 📚 Multiple Output Formats

**Markdown**
- Single-file output with TOC and index
- Cross-reference links and code highlighting
- Suitable for documentation websites and README files

**mdBook**
- Multi-page structure with navigation
- Chapter organization by header or module
- Search, code highlighting, and responsive design
- Ready for GitHub Pages or static hosting

**JSON**
- Structured data for custom processing
- Version 2 schema with full document model
- Enables rendering pipelines and tooling integration

**SARIF**
- Static Analysis Results Interchange Format
- GitHub Advanced Security integration
- Code scanning and CI/CD workflows

#### 🔗 Cross-References
- `@ref` tag for explicit symbol references
- Automatic link resolution within documentation
- External documentation links (e.g., std:: to cppreference.com)
- `@copydoc` for documentation inheritance

#### 🎨 Rich Documentation Elements
- Code blocks with syntax highlighting (`@code`/`@endcode`)
- Mermaid diagrams (`@mermaid`/`@endmermaid`)
- Snippet inclusion from external files (`@snippet`)
- Godbolt/Compiler Explorer integration for live examples

### Language Features

#### C++ Support
- **Templates**: Full parsing of template declarations and parameters
- **Concepts**: C++20 concept support with `requires` clause extraction
- **Classes**: Full class hierarchy, methods, and member documentation
- **Inheritance**: Base class rendering with access specifiers
- **Virtual Functions**: `override`, `final`, `pure virtual` specifiers
- **Namespaces**: Nested namespace tracking and organization
- **Attributes**: C++ attribute parsing and documentation
- **Enums**: Scoped and unscoped enum support
- **Unions**: Union type parsing and documentation
- **Friends**: Friend declaration parsing
- **Type Aliases**: `typedef` and `using` alias support

#### C Support
- All standard C constructs
- Function pointers
- Nested structs
- Typedefs
- Macros (with documentation support)

### Developer Tools

#### 🖥️ Language Server Protocol
- **Real-time diagnostics**: Immediate feedback on documentation issues
- **Auto-completion**: 37 Doxygen tags with snippets
- **Code actions**: Quick fixes for common issues
  - Generate documentation stubs
  - Add missing `@param` tags
  - Add missing `@return` tags
  - Fix parameter name mismatches
- **Incremental sync**: Efficient document updates

#### 📊 Coverage Analysis
- **Documentation coverage**: Percentage of documented entities
- **Per-type breakdown**: Classes, functions, variables, etc.
- **Parameter coverage**: `@param` tag presence
- **Return coverage**: `@return` tag presence for non-void functions
- **Template parameter coverage**: `@tparam` tag presence
- **Configurable thresholds**: Set minimum coverage requirements

#### 🔍 Linting
- **Missing documentation**: Detect undocumented entities
- **Brief checks**: Ensure `@brief` is present and well-formed
- **Parameter validation**: Detect missing or duplicate `@param` tags
- **Return validation**: Detect missing `@return` for non-void functions
- **Empty descriptions**: Flag empty or whitespace-only descriptions
- **Cross-reference validation**: Verify `@ref` and `@copydoc` targets exist
- **Parameter name matching**: Validate `@param` names match actual parameters
- **Configurable severity**: Per-rule configuration (ignore/info/warning/error)

#### 👁️ Watch Mode
- **Native file watching**: Inotify on Linux, polling fallback on other platforms
- **Incremental builds**: Only rebuild changed files
- **Ignore patterns**: Filter out build artifacts and VCS directories
- **Automatic mdBook serve**: Live preview with `--serve` flag
- **Dependency tracking**: Rebuild when included headers change

#### 🧪 Testing Integration
- **Built-in test framework**: Lightweight C++ test macros
- **CMake integration**: Seamless integration with existing build systems
- **Coverage tracking**: Track which symbols are tested
- **Test-to-symbol mapping**: Link tests to documented symbols

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         Stig Architecture                        │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   CLI / LSP  │    │   Parser    │    │   Output     │
│   Layer      │    │   Engine     │    │   Generators │
└──────────────┘    └──────────────┘    └──────────────┘
        │                     │                     │
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Argument    │    │ Tree-sitter  │    │   Markdown   │
│  Parsing     │    │   Grammars   │    │   Renderer   │
└──────────────┘    └──────────────┘    └──────────────┘
                           │
                           │
                           ▼
                  ┌──────────────┐
                  │  Docstring   │
                  │  Extractor   │
                  └──────────────┘
                           │
                           ▼
                  ┌──────────────┐
                  │   Symbol     │
                  │   Table     │
                  └──────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Coverage   │  │    Lint      │  │   Cross-     │
│   Analyzer   │  │   Engine     │  │   Reference  │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Component Breakdown

#### 1. Core Parser Engine (`src/parser/`)

**C Parser** (`c.zig` - ~1,200 lines)
- Tree-sitter C grammar integration
- Function, struct, enum, and typedef parsing
- Macro documentation extraction
- File-level and custom page documentation

**C++ Parser** (`cpp.zig` - ~2,800 lines)
- Tree-sitter C++ grammar integration
- Template parsing with parameter extraction
- Class hierarchy tracking
- Concept and `requires` clause extraction
- Virtual function specifier detection
- Namespace and access specifier handling

**Common Utilities** (`common.zig`)
- Shared parsing logic
- AST traversal helpers
- Source code utilities

#### 2. Docstring Extraction (`src/docstring/`)

**Extractor** (`extractor.zig` - ~2,300 lines)
- Doxygen tag parsing (`@` and `\` prefixes)
- Multi-line continuation support
- Escaped character handling (`@@`, `\\`)
- Tag content extraction
- Format detection (Doxygen, triple-slash, markdown)

**Include Processor** (`includes.zig`)
- `@include` directive resolution
- Snippet extraction from external files
- Multi-language comment style support

#### 3. Output Generation (`src/output/`)

**Markdown Generator** (`markdown.zig` - ~3,000 lines)
- Single-file markdown output
- Table of contents generation
- Code block formatting
- Cross-reference link resolution

**mdBook Generator** (`mdbook.zig` - ~2,100 lines)
- Multi-page book structure
- Chapter organization (by header, module, prefix, or flat)
- `book.toml` generation
- `SUMMARY.md` construction

**JSON Pipeline** (`json/`)
- **Generator** (`generator.zig` - ~2,300 lines): JSON v2 output
- **Reader** (`reader.zig` - ~1,200 lines): JSON parsing
- **Schema** (`schema.zig`): JSON schema validation

**Rendering** (`render/`)
- **Markdown** (`markdown.zig` - ~1,100 lines): Markdown rendering
- **Modular** (`mod.zig`): Plugin architecture

**Writing** (`write/`)
- **Single File** (`single.zig` - ~300 lines): Single file output
- **Multi File** (`multi.zig` - ~600 lines): Multi-file output

#### 4. Analysis Engine

**Coverage** (`coverage.zig` - ~850 lines)
- Documentation coverage calculation
- Per-entity type statistics
- Parameter and return coverage
- Configurable thresholds

**Linting** (`lint.zig` - ~1,400 lines)
- Rule-based validation engine
- Configurable severity levels
- Per-rule overrides
- SARIF report generation

**Cross-Reference** (`xref.zig` - ~780 lines)
- Symbol table construction
- Name resolution and scoping
- External link generation
- `@ref` and `@copydoc` validation

#### 5. Language Server (`src/lsp/`)

**Server** (`server.zig` - ~1,800 lines)
- LSP protocol implementation
- Document synchronization
- Diagnostics publishing
- Code action handling

**JSON-RPC** (`jsonrpc.zig` - ~360 lines)
- JSON-RPC protocol layer
- Message parsing and serialization
- Error handling

**Diagnostics** (`diagnostics.zig` - ~260 lines)
- Diagnostic conversion from Stig to LSP
- Severity mapping
- Position translation

**Types** (`types.zig` - ~540 lines)
- LSP type definitions
- Protocol structures

#### 6. Watch Mode (`src/watch.zig` - ~500 lines)

- File system watching (inotify/polling)
- Change debouncing
- Incremental rebuild orchestration
- mdBook serve integration

#### 7. Caching (`src/cache.zig` - ~920 lines)

- Incremental build cache
- File hash tracking
- Include dependency tracking
- Cache serialization/deserialization

#### 8. CLI Layer (`src/cli.zig` - ~1,350 lines)

- Argument parsing using Argonaut
- Subcommand handling
- Help system
- Configuration merging

#### 9. Configuration (`src/config.zig` - ~880 lines)

- TOML configuration parsing
- Default values
- Validation
- Schema definitions

### Data Flow

```
Source Files (Headers)
        │
        ▼
┌──────────────────┐
│  Tree-sitter     │
│  Parser          │
└──────────────────┘
        │
        ▼
   AST Nodes
        │
        ▼
┌──────────────────┐
│  Docstring       │
│  Extractor       │
└──────────────────┘
        │
        ▼
┌──────────────────┐
│  Symbol Table    │
│  Construction    │
└──────────────────┘
        │
        ├──────────────┬──────────────┬──────────────┐
        │              │              │              │
        ▼              ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Coverage │  │   Lint   │  │   Xref   │  │  Output  │
│ Analysis │  │          │  │          │  │  Render  │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
                                                │
                        ┌───────────┬───────────┴───────────┬───────────┐
                        │           │                       │           │
                        ▼           ▼                       ▼           ▼
                   ┌────────┐  ┌────────┐             ┌────────┐  ┌────────┐
                   │Markdown│  │mdBook  │             │  JSON  │  │ SARIF  │
                   └────────┘  └────────┘             └────────┘  └────────┘
```

### Dependencies

Stig uses minimal external dependencies, all managed through Zig's package manager:

| Dependency | Purpose | Version |
|------------|---------|---------|
| `zig-tree-sitter` | Tree-sitter Zig bindings | 0.25.0 |
| `tree-sitter-c` | C grammar | 0.24.1 |
| `tree-sitter-cpp` | C++ grammar | (vendored) |
| `argonaut` | CLI argument parsing | (vendored) |
| `zig-toml` | TOML configuration | 0.3.0 |

### Performance Characteristics

- **Memory**: General purpose allocator with safety disabled for performance
- **Parsing**: Incremental parsing with Tree-sitter's efficient API
- **Caching**: File-based cache for incremental builds
- **Concurrency**: Currently single-threaded (Zig's async roadmap may enable parallelism)

---

## Installation

### Prerequisites

- **Zig**: Version 0.15.0 or later
  - Download from [ziglang.org](https://ziglang.org/download/)
  - Install and add to PATH
- **Optional**: mdBook (for mdBook output and serve mode)
  ```bash
  cargo install mdbook
  ```

### Build from Source

```bash
# Clone the repository
git clone https://github.com/bresilla/stig.git
cd stig

# Build (optimized release)
zig build -Doptimize=ReleaseFast

# The binary will be at zig-out/bin/stig
./zig-out/bin/stig --version
```

### Development Environment

#### Using Devbox (Nix-based)

```bash
# Install Devbox
curl -fsSL https://get.jetpack.io/devbox | bash

# Enter the development environment
cd stig
devbox shell

# Now you have Zig, CMake, and Clang available
zig build
```

#### Manual Setup

```bash
# Install Zig (see prerequisites)
# Install mdBook (optional)
cargo install mdbook

# Verify installation
zig version  # Should be 0.15.0 or later
mdbook --version  # If using mdBook
```

### System-wide Installation

```bash
# Build
zig build -Doptimize=ReleaseFast

# Install binary (requires sudo)
sudo cp zig-out/bin/stig /usr/local/bin/

# Verify
stig --version
```

### Installing CMake Integration

```bash
# Install CMake module
sudo mkdir -p /usr/local/share/stig/cmake
sudo cp cmake/FindStig.cmake /usr/local/share/stig/cmake/
```

---

## Quick Start

### 1. Basic Usage

Generate documentation from a single header file:

```bash
stig include/mylib.h
```

This outputs Markdown to stdout.

### 2. Generate mdBook Structure

```bash
stig generate include/*.hpp -f mdbook -o docs/ --title "My Library API"
```

This creates an mdBook structure in `docs/`:

```
docs/
├── book.toml
├── SUMMARY.md
├── src/
│   ├── SUMMARY.md
│   ├── intro.md
│   ├── mylib_hpp.md
│   └── ...
└── ...
```

Build and serve the book:

```bash
cd docs
mdbook build
mdbook serve
```

### 3. Check Documentation Coverage

```bash
# Human-readable report
stig check include/*.h

# Compiler-style (for CI/CD)
stig check -f compiler include/*.h

# JSON output (for tools)
stig check -f json include/*.h > coverage.json
```

### 4. Watch Mode for Live Updates

```bash
stig generate include/**/*.hpp -f mdbook -o docs/ --watch --serve
```

This watches for changes and:
- Rebuilds documentation when files change
- Runs `mdbook serve` automatically
- Provides live preview at `http://localhost:3000`

### 5. Start LSP Server

```bash
stig lsp
```

Use from your editor (see [LSP Integration](#language-server-protocol)).

---

## Usage Guide

### Subcommands

Stig provides multiple subcommands for different use cases:

#### `generate` (default)

Generate documentation from header files.

```bash
stig generate [OPTIONS] <INPUT_FILES>...
```

**Options:**
- `-o, --output <PATH>`: Output file or directory
- `-f, --format <FMT>`: `markdown`, `mdbook`, or `json` (default: `markdown`)
- `--title <TITLE>`: Document title
- `-c, --config <FILE>`: Configuration file (default: `stig.toml`)
- `-w, --watch`: Watch for changes (mdBook only)
- `--serve`: Watch with `mdbook serve`
- `--force`: Ignore cache, rebuild all

**Examples:**

```bash
# Markdown to file
stig generate include/*.h -o api.md

# mdBook to directory
stig generate include/*.h -f mdbook -o docs/

# JSON output
stig generate include/*.h -f json -o api.json

# Watch mode
stig generate include/*.h -f mdbook -o docs/ --watch
```

#### `check`

Validate documentation coverage and quality.

```bash
stig check [OPTIONS] <INPUT_FILES>...
```

**Options:**
- `-c, --config <FILE>`: Configuration file
- `-f, --format <FMT>`: `human`, `compiler`, `json`, `sarif`
- `--min-coverage <N>`: Required coverage (0-100)
- `--strict`: Treat warnings as errors

**Exit Codes:**
- `0`: All checks passed
- `1`: Errors detected
- `2`: Coverage below threshold or warnings in strict mode

**Examples:**

```bash
# Human-readable
stig check include/*.h

# Compiler-style (CI/CD)
stig check -f compiler include/*.h

# With coverage threshold
stig check --min-coverage 90 include/*.h

# Strict mode
stig check --strict include/*.h

# SARIF output (GitHub)
stig check -f sarif include/*.h > results.sarif
```

#### `lsp`

Start the Language Server Protocol server.

```bash
stig lsp
```

Communicates over stdin/stdout. See [LSP Integration](#language-server-protocol).

#### `render`

Render documentation from a JSON file.

```bash
stig render [OPTIONS] <JSON_FILE>
```

**Options:**
- `-o, --output <PATH>`: Output file or directory
- `--title <TITLE>`: Document title

**Examples:**

```bash
# Render JSON to mdBook
stig render api.json -o docs/

# Render JSON to single Markdown file
stig render api.json -o api.md
```

#### `init`

Initialize a new Stig project.

```bash
stig init [OPTIONS]
```

**Options:**
- `-c, --config <FILE>`: Configuration file path
- `--force`: Overwrite existing files

Creates:
- `stig.toml` configuration file
- Example header with documentation

#### `coverage`

Analyze test coverage (which symbols are tested).

```bash
stig coverage [OPTIONS] <SOURCE_FILES>...
```

**Options:**
- `-c, --config <FILE>`: Configuration file
- `-f, --format <FMT>`: `human`, `compiler`, `json`, `sarif`
- `--min-coverage <N>`: Minimum test coverage threshold

#### `test`

Run tests using Stig's test framework.

```bash
stig test [OPTIONS] [TEST_FILES]...
```

**Options:**
- `-c, --config <FILE>`: Configuration file
- `-f, --format <FMT>`: `console`, `json`, `junit`, `sarif`

---

## Configuration

Stig uses `stig.toml` for configuration. Place it in your project root.

### Complete Example

```toml
# Project metadata
title = "My Library API"
version = "1.0.0"
authors = ["Your Name <you@example.com>"]
language = "en"

# Input and output
input_patterns = ["include/**/*.hpp", "include/*.h"]
output_dir = "docs"
format = "mdbook"

# Generation options
generate_intro = true
grouping = "by_header"  # by_header, by_prefix, by_module, flat

# Filtering
blacklist_namespace = ["detail", "internal", "impl"]
blacklist_pattern = ["*_internal", "test_*"]
extract_private = false
extract_protected = true

# Coverage
[coverage]
min_coverage = 80
require_param_docs = true
require_return_docs = true
require_tparam_docs = true
exclude_patterns = ["vendor/**"]

# Linting
[lint]
enabled = true
treat_warnings_as_errors = false
max_brief_length = 80
require_brief = true
require_param_docs = true
require_return_docs = true
require_tparam_docs = true
check_cross_references = true
require_brief_period = false
exclude_patterns = []

# Per-rule severity
[lint.rules]
W001 = "ignore"      # Missing documentation
W003 = "error"       # Missing @param
E001 = "warning"     # Param name mismatch

# Watch mode
[watch]
debounce_ms = 100
ignore_patterns = [
    ".git/**",
    "build/**",
    "node_modules/**",
]

# Godbolt/Compiler Explorer
[godbolt]
enabled = true
compiler = "g132"
options = "-O2 -std=c++20"
link_text = "Run on Compiler Explorer"

# Test coverage
[test_coverage]
min_coverage = 0
test_patterns = ["test/**/*.cpp"]
exclude_patterns = []

# Resource limits
[limits]
max_file_size = 10485760      # 10 MB
max_include_size = 1048576    # 1 MB
max_json_size = 104857600    # 100 MB
max_config_size = 1048576    # 1 MB

# Output customization
[output]
show_source_location = true
show_access_specifiers = true
code_language = "cpp"
synopsis_style = "compact"   # compact, full

# Custom section names (localization)
[section_names]
parameters = "Parameters"
returns = "Return Value"
template_params = "Template Parameters"
see_also = "See Also"
notes = "Notes"
warnings = "Warnings"
examples = "Examples"

# External documentation links
[[external_docs]]
prefix = "std::"
url_template = "https://en.cppreference.com/w/cpp/$$"

[[external_docs]]
prefix = "boost::"
url_template = "https://www.boost.org/doc/libs/release/libs/$$"

# Module organization (for by_module grouping)
[[modules]]
name = "core"
patterns = ["include/core/*.hpp"]
title = "Core Functionality"
description = "Fundamental types and algorithms"

[[modules]]
name = "utils"
patterns = ["include/utils/*.hpp"]
title = "Utilities"
description = "Helper functions and utilities"
```

### Configuration Sections

#### Project Metadata

```toml
title = "API Reference"        # Documentation title
authors = ["Name <email>"]    # Author list
language = "en"               # Language for mdBook
```

#### Input/Output

```toml
input_patterns = ["include/**/*.hpp"]  # Glob patterns for headers
output_dir = "docs"                    # Output directory
format = "mdbook"                     # Output format
```

#### Grouping Strategies

```toml
grouping = "by_header"  # Options:
# - by_header: One chapter per header file
# - by_prefix: Group by common file prefix
# - by_module: Use [[modules]] definitions
# - flat: All symbols in single page
```

#### Filtering

```toml
blacklist_namespace = ["detail", "internal"]  # Exclude namespaces
blacklist_pattern = ["*_internal"]           # Glob patterns to exclude
extract_private = false                       # Include private members
extract_protected = true                      # Include protected members
```

#### Output Options

```toml
[output]
show_source_location = true     # Show file:line in docs
show_access_specifiers = true  # Show public/private/protected
code_language = "cpp"          # Syntax highlighting language
synopsis_style = "compact"    # compact or full
```

#### Coverage Configuration

```toml
[coverage]
min_coverage = 80              # Minimum coverage percentage
require_param_docs = true      # Require @param for all parameters
require_return_docs = true     # Require @return for non-void functions
require_tparam_docs = true     # Require @tparam for templates
exclude_patterns = ["vendor/**"]  # Patterns to exclude
```

#### Linting Configuration

```toml
[lint]
enabled = true                     # Enable linting
treat_warnings_as_errors = false   # Warnings as errors
max_brief_length = 80             # Max @brief length
require_brief = true              # Require @brief
require_param_docs = true         # Require @param
require_return_docs = true        # Require @return
require_tparam_docs = true        # Require @tparam
check_cross_references = true      # Validate @ref
require_brief_period = false      # Require period at end
```

#### Per-Rule Severity

Override individual rule severity:

```toml
[lint.rules]
# Codes: W001-W007 (warnings), E001-E002 (errors)
W001 = "ignore"      # Ignore missing docs
W003 = "error"       # Missing @param as error
E001 = "warning"     # Downgrade to warning
```

See [Lint Rules](#lint-rules) for complete list.

#### Watch Mode

```toml
[watch]
debounce_ms = 100                    # Debounce delay
ignore_patterns = [
    ".git/**",
    "build/**",
    "*.o",
]
```

#### Godbolt Integration

```toml
[godbolt]
enabled = true               # Enable Compiler Explorer links
compiler = "g132"          # Compiler ID
options = "-O2 -std=c++20" # Compiler options
link_text = "Try it"
```

#### Module Organization

```toml
[[modules]]
name = "core"
patterns = ["include/core/*.hpp"]
title = "Core"
description = "Core functionality"

[[modules]]
name = "utils"
patterns = ["include/utils/*.hpp"]
title = "Utilities"
```

#### External Docs

```toml
[[external_docs]]
prefix = "std::"
url_template = "https://en.cppreference.com/w/cpp/$$"

[[external_docs]]
prefix = "mylib::internal::"
url_template = "internal/$$.html"
```

---

## Doxygen Tags

Stig supports comprehensive Doxygen-style tags. Both `@tag` and `\tag` forms are accepted.

### Basic Documentation Tags

#### `@brief` / `@short`

Brief one-line description.

```cpp
/**
 * @brief Adds two numbers together
 *
 * Performs addition of two integers.
 */
int add(int a, int b);
```

#### `@details`

Detailed description (multi-line).

```cpp
/**
 * @brief Adds two numbers
 * @details
 * This function performs integer addition with the following considerations:
 * - Overflow is not checked
 * - Negative numbers are handled correctly
 * - Result may overflow for very large inputs
 */
int add(int a, int b);
```

#### `@param` / `@p`

Parameter documentation.

```cpp
/**
 * @brief Copies memory
 * @param dest Destination address
 * @param src Source address
 * @param n Number of bytes to copy
 */
void* memcpy(void* dest, const void* src, size_t n);
```

#### `@tparam`

Template parameter documentation.

```cpp
/**
 * @brief Generic container
 * @tparam T Element type
 * @tparam N Maximum capacity
 */
template<typename T, size_t N>
class StaticArray { /* ... */ };
```

#### `@return` / `@returns`

Return value documentation.

```cpp
/**
 * @brief Computes factorial
 * @return The factorial of n
 */
int factorial(int n);
```

#### `@retval`

Specific return value documentation.

```cpp
/**
 * @brief Opens a file
 * @retval 0 Success
 * @retval -1 File not found
 * @retval -2 Permission denied
 */
int open_file(const char* path);
```

### Semantic Tags

#### `@throws` / `@throw` / `@exception`

Exception documentation.

```cpp
/**
 * @brief Allocates memory
 * @throws std::bad_alloc If allocation fails
 */
void* allocate(size_t size);
```

#### `@pre`

Preconditions.

```cpp
/**
 * @brief Accesses array element
 * @pre index < size()
 */
T& at(size_t index);
```

#### `@post`

Postconditions.

```cpp
/**
 * @brief Resets the container
 * @post size() == 0
 */
void clear();
```

#### `@requires`

C++20 concept requirements.

```cpp
/**
 * @brief Sorts elements
 * @requires std::sortable<It>
 */
template<std::sortable It>
void sort(It begin, It end);
```

#### `@effects`

Side effects.

```cpp
/**
 * @brief Adds element to container
 * @effects Invalidates iterators
 */
void push(const T& value);
```

#### `@complexity`

Algorithmic complexity.

```cpp
/**
 * @brief Binary search
 * @complexity O(log n)
 */
bool contains(const T& value) const;
```

#### `@invariant`

Class invariants.

```cpp
/**
 * @brief Smart pointer
 * @invariant pointer is either null or valid
 */
template<typename T>
class UniquePtr { /* ... */ };
```

#### `@threadsafety` / `@sync`

Thread safety notes.

```cpp
/**
 * @brief Thread-safe counter
 * @threadsafety Safe for concurrent access
 */
class AtomicCounter { /* ... */ };
```

### Informational Tags

#### `@note`

Additional notes.

```cpp
/**
 * @brief Parses input
 * @note This function modifies the input buffer
 */
void parse(char* buffer);
```

#### `@warning`

Warning messages.

```cpp
/**
 * @brief Loads library
 * @warning Caller must ensure library is thread-safe
 */
void load_library(const char* name);
```

#### `@deprecated`

Deprecation notice.

```cpp
/**
 * @brief Old function
 * @deprecated Use new_function() instead
 */
void old_function();
```

#### `@since`

Version introduced.

```cpp
/**
 * @brief New feature
 * @since 1.2.0
 */
void new_feature();
```

#### `@author`

Author information.

```cpp
/**
 * @brief Core module
 * @author John Doe <john@example.com>
 */
namespace core { /* ... */ };
```

#### `@version`

Version information.

```cpp
/**
 * @brief API interface
 * @version 2.0
 */
class API { /* ... */ };
```

#### `@date`

Date information.

```cpp
/**
 * @brief Updated algorithm
 * @date 2024-01-15
 */
void improved_algorithm();
```

#### `@copyright`

Copyright notice.

```cpp
/**
 * @file utils.h
 * @copyright Copyright (c) 2024 Company Name
 */
```

#### `@see` / `@sa`

See also references.

```cpp
/**
 * @brief Vector operations
 * @see @ref Matrix
 * @sa dot_product
 */
class Vector { /* ... */ };
```

#### `@todo`

TODO items.

```cpp
/**
 * @brief Future feature
 * @todo Implement caching for better performance
 */
void future_feature();
```

#### `@bug`

Known bugs.

```cpp
/**
 * @brief Experimental function
 * @bug May crash on empty input
 */
void experimental();
```

### Cross-Reference Tags

#### `@ref`

Cross-reference to another symbol.

```cpp
/**
 * @brief Matrix operations
 *
 * This class provides matrix operations that complement @ref Vector.
 * See also @ref Matrix::multiply for details.
 */
class Matrix { /* ... */ };
```

#### `@copydoc`

Copy documentation from another symbol.

```cpp
/**
 * @brief Copies documentation from add()
 * @copydoc add
 */
int add_integers(int a, int b);
```

### Grouping Tags

#### `@defgroup`

Define a documentation group.

```cpp
/**
 * @defgroup math Math Operations
 * @brief Mathematical functions and utilities
 */
```

#### `@addtogroup`

Add to existing group.

```cpp
/**
 * @addtogroup math
 * @{
 */

/**
 * @brief Sine function
 */
double sin(double x);

/** @} */
```

#### `@ingroup`

Mark entity as belonging to group.

```cpp
/**
 * @ingroup math
 * @brief Cosine function
 */
double cos(double x);
```

#### `@{` / `@}`

Group member markers.

```cpp
/**
 * @addtogroup math
 * @{
 */

double tan(double x);
double atan(double x);

/** @} */
```

### Code Tags

#### `@code` / `@endcode`

Code blocks.

```cpp
/**
 * @brief Usage example
 *
 * @code
 * Calculator calc;
 * int result = calc.add(2, 3);
 * @endcode
 */
class Calculator { /* ... */ };
```

#### `@snippet`

Include code from external file.

```cpp
/**
 * @brief Example usage
 *
 * @snippet examples/usage.cpp calculator_example
 */
class Calculator { /* ... */ };
```

In `examples/usage.cpp`:

```cpp
// [calculator_example]
Calculator calc;
int result = calc.add(2, 3);
std::cout << result << std::endl;
// [calculator_example]
```

#### `@mermaid` / `@endmermaid`

Mermaid diagrams.

```cpp
/**
 * @brief Workflow diagram
 *
 * @mermaid
 * graph TD
 *   A[Start] --> B[Process]
 *   B --> C[End]
 * @endmermaid
 */
void workflow();
```

### File and Page Tags

#### `@file`

File-level documentation.

```cpp
/**
 * @file utils.h
 * @brief Utility functions
 * @author Your Name
 */
```

#### `@page` / `@mainpage`

Custom pages.

```cpp
/**
 * @page getting-started Getting Started
 *
 * # Quick Start Guide
 *
 * To use this library:
 * 1. Include the header
 * 2. Call the functions
 */
```

#### `@exclude`

Exclude from documentation.

```cpp
/**
 * @exclude
 * @brief Internal implementation detail
 */
void internal_helper();
```

### Custom Tags

#### `@synopsis`

Custom synopsis override.

```cpp
/**
 * @brief Custom display
 * @synopsis auto result = process(data)
 */
auto process(const Data& data);
```

#### `@unique_name`

Custom anchor name.

```cpp
/**
 * @brief Function with special name
 * @unique_name special_function_v2
 */
void function();
```

### Multi-line Tag Continuation

Tags can continue on subsequent lines with indentation:

```cpp
/**
 * @brief Brief description
 * @param param1 This is a long parameter description that
 *              continues on the next line
 * @param param2 Another parameter with detailed
 *              explanation spanning multiple lines
 */
void function(int param1, int param2);
```

### Escaped Characters

Use `@@` for literal `@` and `\\` for literal `\`:

```cpp
/**
 * @brief Email address
 * @param email Must contain @@ character (e.g., user@@example.com)
 * @param path Windows paths use backslashes: C:\\Users\\...
 */
void send_email(const char* email, const char* path);
```

---

## Output Formats

### Markdown

Single-file Markdown output with:

- Table of contents
- Cross-reference links
- Code block syntax highlighting
- Organized by header file or namespace

**Example usage:**

```bash
stig generate include/*.h -f markdown -o api.md
```

**Output structure:**

```markdown
# API Documentation

## Table of Contents

- [utils.h](#utilsh)
  - [Functions](#functions)

---

## utils.h

### Functions

#### `void print(const char* message)`

Prints a message to standard output.

**Parameters:**
- `message`: The message to print

---

[Back to Top](#api-documentation)
```

### mdBook

Multi-page documentation structure ready for mdBook.

**Example usage:**

```bash
stig generate include/*.h -f mdbook -o docs/
cd docs
mdbook serve
```

**Output structure:**

```
docs/
├── book.toml
├── SUMMARY.md
├── src/
│   ├── intro.md
│   ├── SUMMARY.md
│   ├── utils_h.md
│   ├── core_hpp.md
│   └── ...
└── ...
```

**book.toml** example:

```toml
[book]
title = "API Documentation"
authors = ["Your Name"]
language = "en"

[build]
build-dir = "book"

[output.html]
default-theme = "rust"
```

**Grouping strategies:**

1. **by_header** (default): One chapter per header file
2. **by_prefix**: Group by common file prefix (e.g., `core_*.hpp` → `core/`)
3. **by_module**: Use `[[modules]]` configuration
4. **flat**: All symbols in single page

### JSON

Structured data for custom processing.

**Example usage:**

```bash
stig generate include/*.h -f json -o api.json
```

**Schema:**

```json
{
  "version": "2.0",
  "project": {
    "title": "API Documentation",
    "version": "1.0.0"
  },
  "modules": [
    {
      "name": "utils.h",
      "entities": [
        {
          "name": "print",
          "kind": "function",
          "brief": "Prints a message",
          "params": [...],
          "return": {...}
        }
      ]
    }
  ]
}
```

### SARIF

Static Analysis Results Interchange Format for CI/CD integration.

**Example usage:**

```bash
stig check -f sarif include/*.h > results.sarif
```

Use with GitHub Advanced Security:

```yaml
- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: results.sarif
```

---

## Language Server Protocol

Stig provides a full-featured LSP server for editor integration.

### Features

- **Diagnostics**: Real-time documentation validation
- **Completion**: Auto-complete 37 Doxygen tags with snippets
- **Code Actions**: Quick fixes for common issues
- **Hover**: Show documentation on hover
- **Document Symbols**: Navigate to documented entities
- **Signature Help**: Show parameter documentation

### Editor Configuration

#### Neovim (native LSP)

```lua
vim.lsp.start({
  name = "stig",
  cmd = { "stig", "lsp" },
  root_dir = vim.fs.dirname(
    vim.fs.find({ "stig.toml" }, { upward = true })[1]
  ),
})
```

#### Neovim (nvim-lspconfig)

```lua
require('lspconfig').stig.setup({
  cmd = { "stig", "lsp" },
  root_dir = function()
    return vim.fs.dirname(
      vim.fs.find({ "stig.toml" }, { upward = true })[1]
    )
  end,
})
```

#### VS Code (coc.nvim)

```json
{
  "languageserver": {
    "stig": {
      "command": "stig",
      "args": ["lsp"],
      "filetypes": ["c", "cpp"],
      "rootPatterns": ["stig.toml"],
      "workspaceFolders": true
    }
  }
}
```

#### VS Code (custom extension)

Create `.vscode/settings.json`:

```json
{
  "stig.enabled": true,
  "stig.path": "/usr/local/bin/stig",
  "stig.configPath": "stig.toml"
}
```

#### Emacs (eglot)

```elisp
(add-hook 'c++-mode-hook
  (lambda ()
    (add-to-list 'eglot-server-programs
                 '((c++-mode . ("stig" "lsp")))))
```

#### Vim/Neovim (vim-lsp)

```vim
if executable('stig')
  au User lsp_setup call lsp#register_server({
    \ 'name': 'stig',
    \ 'cmd': {server_info->['stig', 'lsp']},
    \ 'whitelist': ['c', 'cpp'],
    \ 'workspace_config': {
    \   'stig': {
    \     'configPath': 'stig.toml',
    \   },
    \ },
    \ })
endif
```

### LSP Capabilities

#### Diagnostics

Stig provides real-time diagnostics:

- Missing documentation (`@brief`, `@param`, `@return`)
- Empty descriptions
- Duplicate `@param` tags
- Parameter name mismatches
- Broken cross-references

**Example diagnostic:**

```
include/utils.h:10:5: warning [W003]: Missing @param for parameter 'message'
```

#### Completion

Auto-complete Doxygen tags with snippets:

- `@brief` → Insert `@brief ` and move to detail
- `@param` → Insert `@param ` with placeholder
- `@code` → Insert code block with cursor inside

#### Code Actions

Available quick fixes:

1. **Generate documentation stub**
   - Creates minimal docstring with `@brief` and `@param` tags

2. **Add missing `@param`**
   - Adds `@param` tags for undocumented parameters

3. **Add missing `@return`**
   - Adds `@return` tag for non-void functions

4. **Fix parameter name**
   - Corrects `@param` name to match function signature

**Trigger:** Cursor on diagnostic, run code action.

---

## Coverage & Linting

### Coverage Analysis

Track how well your code is documented.

```bash
stig check include/*.h
```

**Output:**

```
Documentation Coverage Report
============================

Overall Coverage: 85%

By Type:
  Functions: 90% (45/50)
  Classes:    80% (4/5)
  Structs:   100% (3/3)
  Variables:  70% (7/10)
  Macros:     0% (0/2)

Parameter Documentation: 95% (38/40)
Return Documentation:     100% (45/45)
Template Params:         75% (3/4)

Missing Documentation:
  - internal_helper() (utils.h:42)
  - debug_flag (utils.h:10)
  - MACRO_CONSTANT (config.h:5)

Coverage is below minimum threshold (80%)
```

### Linting

Validate documentation quality.

```bash
stig check include/*.h
```

**Lint Rules:**

| Code | Severity | Rule |
|------|----------|------|
| W001 | Warning | Missing documentation |
| W002 | Warning | Missing `@brief` |
| W003 | Warning | Missing `@param` |
| W004 | Warning | Missing `@tparam` |
| W005 | Warning | Missing `@return` |
| W006 | Warning | Empty description |
| W007 | Warning | Duplicate `@param` |
| E001 | Error | Parameter name mismatch |
| E002 | Error | Broken cross-reference |

**Configurable severity:**

```toml
[lint.rules]
W001 = "ignore"      # Skip missing doc warnings
W003 = "error"       # Treat missing @param as error
E001 = "warning"     # Downgrade param mismatch
```

### CI/CD Integration

#### Compiler-style output

```bash
stig check -f compiler include/*.h
```

Output:
```
include/utils.h:10:5: warning [W002]: Missing @brief for function print
include/utils.h:15:5: error [E001]: Parameter name mismatch: expected 'msg', found 'message'
```

#### SARIF output

```bash
stig check -f sarif include/*.h > results.sarif
```

GitHub Actions example:

```yaml
- name: Check Documentation
  run: stig check -f compiler include/*.h

- name: Upload SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: results.sarif
```

---

## Watch Mode

Watch for file changes and automatically rebuild documentation.

### Basic Usage

```bash
stig generate include/*.h -f mdbook -o docs/ --watch
```

### With Live Preview

```bash
stig generate include/*.h -f mdbook -o docs/ --watch --serve
```

This:
1. Watches header files for changes
2. Rebuilds documentation when files change
3. Runs `mdbook serve` automatically
4. Opens browser at `http://localhost:3000`

### Configuration

```toml
[watch]
debounce_ms = 100                    # Wait before rebuild
ignore_patterns = [
    ".git/**",
    "build/**",
    "node_modules/**",
    "*.o",
]
```

### How It Works

1. **File Watching**
   - Linux: Uses inotify for instant notification
   - Other platforms: Polls every 200ms

2. **Debouncing**
   - Waits `debounce_ms` after last change
   - Coalesces rapid changes

3. **Incremental Rebuild**
   - Only rebuilds changed files
   - Uses `.stig-cache` to track state
   - Handles include dependencies

4. **Output**
   - Regenerates mdBook structure
   - Triggers live reload in browser

---

## Integration

### CMake Integration

#### Install CMake Module

```bash
sudo cp cmake/FindStig.cmake /usr/local/share/stig/cmake/
```

#### Basic CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyLibrary)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
find_package(Stig REQUIRED)

stig_add_docs(api_docs
    SOURCES
        include/*.hpp
    OUTPUT ${CMAKE_BINARY_DIR}/docs
    FORMAT mdbook
    TITLE "My Library API"
)
```

#### Build Documentation

```bash
cmake -B build
cmake --build build --target api_docs
```

#### Advanced Configuration

```cmake
stig_add_docs(docs
    SOURCES
        include/core/*.hpp
        include/utils/*.hpp
    OUTPUT ${CMAKE_BINARY_DIR}/api-docs
    FORMAT mdbook
    TITLE "API Reference"
    CONFIG ${CMAKE_SOURCE_DIR}/stig.toml
    FORCE
    WATCH
)
```

### GitHub Actions

#### Basic Workflow

```yaml
name: Documentation

on:
  push:
    branches: [main]
  pull_request:

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Stig
        run: |
          git clone https://github.com/bresilla/stig.git
          cd stig
          zig build -Doptimize=ReleaseFast
          sudo cp zig-out/bin/stig /usr/local/bin/

      - name: Generate Documentation
        run: stig generate include/*.hpp -f mdbook -o docs/

      - name: Install mdBook
        run: cargo install mdbook

      - name: Build mdBook
        run: mdbook build docs

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        if: github.ref == 'refs/heads/main'
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: docs/book
```

#### Using Custom Action

```yaml
- name: Generate Documentation
  uses: ./.github/actions/stig-docs
  with:
    input: 'include/**/*.hpp'
    output: 'docs'
    format: 'mdbook'
    coverage: 'true'
    coverage-threshold: '80'
```

### Other Build Systems

#### Meson

```meson
# meson.build
stig = find_program('stig', required: false)

if stig.found()
  run_target('docs',
    command: [stig, 'generate', 'include/*.h', '-f', 'mdbook', '-o', 'docs'],
    build_by_default: false)
endif
```

#### Bazel

```python
# BUILD.bazel
genrule(
  name = "docs",
  srcs = glob(["include/**/*.h"]),
  outs = ["docs/SUMMARY.md"],
  cmd = "stig generate $(SRCS) -f mdbook -o docs/",
  tools = ["@stig//:stig"],
)
```

#### Make

```makefile
.PHONY: docs

docs:
	stig generate include/*.h -f mdbook -o docs/

watch:
	stig generate include/*.h -f mdbook -o docs/ --watch --serve
```

---

## Advanced Features

### Snippet Extraction

Extract code examples from external files.

**Header file:**

```cpp
/**
 * @brief Usage example
 *
 * @snippet examples/usage.cpp example
 */
class Calculator {
public:
    int add(int a, int b);
};
```

**Example file (`examples/usage.cpp`):**

```cpp
// [example]
Calculator calc;
int result = calc.add(2, 3);
// [example]
```

**Supported comment styles:**

| Language | Comment Style | Example |
|----------|---------------|---------|
| C/C++/Zig/Rust/Go/Java/JS/TS | `//` | `// [anchor]` |
| Python/Shell/Ruby/YAML/Makefile | `#` | `# [anchor]` |
| CSS/SCSS/LESS | `/* */` | `/* [anchor] */` |
| HTML/XML/SVG | `<!-- -->` | `<!-- [anchor] -->` |
| SQL/Lua | `--` | `-- [anchor]` |

### Mermaid Diagrams

Embed Mermaid diagrams in documentation.

```cpp
/**
 * @brief Architecture overview
 *
 * @mermaid
 * graph TD
 *   A[Client] -->|HTTP| B[Server]
 *   B -->|Query| C[Database]
 *   C -->|Result| B
 *   B -->|Response| A
 * @endmermaid
 */
class Server {
    // ...
};
```

### Godbolt Integration

Add Compiler Explorer links to code examples.

```toml
[godbolt]
enabled = true
compiler = "g132"
options = "-O2 -std=c++20"
link_text = "Run on Compiler Explorer"
```

Output includes buttons linking to live code.

### Custom External Links

Configure external documentation links.

```toml
[[external_docs]]
prefix = "std::"
url_template = "https://en.cppreference.com/w/cpp/$$"

[[external_docs]]
prefix = "boost::"
url_template = "https://www.boost.org/doc/libs/release/libs/$$"

[[external_docs]]
prefix = "mylib::internal::"
url_template = "internal/$$.html"
```

### Module Organization

Organize documentation into logical modules.

```toml
grouping = "by_module"

[[modules]]
name = "core"
patterns = ["include/core/*.hpp"]
title = "Core Functionality"
description = "Fundamental types and algorithms"

[[modules]]
name = "utils"
patterns = ["include/utils/*.hpp"]
title = "Utilities"
description = "Helper functions"

[[modules]]
name = "network"
patterns = ["include/network/*.hpp"]
title = "Networking"
description = "Network protocols and utilities"
```

### Custom Section Names

Localize section names for different languages.

```toml
[section_names]
parameters = "Parametry"       # Polish
returns = "Wartość zwracana"
template_params = "Parametry szablonu"
see_also = "Zobacz także"
notes = "Uwagi"
warnings = "Ostrzeżenia"
examples = "Przykłady"
```

### Filtering

Exclude specific namespaces and patterns.

```toml
blacklist_namespace = ["detail", "internal", "impl"]
blacklist_pattern = ["*_internal", "test_*", "*_v[0-9]"]
extract_private = false
extract_protected = true
```

### Resource Limits

Configure file size limits.

```toml
[limits]
max_file_size = 10485760      # 10 MB
max_include_size = 1048576    # 1 MB
max_json_size = 104857600    # 100 MB
max_config_size = 1048576    # 1 MB
```

---

## Examples

### Example 1: Simple Function

```cpp
/**
 * @file math.h
 * @brief Mathematical operations
 */

/**
 * @brief Calculates the factorial of a number
 *
 * Computes n! = n × (n-1) × ... × 2 × 1.
 *
 * @param n The number to compute factorial for
 * @return The factorial of n
 * @pre n >= 0
 * @throws std::invalid_argument If n is negative
 * @complexity O(n)
 *
 * @code
 * int result = factorial(5);  // result = 120
 * @endcode
 */
int factorial(int n);
```

### Example 2: Template Class

```cpp
/**
 * @brief Generic vector container
 *
 * Provides a dynamic array with automatic memory management.
 *
 * @tparam T The element type
 * @tparam Allocator The allocator type (defaults to std::allocator)
 *
 * @see @ref Matrix
 */
template<
    typename T,
    typename Allocator = std::allocator<T>
> class Vector {
public:
    /**
     * @brief Default constructor
     *
     * @complexity O(1)
     */
    Vector();

    /**
     * @brief Constructs with size
     *
     * @param size Initial capacity
     * @throws std::bad_alloc If allocation fails
     */
    explicit Vector(size_t size);

    /**
     * @brief Adds element to end
     *
     * @effects May reallocate memory
     * @post size() increases by 1
     * @threadsafety Not thread-safe
     */
    void push(const T& value);

    /**
     * @brief Accesses element at index
     *
     * @param index Zero-based index
     * @return Reference to element
     * @pre index < size()
     * @throws std::out_of_range If index is out of bounds
     */
    T& at(size_t index);

private:
    T* data_;               ///< Data array
    size_t size_;           ///< Number of elements
    size_t capacity_;       ///< Allocated capacity
};
```

### Example 3: Class with Groups

```cpp
/**
 * @defgroup network Networking
 * @brief Network communication utilities
 */

/**
 * @addtogroup network
 * @{
 */

/**
 * @brief HTTP client
 *
 * Provides asynchronous HTTP requests with SSL support.
 *
 * @note Requires OpenSSL to be installed
 *
 * @warning Thread safety: Each instance must be used from a single thread
 */
class HttpClient {
public:
    /**
     * @brief Configuration settings
     */
    struct Config {
        int timeout_ms;        ///< Request timeout
        bool verify_ssl;       ///< Verify SSL certificates
        std::string user_agent; ///< User agent string
    };

    /**
     * @brief Constructs client with config
     * @param config Configuration settings
     */
    explicit HttpClient(const Config& config);

    /**
     * @brief Performs GET request
     *
     * @param url Target URL
     * @return Response data
     * @throws NetworkError On connection failure
     * @throws TimeoutError If request times out
     *
     * @snippet examples/http.cpp get_example
     */
    std::string get(const std::string& url);

    /**
     * @brief Performs POST request
     *
     * @param url Target URL
     * @param data Request body
     * @return Response data
     */
    std::string post(const std::string& url, const std::string& data);

private:
    void* handle_;  ///< libcurl handle
};

/** @} */
```

### Example 4: Concept and Requirements

```cpp
/**
 * @brief Sorts range using quicksort algorithm
 *
 * Sorts elements in ascending order.
 *
 * @tparam It Iterator type
 * @tparam Comp Comparison function type
 *
 * @requires std::random_access_iterator<It>
 * @requires std::sortable<It, Comp>
 *
 * @param begin Start iterator
 * @param end End iterator
 * @param comp Comparison function (optional)
 *
 * @complexity O(n log n) average, O(n²) worst
 * @invariant The range is sorted after this function returns
 *
 * @see @ref merge_sort
 */
template<
    std::random_access_iterator It,
    typename Comp = std::less<>
>
void quicksort(It begin, It end, Comp comp = Comp{});
```

### Example 5: Cross-References and CopyDoc

```cpp
/**
 * @brief Base class for all shapes
 *
 * Provides common interface for geometric shapes.
 */
class Shape {
public:
    /**
     * @brief Calculates area
     * @return Area in square units
     */
    virtual double area() const = 0;

    /**
     * @brief Calculates perimeter
     * @return Perimeter in linear units
     */
    virtual double perimeter() const = 0;
};

/**
 * @brief Rectangle shape
 *
 * Represents a rectangle with width and height.
 *
 * @see @ref Shape (base class)
 * @see @ref Circle (related shape)
 */
class Rectangle : public Shape {
public:
    /**
     * @copydoc Shape::area
     */
    double area() const override;

    /**
     * @copydoc Shape::perimeter
     */
    double perimeter() const override;
};
```

---

## Project Structure

```
stig/
├── src/                      # Source code
│   ├── main.zig             # Entry point and CLI
│   ├── cli.zig              # Argument parsing
│   ├── config.zig           # Configuration management
│   ├── parser/              # Parsers
│   │   ├── c.zig           # C parser
│   │   ├── cpp.zig         # C++ parser
│   │   └── common.zig      # Shared utilities
│   ├── docstring/           # Docstring handling
│   │   ├── extractor.zig   # Tag extraction
│   │   └── includes.zig    # Include/snippet processing
│   ├── model/               # Data models
│   │   └── types.zig       # Type definitions
│   ├── output/              # Output generators
│   │   ├── markdown.zig    # Markdown output
│   │   ├── mdbook.zig      # mdBook output
│   │   ├── json/           # JSON pipeline
│   │   ├── render/         # Rendering plugins
│   │   └── write/          # File writers
│   ├── coverage.zig        # Coverage analysis
│   ├── lint.zig            # Linting engine
│   ├── xref.zig            # Cross-references
│   ├── cache.zig           # Incremental caching
│   ├── watch.zig           # Watch mode
│   ├── filewatcher.zig     # File watching
│   ├── snippet.zig         # Snippet extraction
│   ├── diagrams.zig        # Diagram generation
│   ├── godbolt.zig         # Compiler Explorer
│   ├── lsp/                # Language Server
│   │   ├── server.zig      # LSP server
│   │   ├── jsonrpc.zig     # JSON-RPC layer
│   │   ├── diagnostics.zig  # Diagnostic conversion
│   │   └── types.zig       # LSP types
│   ├── init.zig            # Project initialization
│   ├── testcov.zig         # Test coverage
│   └── testing.zig         # Test framework
├── test/                   # Tests
│   ├── fixtures/           # Test fixtures
│   │   ├── complex.h       # Complex C constructs
│   │   ├── docstrings.h    # Docstring examples
│   │   └── ...
│   └── complex/            # Complex C++ test project
│       ├── include/         # Test headers
│       ├── examples/       # Test examples
│       ├── test/           # Test files
│       └── book/          # Generated docs
├── vendor/                 # Vendored dependencies
│   ├── tree-sitter-cpp/    # C++ grammar
│   └── argonaut/          # CLI parsing
├── cmake/                  # CMake integration
│   ├── FindStig.cmake      # CMake module
│   └── README.md           # CMake documentation
├── .github/                # GitHub integration
│   ├── workflows/          # CI/CD workflows
│   └── actions/           # GitHub Actions
│       └── stig-docs/     # Documentation action
├── docs/                   # Stig's own documentation
├── build.zig               # Zig build configuration
├── build.zig.zon           # Zig dependencies
├── Makefile                # Build automation
├── stig.toml              # Stig configuration
├── README.md               # This file
├── CHANGELOG.md            # Changelog
├── LICENSE                 # MIT License
├── NAME                    # Project name
└── VERSION                 # Project version
```

### Code Statistics

- **Total Zig code**: ~33,700 lines
- **Main components**:
  - Parser: ~5,200 lines
  - Output generation: ~7,400 lines
  - LSP: ~2,400 lines
  - Analysis (coverage/lint): ~2,300 lines
  - CLI and config: ~2,200 lines

---

## Contributing

Contributions are welcome! Please follow these guidelines:

### Development Setup

```bash
# Clone repository
git clone https://github.com/bresilla/stig.git
cd stig

# Install Devbox (recommended)
curl -fsSL https://get.jetpack.io/devbox | bash
devbox shell

# Or manually install Zig 0.15.0+
zig build
zig build test
```

### Code Style

- **CamelCase**: Classes, Enums, Unions
- **snake_case**: Functions, variables, methods
- **ALL_CAPS**: Global constants
- Follow Zig style guidelines
- Use `zig fmt` for formatting

### Testing

```bash
# Run all tests
zig build test

# Run specific test
zig test src/parser/cpp.zig

# Run with verbose output
zig build test --summary all
```

### Adding Features

1. Add tests for new functionality
2. Implement feature in appropriate module
3. Update documentation
4. Run `zig fmt` on changed files
5. Ensure all tests pass

### Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

### Version 0.0.2 (Current)

Recent highlights:
- SARIF output format
- JSON v2 document model
- `stig render` subcommand
- Improved linting and coverage
- Enhanced C++20 support

### Version 0.0.1

Initial release with core features:
- C/C++ parsing
- Markdown and mdBook output
- LSP support
- Watch mode

---

## License

Stig is distributed under the MIT License. See [LICENSE](LICENSE) for the complete text.

### Copyright

```
Copyright (c) 2024 Stig Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Acknowledgments

Stig would not be possible without the following projects:

- **Zig**: The amazing language that powers Stig
- **Tree-sitter**: Grammar parsing framework
- **Doxygen**: Documentation tag conventions
- **Standardese**: Inspiration for modern documentation tooling
- **mdBook**: Excellent static site generator
- **Argonaut**: CLI argument parsing library
- **zig-toml**: TOML parsing library

---

## Resources

- **GitHub Repository**: [https://github.com/bresilla/stig](https://github.com/bresilla/stig)
- **Documentation**: [https://stig.dev](https://stig.dev)
- **Issue Tracker**: [https://github.com/bresilla/stig/issues](https://github.com/bresilla/stig/issues)
- **Discussions**: [https://github.com/bresilla/stig/discussions](https://github.com/bresilla/stig/discussions)

---

## Support

- **Documentation**: See [Doxygen Tags](#doxygen-tags) and [Configuration](#configuration)
- **Examples**: See [test/fixtures](test/fixtures/) for comprehensive examples
- **Issues**: Report bugs on [GitHub Issues](https://github.com/bresilla/stig/issues)
- **Discussions**: Ask questions on [GitHub Discussions](https://github.com/bresilla/stig/discussions)

---

## Roadmap

### Planned Features

- [ ] HTML output format
- [ ] Doxygen XML import
- [ ] Sphinx integration
- [ ] More diagram types (PlantUML, Graphviz)
- [ ] Custom template rendering
- [ ] Parallel parsing for large codebases
- [ ] Incremental LSP indexing
- [ ] More language support (Rust, Python)

### Long-term Goals

- [ ] Cloud-based documentation hosting
- [ ] Documentation versioning
- [ ] Interactive examples
- [ ] API explorer UI
- [ ] Documentation analytics

---

**Stig** - Modern C/C++ Documentation Generator

*Built with ❤️ using Zig*
