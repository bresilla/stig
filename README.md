# Stig

Tree-sitter based C and C++ documentation generator focused on header files and Doxygen-style comments.

## Overview

Stig parses C and C++ headers with Tree-sitter, extracts Doxygen-style documentation, and produces Markdown, mdBook, HTML, or JSON output. Documentation checks and linting help enforce coverage requirements, and an LSP mode provides real-time diagnostics in editors. Implementation files (`.cpp`, `.cc`, `.cxx`) are skipped automatically so documentation stays with declarations in headers (`.h`, `.hpp`, `.hxx`, `.hh`, `.H`).

## Features

- Header-first parsing with Tree-sitter (no libclang dependency)
- Multiple output formats: Markdown, mdBook, HTML, JSON
- Cross-references, snippet extraction, Mermaid diagrams, optional Godbolt links
- Coverage analysis and linting with configurable thresholds
- Language Server Protocol support (`stig check` with no arguments)
- Watch mode with incremental caching for mdBook generation
- mdBook preprocessor integration
- Configurable behaviour through `stig.toml`

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

# Start the LSP server for editor integration (stdin/stdout)
stig check
```

> Stig only processes header files. Any `.cpp`, `.cc`, or `.cxx` file is reported as skipped so that documentation remains in headers alongside declarations.

## Usage

### Generate documentation (`stig generate`)

```
stig generate [OPTIONS] <INPUT_FILES>...
stig [OPTIONS] <INPUT_FILES>...    # generate is the default subcommand
```

Common options:

- `-o, --output <PATH>`: Output file or directory (default: stdout for Markdown/HTML/JSON)
- `-f, --format <FMT>`: `markdown`, `mdbook`, `json`, or `html` (default: `markdown`)
- `--title <TITLE>`: Document title for mdBook/HTML output
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

### Language Server Protocol (LSP)

Running `stig check` with no additional arguments starts the Language Server Protocol server over standard input/output. The server reuses the same coverage and lint engines that power the CLI, so the thresholds and toggles in `stig.toml` immediately affect editor diagnostics. Only header files are analyzed; when an implementation file is opened Stig clears diagnostics to avoid false positives.

Use any editor that supports stdio-based LSP servers. Configure it to execute `stig check` in the project root (or a directory containing `stig.toml`).

Example Neovim configuration:

```lua
vim.lsp.start({
  name = "stig",
  cmd = { "stig", "check" },
  root_dir = vim.fs.dirname(vim.fs.find({ "stig.toml" }, { upward = true })[1]),
})
```

Example `coc.nvim` or VS Code style command:

```json
{
  "command": "stig",
  "args": ["check"],
  "options": {
    "cwd": "${workspaceRoot}"
  }
}
```

Diagnostics include:

- Missing `@brief`, `@param`, `@tparam`, and `@return` documentation
- Coverage failures based on the configured minimum percentage
- Broken cross references or invalid snippet references
- Coverage and lint warnings promoted to errors when `--strict` (or `lint.treat_warnings_as_errors`) is enabled

### mdBook preprocessor (`stig preprocessor`)

```
stig preprocessor
```

The preprocessor reads JSON from stdin and writes JSON to stdout. It allows Stig to be wired into mdBook pipelines. Use the `supports` subcommand expected by mdBook by invoking `stig supports` (handled internally as a preprocessor mode).

### Version and help

- `stig --help`, `stig help`, or `stig <command> --help` for usage details
- `stig --version` to print the program version

## Configuration (`stig.toml`)

Stig looks for `stig.toml` in the current directory. CLI flags override configuration values. A minimal example:

```toml
title = "My Library API"
format = "mdbook"
output_dir = "docs"
inputs = ["include/**/*.hpp"]

generate_intro = true
grouping = "by_header"

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
check_cross_references = true

[godbolt]
enabled = true
compiler = "g132"
options = "-O2 -std=c++20"
link_text = "Run on Compiler Explorer"
```

See `config.zig` for all supported keys, including module grouping, external documentation links, and output customization.

## Doc comment support

Stig understands standard Doxygen-style tags such as `@brief`, `@details`, `@param`, `@tparam`, `@return`, `@throws`, `@see`, `@note`, `@warning`, `@deprecated`, `@since`, `@example`, and `@code`/`@endcode`. Both `@tag` and `\tag` forms are accepted. Additional commands include `@ref` for cross references, `@snippet` for embedding external code blocks, `@copydoc`, `@group`, `@page`, `@mainpage`, and `@mermaid`/`@endmermaid` for diagrams.

## Watch mode and incremental builds

When generating mdBook output without `--force`, Stig caches file contents and parsed modules in `.stig-cache`. Only changed headers are reparsed, which keeps watch-mode rebuilds fast. Use `--force` to ignore the cache.

## Linting and coverage

`stig check` combines coverage analysis and linting:

- Coverage tracks documented versus undocumented entities by type and reports missing parameter, template parameter, and return documentation.
- Linting validates comment quality (brief length, missing sections, broken references). Enable strict mode to treat warnings as build failures.

The compiler-style format (`-f compiler`) is suitable for CI systems that expect `file:line:col: severity: message` diagnostics.

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

## License

Stig is distributed under the MIT license. See `LICENSE` for the complete text.

## Acknowledgments

- Zig language and standard library
- Tree-sitter parsing framework
- Doxygen and Standardese for documentation tag conventions
