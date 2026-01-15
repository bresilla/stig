# Changelog

## [Unreleased]

### Features

- Add SARIF output format for GitHub code scanning integration (`stig check --format sarif`)
- Add `stig render` subcommand for JSON-to-markdown conversion pipeline
- Add JSON v2 document model schema for improved tool interoperability
- Add multi-file and single-file output writers for flexible documentation structure
- Improve Doxygen tag detection to include @deprecated, @note, @warning, @see, @throws, @since, @author, @version, @tparam, @code, @retval
- Add configurable file size limits via `[limits]` config section

### Bug Fixes

- Fix version mismatch between cli.zig and VERSION file
- Fix min-coverage validation to allow 0% and reject negative values
- Fix CLI help text to match actual config field names
- Fix placeholder URLs in init template and sample configs

### Improvements

- Add actionable error messages with hints for common issues
- Add logging for silent error handling throughout codebase
- Add file size limit context in error messages
- Fix bounds checking in LSP server block comment detection
- Document serve mode requirements in help text
- Add error logging in file writers (single.zig, multi.zig)
- Add error logging for path formatting failures in snippet.zig
- Add JSON parse error logging in LSP jsonrpc.zig
- Add LSP message size limit (100MB) to prevent DoS
- Add Content-Length parse error logging in LSP
- Increase cache manifest buffer sizes for long paths
- Add integer bounds checking for LSP line numbers
- Add error logging in xref.zig symbol table cleanup
- Add error logging in cache.zig dependency resolution
- Add error logging in LSP parser for C/C++ files
- Add error logging in preprocessor stdin reading

## [0.0.2] - 2026-01-03

### <!-- 0 -->⛰️  Features

- LSP and `stig check` subcommand for documentation analysis
- Add Compiler Explorer (Godbolt) integration
- Add GitHub Actions integration
- Add call graph infrastructure
- Add @ref tag for explicit cross-references
- Add more P2 features - inheritance diagrams, symbol index, @code blocks, @page/@mainpage
- Add support for custom @page Doxygen tag
- Add support for Doxygen @code, @page, and inheritance diagrams
- Add P2 features - @attention/@important, @date/@copyright, @mermaid, incremental builds
- Implement linting, coverage, JSON output, and snippet processing
- Render @output_section headers for ungrouped functions
- Render @file documentation at top of page
- Apply blacklist_namespace and blacklist_pattern filtering in markdown output
- Parse blacklist and extract_private/protected config from TOML
- Add output customization options (source location, access specifiers, synopsis style)
- Add custom section name configuration for localization
- Add extract_private and extract_protected configuration options
- Add namespace/entity blacklist configuration
- Implement @copydoc command for documentation inheritance
- Implement scoped name lookup with * and ? prefix
- Implement signature-based unique names for overload disambiguation
- Implement external documentation links for std:: and custom prefixes
- Implement @output_section command for synopsis section headers
- Implement @file command for file-level documentation
- Implement @entity command for remote documentation
- Implement @module command for logical module organization
- Implement @unique_name command for custom link targets
- Implement @group command for grouping related functions
- Implement @synopsis command for custom signature display
- Implement @exclude command
- Add @ingroup and @defgroup support
- Improve variadic template parameter support
- Parse friend declarations
- Parse C++ attributes from declarations
- Add C++ standard-style section tags
- Support backslash command prefix for Doxygen compatibility
- Add @retval tag support for multiple return value documentation
- Add @tparam tag support for template parameter documentation
- Extract and render base classes with access specifiers
- Parse and document C++ templates
- Parse and document C++ classes, methods, and concepts
- Rename project from Stinger to Stig
- Add C++ class documentation generation
- Parse template declarations and apply docstrings
- Enable cross-reference links in markdown output
- Add incremental updates with file caching
- Add include directive for embedding code examples
- Add watch mode with live reload
- Add C++ grammar support
- Add mdbook preprocessor mode
- Add macro documentation support
- Add configuration file support (stinger.toml)
- Add cross-reference link generation
- Enhanced Doxygen tag parsing
- Add mdbook structure generation
- Add CLI interface
- Add markdown output generator
- Add docstring extraction and association
- Initial stinger implementation with tree-sitter C parser

### <!-- 1 -->🐛 Bug Fixes

- Correct project version to 0.0.1
- Report correct line numbers for method issues
- Extract custom pages in C parser
- Extract parameter names and types from complex C++ declarations
- Disable GPA safety to suppress leak warnings
- Use expanded glob files for processing, not CLI args
- Add glob pattern expansion and fix config format handling

### <!-- 2 -->🚜 Refactor

- Add CMake integration and HTML output format
- Restructure complex test as standalone C++ project
- Use zig-toml library for TOML config parsing
- Use argonaut library for CLI argument parsing

### <!-- 3 -->📚 Documentation

- Comprehensive README and SKILL.md update
- Add filtering behavior and output_section examples to README
- Update README with Standardese feature parity documentation
- Documentations
- Add initial README.md file

### <!-- 6 -->🧪 Testing

- Add complex C++ spatial geometry test fixtures
- Add comprehensive unit tests for parser, docstring, and markdown
- Add comprehensive test fixtures for parser validation

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Add boilerplate for project and changelog
- Clean up test output directories and restore docs
- Add Makefile for Zig build system automation
- Remove generated book files

### Build

- Add release binaries workflow


### <!-- 0 -->⛰️  Features

- LSP and `stig check` subcommand for documentation analysis
- Add Compiler Explorer (Godbolt) integration
- Add GitHub Actions integration
- Add call graph infrastructure
- Add @ref tag for explicit cross-references
- Add more P2 features - inheritance diagrams, symbol index, @code blocks, @page/@mainpage
- Add support for custom @page Doxygen tag
- Add support for Doxygen @code, @page, and inheritance diagrams
- Add P2 features - @attention/@important, @date/@copyright, @mermaid, incremental builds
- Implement linting, coverage, JSON output, and snippet processing
- Render @output_section headers for ungrouped functions
- Render @file documentation at top of page
- Apply blacklist_namespace and blacklist_pattern filtering in markdown output
- Parse blacklist and extract_private/protected config from TOML
- Add output customization options (source location, access specifiers, synopsis style)
- Add custom section name configuration for localization
- Add extract_private and extract_protected configuration options
- Add namespace/entity blacklist configuration
- Implement @copydoc command for documentation inheritance
- Implement scoped name lookup with * and ? prefix
- Implement signature-based unique names for overload disambiguation
- Implement external documentation links for std:: and custom prefixes
- Implement @output_section command for synopsis section headers
- Implement @file command for file-level documentation
- Implement @entity command for remote documentation
- Implement @module command for logical module organization
- Implement @unique_name command for custom link targets
- Implement @group command for grouping related functions
- Implement @synopsis command for custom signature display
- Implement @exclude command
- Add @ingroup and @defgroup support
- Improve variadic template parameter support
- Parse friend declarations
- Parse C++ attributes from declarations
- Add C++ standard-style section tags
- Support backslash command prefix for Doxygen compatibility
- Add @retval tag support for multiple return value documentation
- Add @tparam tag support for template parameter documentation
- Extract and render base classes with access specifiers
- Parse and document C++ templates
- Parse and document C++ classes, methods, and concepts
- Rename project from Stinger to Stig
- Add C++ class documentation generation
- Parse template declarations and apply docstrings
- Enable cross-reference links in markdown output
- Add incremental updates with file caching
- Add include directive for embedding code examples
- Add watch mode with live reload
- Add C++ grammar support
- Add mdbook preprocessor mode
- Add macro documentation support
- Add configuration file support (stinger.toml)
- Add cross-reference link generation
- Enhanced Doxygen tag parsing
- Add mdbook structure generation
- Add CLI interface
- Add markdown output generator
- Add docstring extraction and association
- Initial stinger implementation with tree-sitter C parser

### <!-- 1 -->🐛 Bug Fixes

- Report correct line numbers for method issues
- Extract custom pages in C parser
- Extract parameter names and types from complex C++ declarations
- Disable GPA safety to suppress leak warnings
- Use expanded glob files for processing, not CLI args
- Add glob pattern expansion and fix config format handling

### <!-- 2 -->🚜 Refactor

- Add CMake integration and HTML output format
- Restructure complex test as standalone C++ project
- Use zig-toml library for TOML config parsing
- Use argonaut library for CLI argument parsing

### <!-- 3 -->📚 Documentation

- Comprehensive README and SKILL.md update
- Add filtering behavior and output_section examples to README
- Update README with Standardese feature parity documentation
- Documentations
- Add initial README.md file

### <!-- 6 -->🧪 Testing

- Add complex C++ spatial geometry test fixtures
- Add comprehensive unit tests for parser, docstring, and markdown
- Add comprehensive test fixtures for parser validation

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Clean up test output directories and restore docs
- Add Makefile for Zig build system automation
- Remove generated book files

### Build

- Add release binaries workflow

<!-- WARP -->
