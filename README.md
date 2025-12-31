# Stig

C/C++ documentation generator using tree-sitter parsing with mdbook output support

## Overview

Stig is a documentation generator for C and C++ codebases that parses source files using tree-sitter and extracts documentation from Doxygen-style comments. It generates clean markdown documentation that can be viewed standalone or built into an mdbook.

**Key Features:**
- **Tree-sitter Parsing**: Accurate AST-based extraction of functions, structs, enums, typedefs, and macros
- **Doxygen Support**: Parses `/** */`, `///`, `@param`, `@return`, `@brief` and other common tags
- **mdbook Integration**: Generates complete mdbook structure or works as an mdbook preprocessor
- **Watch Mode**: Auto-regenerates documentation on file changes with optional live preview
- **Cross-References**: Automatic linking between types and functions in generated docs
- **C and C++ Support**: Handles both C and C++ header files with appropriate parsers

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

For a reproducible development environment:

```bash
# Install devbox if not already installed
curl -fsSL https://get.jetpack.io/devbox | bash

# Enter the development shell
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

Stig can run as an mdbook preprocessor, allowing you to embed API documentation directly in your mdbook chapters.

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

### Configuration File

Stig looks for `stig.toml` in the current directory. CLI arguments override config file settings.

```toml
title = "My Library API"
output = "docs"
format = "mdbook"
inputs = ["include/*.h", "src/*.h"]
language = "en"
generate_intro = true
grouping = "by_header"  # by_header, by_prefix, or flat
authors = ["Your Name"]
```

## Supported Documentation Styles

Stig extracts documentation from several comment styles:

```c
/**
 * @brief Adds two integers.
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 */
int add(int a, int b);

/// Subtracts two integers.
/// @param a Minuend
/// @param b Subtrahend
int subtract(int a, int b);

struct Point {
    int x;  /**< X coordinate */
    int y;  ///< Y coordinate
};

enum Color {
    RED = 0,    /**< Red color */
    GREEN = 1,  ///< Green color
    BLUE = 2
};
```

## Output Structure

When generating mdbook format, stig creates:

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

## Requirements

- Zig 0.14.0+ (for building)
- mdbook (optional, for building generated documentation)

## License

MIT License
