# Getting Started

## Installation

### Build from Source

Requires Zig 0.14.0 or later.

```bash
git clone https://github.com/bresilla/stig.git
cd stig
zig build -Doptimize=ReleaseFast
```

The binary will be at `zig-out/bin/stig`.

### Using Make

```bash
make build
make install  # installs to ~/.local/bin
```

## Basic Usage

### Generate Markdown

```bash
# Single file to stdout
stig include/mylib.h

# Multiple files to single output
stig include/*.h -o api.md

# Specific files
stig src/types.h src/functions.h -o docs.md
```

### Generate mdbook

```bash
# Create mdbook structure
stig include/*.h -f mdbook -o docs/

# Build the book
cd docs && mdbook build

# Or serve locally
cd docs && mdbook serve
```

### Watch Mode

```bash
# Watch for changes
stig include/*.h -f mdbook -o docs/ --watch

# Watch + live preview (spawns mdbook serve)
stig include/*.h -f mdbook -o docs/ --serve
```

## Project Configuration

Create a `stig.toml` in your project root:

```toml
title = "My Library API"
output = "docs"
format = "mdbook"
inputs = ["include/*.h", "include/*.hpp"]
```

Then just run:

```bash
stig
```

## Output Structure

When using mdbook format, stig creates:

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

- **functions/** - Free functions grouped by header file
- **types/** - Structs, classes, enums, typedefs grouped by header
- **macros/** - Macro definitions grouped by header
