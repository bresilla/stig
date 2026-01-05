# Stig

Tree-sitter based C and C++ documentation generator focused on header files and Doxygen-style comments.

## Overview

Stig parses C and C++ headers with Tree-sitter, extracts Doxygen-style documentation, and produces Markdown, mdBook, or JSON output. Documentation checks and linting help enforce coverage requirements, and an LSP mode provides real-time diagnostics in editors. Implementation files (`.cpp`, `.cc`, `.cxx`) are skipped automatically so documentation stays with declarations in headers (`.h`, `.hpp`, `.hxx`, `.hh`, `.H`).

## Features

### Core Features
- **Header-first parsing** with Tree-sitter (no libclang dependency)
- **Multiple output formats**: Markdown, mdBook, JSON
- **Cross-references** with `@ref`, `@see`, `@copydoc` support
- **Snippet extraction** from external files with multi-language comment support
- **Mermaid diagrams** embedded in documentation
- **Godbolt integration** for live code examples
- **Coverage analysis** and **linting** with configurable thresholds
- **Language Server Protocol** support for editor integration
- **Watch mode** with native file watching and incremental caching
- **mdBook preprocessor** integration

### Parser Features
- Full C and C++ header parsing via Tree-sitter
- **Union type** parsing and documentation
- **Template support** with `requires` clause extraction
- **Virtual function specifiers**: `override`, `final`, `pure virtual`
- **Namespace** and **class** hierarchy tracking
- **Enum** and **typedef/using** alias support

### Docstring Features
- Standard Doxygen tags: `@brief`, `@details`, `@param`, `@tparam`, `@return`, `@retval`
- Additional tags: `@throws`, `@see`, `@note`, `@warning`, `@deprecated`, `@since`, `@author`
- **Multi-line tag continuation** with proper line joining
- **Escaped characters**: `@@` and `\\` for literal @ and \
- **Group support**: `@defgroup`, `@addtogroup`, `@ingroup`
- **Cross-references**: `@ref` extraction from all tag content
- **Code blocks**: `@code`/`@endcode`, `@mermaid`/`@endmermaid`
- **Snippet inclusion**: `@snippet` with multi-language comment style support

### LSP Features
- Real-time diagnostics for documentation issues
- **Auto-completion** for 37 Doxygen tags with snippets
- **Quick fixes** (code actions) for common issues:
  - Generate documentation stubs for undocumented entities
  - Add missing `@param` documentation
  - Add missing `@return` documentation
  - Fix mismatched parameter names
- **Incremental document sync** for better performance
- Dedicated `stig lsp` command for LSP server mode

### Linting Features
- Missing documentation detection (brief, param, tparam, return)
- **Duplicate `@param`** detection
- **Empty description** checks
- Broken cross-reference validation
- **Per-rule configuration** with severity overrides:
  ```toml
  [lint.rules]
  W001 = "ignore"    # Ignore missing docs
  W003 = "error"     # Treat missing @param as error
  E001 = "warning"   # Downgrade param mismatch to warning
  ```

### Watch Mode Features
- **Native file watching** using inotify on Linux (polling fallback on other platforms)
- **Ignore patterns** for filtering out build artifacts:
  ```toml
  [watch]
  debounce_ms = 200
  ignore_patterns = [".git/**", "node_modules/**", "build/**", "*.o"]
  ```
- Incremental rebuilds with file caching
- Automatic mdbook serve integration

### Snippet Comment Styles
Stig supports multiple comment styles for snippet markers based on file type:
- **C/C++/Zig/Rust/Go/Java/JS/TS**: `// [anchor]`
- **Python/Shell/Ruby/YAML/Makefile**: `# [anchor]`
- **CSS/SCSS/LESS**: `/* [anchor] */`
- **HTML/XML/SVG**: `<!-- [anchor] -->`
- **SQL/Lua**: `-- [anchor]`

## Installation

Requires Zig 0.14.0 or newer.

```bash
git clone https://github.com/bresilla/stig.git
cd stig
zig build -Doptimize=ReleaseFast
```

The executable is written to `zig-out/bin/stig`.

### Development environment (Devbox + Nix)

```bash
curl -fsSL https://get.jetpack.io/devbox | bash
cd stig
devbox shell
```

## Quick start

```bash
# Generate markdown to stdout
stig include/mylib.h

# Generate an mdBook structure
stig generate include/*.h -f mdbook -o docs/ --title "My Library API"

# Check documentation coverage (human-readable)
stig check include/*.h

# Compiler-style diagnostics (file:line:col)
stig check -f compiler include/*.h

# Watch headers and regenerate mdBook output
stig generate include/*.h -f mdbook -o docs/ --watch

# Start the LSP server for editor integration
stig lsp
```

> Stig only processes header files. Any `.cpp`, `.cc`, or `.cxx` file is reported as skipped so that documentation remains in headers alongside declarations.

## Usage

### Generate documentation (`stig generate`)

```
stig generate [OPTIONS] <INPUT_FILES>...
stig [OPTIONS] <INPUT_FILES>...    # generate is the default subcommand
```

Common options:

- `-o, --output <PATH>`: Output file or directory (default: stdout for Markdown/JSON)
- `-f, --format <FMT>`: `markdown`, `mdbook`, or `json` (default: `markdown`)
- `--title <TITLE>`: Document title for mdBook output
- `-c, --config <FILE>`: Alternate configuration file (default: `stig.toml`)
- `-w, --watch`: Watch for file changes and regenerate (mdBook only)
- `--serve`: Watch plus `mdbook serve` for live preview (implies `--watch`)
- `--force`: Ignore cache and rebuild everything (mdBook incremental mode)

Watch mode requires mdBook output and an output directory. Only `.h`/`.hpp`/`.hxx`/`.hh`/`.H` files are parsed; other files are logged as skipped.

### Check documentation (`stig check`)

```
stig check [OPTIONS] <INPUT_FILES>...
```

Options:

- `-c, --config <FILE>`: Configuration file (default: `stig.toml`)
- `-f, --format <FMT>`: `human`, `compiler`, `json` (default: `human`)
- `--min-coverage <N>`: Required coverage percentage (0-100)
- `--strict`: Treat warnings as errors (affects exit codes)

Exit codes:

- `0`: All checks passed
- `1`: Errors detected (undocumented entities, invalid references)
- `2`: Coverage below threshold or warnings present when `--strict` is set

### Language Server Protocol (`stig lsp`)

```
stig lsp
```

Starts the Language Server Protocol server over standard input/output. The server provides:

- **Real-time diagnostics** for documentation issues
- **Auto-completion** for Doxygen tags (`@brief`, `@param`, etc.) with snippet support
- **Code actions** for quick fixes (generate doc stubs, add missing params)
- **Incremental document sync** for efficient updates

The server reuses the same coverage and lint engines that power the CLI, so thresholds and toggles in `stig.toml` immediately affect editor diagnostics.

Example Neovim configuration:

```lua
vim.lsp.start({
  name = "stig",
  cmd = { "stig", "lsp" },
  root_dir = vim.fs.dirname(vim.fs.find({ "stig.toml" }, { upward = true })[1]),
})
```

Example VS Code / coc.nvim configuration:

```json
{
  "command": "stig",
  "args": ["lsp"],
  "options": {
    "cwd": "${workspaceRoot}"
  }
}
```

Diagnostics include:

- Missing `@brief`, `@param`, `@tparam`, and `@return` documentation
- Duplicate `@param` tags for the same parameter
- Empty descriptions in documentation tags
- Coverage failures based on the configured minimum percentage
- Broken cross references or invalid snippet references

### mdBook preprocessor (`stig preprocessor`)

```
stig preprocessor
```

The preprocessor reads JSON from stdin and writes JSON to stdout. It allows Stig to be wired into mdBook pipelines. Use the `supports` subcommand expected by mdBook by invoking `stig supports` (handled internally as a preprocessor mode).

### Version and help

- `stig --help`, `stig help`, or `stig <command> --help` for usage details
- `stig --version` to print the program version

## Configuration (`stig.toml`)

Stig looks for `stig.toml` in the current directory. CLI flags override configuration values. A comprehensive example:

```toml
title = "My Library API"
format = "mdbook"
output_dir = "docs"
inputs = ["include/**/*.hpp"]

generate_intro = true
grouping = "by_header"

# Filtering options
blacklist_namespace = ["detail", "internal", "impl"]
blacklist_pattern = ["*_internal", "test_*"]
extract_private = false
extract_protected = true

[coverage]
min_coverage = 85
require_param_docs = true
require_return_docs = true
require_tparam_docs = true

[lint]
enabled = true
require_brief = true
require_param_docs = true
require_return_docs = true
require_tparam_docs = true
check_cross_references = true
max_brief_length = 80
require_brief_period = false

# Per-rule severity overrides
[lint.rules]
W001 = "ignore"      # Ignore missing documentation warnings
W003 = "error"       # Treat missing @param as error
W005 = "warning"     # Missing @return as warning
E001 = "info"        # Param name mismatch as info

[watch]
debounce_ms = 100
ignore_patterns = [
    ".git/**",
    "node_modules/**",
    "build/**",
    "zig-out/**",
    "*.o",
    "*.obj"
]

[godbolt]
enabled = true
compiler = "g132"
options = "-O2 -std=c++20"
link_text = "Run on Compiler Explorer"
```

See `config.zig` for all supported keys, including module grouping, external documentation links, and output customization.

## Doc comment support

Stig understands standard Doxygen-style tags:

### Basic Tags
- `@brief` / `@short`: Brief description
- `@details`: Detailed description
- `@param` / `@p`: Parameter documentation
- `@tparam`: Template parameter documentation
- `@return` / `@returns`: Return value documentation
- `@retval`: Specific return value documentation

### Semantic Tags
- `@throws` / `@throw` / `@exception`: Exception documentation
- `@pre`: Preconditions
- `@post`: Postconditions
- `@requires`: Requirements (C++20 concepts)
- `@effects`: Side effects
- `@complexity`: Algorithmic complexity
- `@invariant`: Class invariants
- `@threadsafety` / `@sync`: Thread safety notes

### Informational Tags
- `@note`: Additional notes
- `@warning`: Warning messages
- `@deprecated`: Deprecation notices
- `@since`: Version introduced
- `@author`: Author information
- `@version`: Version information
- `@date`: Date information
- `@copyright`: Copyright notice
- `@see` / `@sa`: See also references
- `@todo`: TODO items
- `@bug`: Known bugs

### Cross-Reference Tags
- `@ref`: Cross-reference to another symbol
- `@copydoc`: Copy documentation from another symbol

### Grouping Tags
- `@defgroup`: Define a documentation group
- `@addtogroup`: Add to an existing group
- `@ingroup`: Mark entity as belonging to a group
- `@{` / `@}`: Group member markers

### Code Tags
- `@code` / `@endcode`: Code blocks
- `@snippet`: Include code from external file
- `@mermaid` / `@endmermaid`: Mermaid diagrams
- `@example`: Example code

### Other Tags
- `@file`: File-level documentation
- `@page` / `@mainpage`: Page documentation
- `@exclude`: Exclude from documentation
- `@synopsis`: Custom synopsis override
- `@unique_name`: Custom anchor name

Both `@tag` and `\tag` forms are accepted. Multi-line continuation is supported by indentation.

## Watch mode and incremental builds

When generating mdBook output without `--force`, Stig caches file contents and parsed modules in `.stig-cache`. Only changed headers are reparsed, which keeps watch-mode rebuilds fast. Use `--force` to ignore the cache.

Watch mode features:
- **Native file watching** using inotify on Linux for instant change detection
- **Polling fallback** on other platforms (200ms interval)
- **Ignore patterns** to filter out build artifacts and VCS directories
- **Debouncing** to coalesce rapid changes
- **Include dependency tracking** to rebuild when included headers change

## Linting and coverage

`stig check` combines coverage analysis and linting:

- **Coverage** tracks documented versus undocumented entities by type and reports missing parameter, template parameter, and return documentation.
- **Linting** validates comment quality:
  - Brief length limits
  - Missing required sections
  - Duplicate parameter documentation
  - Empty descriptions
  - Broken cross-references
  - Parameter name mismatches

The compiler-style format (`-f compiler`) is suitable for CI systems that expect `file:line:col: severity: message` diagnostics.

### Lint Rules

| Code | Severity | Description |
|------|----------|-------------|
| W001 | Warning | Missing documentation |
| W002 | Warning | Missing @brief |
| W003 | Warning | Missing @param for parameter |
| W004 | Warning | Missing @tparam for template parameter |
| W005 | Warning | Missing @return for non-void function |
| W006 | Warning | Empty description |
| W007 | Warning | Duplicate @param |
| E001 | Error | Parameter name mismatch |
| E002 | Error | Broken cross-reference |

## GitHub Actions

The repository includes `.github/actions/stig-docs`, which can be used from workflows:

```yaml
- name: Generate documentation
  uses: ./.github/actions/stig-docs
  with:
    input: "include/*.hpp"
    output: "docs"
    format: "mdbook"
    coverage: "true"
    coverage-threshold: "80"
```

Refer to `.github/actions/stig-docs/README.md` for full input descriptions.

## CMake integration

`cmake/FindStig.cmake` and accompanying helpers allow projects to invoke Stig from CMake. Example:

```cmake
find_package(Stig REQUIRED)

stig_add_docs(
    TARGET api_docs
    SOURCES include/**/*.hpp
    OUTPUT docs
    FORMAT mdbook
    TITLE "Project API"
)
```

Run `cmake --build . --target api_docs` to generate the documentation. See `cmake/README.md` for details.

## Recent Changes (v0.1.0)

### Phase 1: Cleanup & Removal
- Removed HTML output generator (1055 lines deleted)
- Extracted common parser utilities into shared module

### Phase 2: Critical Bug Fixes
- Fixed `getExternalLink` URL substitution bug
- Fixed Godbolt `generateSimpleUrl` encoding issues
- Added include dependency tracking to cache

### Phase 3: Parser Enhancements
- Added union type parsing
- Extract `requires` clause from templates
- Extract `override`/`final`/`pure virtual` specifiers
- Added comprehensive C++ parser tests

### Phase 4: Docstring Extraction Improvements
- Support multi-line tag continuation
- Support escaped `@@` and `\\` characters
- Extract `@ref` from all tag content
- Added `@defgroup` and `@addtogroup` support

### Phase 5: Lint & Coverage Improvements
- Added duplicate `@param` detection
- Added empty description checks
- Added per-rule lint configuration with severity overrides

### Phase 6: LSP Enhancements
- Added `textDocument/completion` for 37 Doxygen tags
- Added `textDocument/codeAction` for quick fixes
- Added incremental document sync
- Separated `stig lsp` from `stig check`

### Phase 7: Infrastructure & Performance
- Added OS-native file watching (inotify on Linux)
- Added watch mode ignore patterns
- Support multiple snippet comment styles (Python, Shell, CSS, HTML, SQL, etc.)

## License

Stig is distributed under the MIT license. See `LICENSE` for the complete text.

## Acknowledgments

- Zig language and standard library
- Tree-sitter parsing framework
- Doxygen and Standardese for documentation tag conventions
