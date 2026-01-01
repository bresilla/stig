# Stig CMake Integration

This directory contains CMake modules for integrating Stig documentation generation into CMake-based projects.

## Installation

### Option 1: System-wide Installation

```bash
# Build and install stig
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/stig /usr/local/bin/

# Install CMake module
sudo mkdir -p /usr/local/share/stig/cmake
sudo cp cmake/FindStig.cmake /usr/local/share/stig/cmake/
```

### Option 2: Project-local Installation

Copy the `FindStig.cmake` file to your project's cmake directory:

```bash
mkdir -p your-project/cmake
cp cmake/FindStig.cmake your-project/cmake/
```

## Usage

### Basic Example

```cmake
cmake_minimum_required(VERSION 3.14)
project(MyLibrary)

# Add stig cmake module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

# Find stig
find_package(Stig REQUIRED)

# Add documentation target
stig_add_docs(my_docs
    SOURCES
        include/*.hpp
        src/*.hpp
    OUTPUT ${CMAKE_BINARY_DIR}/docs
    FORMAT mdbook
    TITLE "My Library API"
)
```

Build documentation:
```bash
cmake -B build
cmake --build build --target my_docs
```

### Advanced Example

```cmake
# Add documentation with custom configuration
stig_add_docs(api_docs
    SOURCES
        ${CMAKE_SOURCE_DIR}/include/mylib/*.hpp
        ${CMAKE_SOURCE_DIR}/include/mylib/core/*.hpp
    OUTPUT ${CMAKE_BINARY_DIR}/api-docs
    FORMAT mdbook
    TITLE "MyLib API Reference"
    CONFIG ${CMAKE_SOURCE_DIR}/stig.toml
    FORCE  # Force rebuild even if files haven't changed
    WATCH  # Also create a watch target
)

# This creates two targets:
# - api_docs: Build documentation once
# - api_docs_watch: Watch for changes and rebuild automatically
```

### With CTest Integration

```cmake
enable_testing()

# Add documentation build as a test
add_test(NAME docs_build
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target my_docs
)

# Run tests including documentation build
# cmake --build build --target test
```

### Optional Documentation

Make documentation optional for users who don't have stig installed:

```cmake
option(BUILD_DOCS "Build documentation with stig" ON)

if(BUILD_DOCS)
    find_package(Stig QUIET)
    
    if(STIG_FOUND)
        stig_add_docs(docs
            SOURCES include/*.hpp
            OUTPUT ${CMAKE_BINARY_DIR}/docs
            FORMAT mdbook
            TITLE "API Documentation"
        )
        message(STATUS "Documentation target 'docs' configured")
    else()
        message(STATUS "Stig not found - documentation disabled")
    endif()
endif()
```

## Function Reference

### `stig_add_docs(TARGET_NAME ...)`

Creates a custom target for generating documentation with stig.

**Arguments:**

- `TARGET_NAME` (required): Name of the CMake target to create
- `SOURCES` (required): List of source files or glob patterns
- `OUTPUT` (optional): Output directory (default: `${CMAKE_CURRENT_BINARY_DIR}/docs`)
- `FORMAT` (optional): Output format - `mdbook`, `markdown`, `json`, or `html` (default: `mdbook`)
- `TITLE` (optional): Documentation title (default: "API Documentation")
- `CONFIG` (optional): Path to stig.toml configuration file
- `FORCE` (optional): Force rebuild even if files haven't changed
- `WATCH` (optional): Create an additional `${TARGET_NAME}_watch` target
- `DEPENDS` (optional): Additional dependencies for the target

**Example:**

```cmake
stig_add_docs(my_docs
    SOURCES
        include/core/*.hpp
        include/utils/*.hpp
    OUTPUT ${CMAKE_BINARY_DIR}/documentation
    FORMAT mdbook
    TITLE "My Library v${PROJECT_VERSION}"
    CONFIG ${CMAKE_SOURCE_DIR}/docs/stig.toml
    DEPENDS generate_headers  # Wait for header generation
    FORCE
    WATCH
)
```

## Variables

After `find_package(Stig)`, the following variables are available:

- `STIG_FOUND`: TRUE if stig was found
- `STIG_EXECUTABLE`: Path to the stig executable
- `STIG_VERSION`: Version of stig (e.g., "0.1.0")

## Environment Variables

You can set `STIG_ROOT` to help CMake find stig:

```bash
export STIG_ROOT=/path/to/stig/installation
cmake -B build
```

Or pass it directly to CMake:

```bash
cmake -B build -DSTIG_ROOT=/path/to/stig
```

## Examples

See the `test/complex/CMakeLists.txt` file for a complete working example.

## Troubleshooting

### "Stig not found"

Make sure stig is in your PATH or set `STIG_ROOT`:

```bash
# Check if stig is in PATH
which stig

# If not, set STIG_ROOT
export STIG_ROOT=/path/to/stig/installation
```

### Glob patterns not working

CMake evaluates glob patterns at configure time. If you add new files, you need to reconfigure:

```bash
cmake -B build  # Reconfigure to pick up new files
```

### Documentation not rebuilding

Use the `FORCE` option to force rebuild:

```cmake
stig_add_docs(docs
    SOURCES include/*.hpp
    FORCE  # Always rebuild
)
```

## License

Same as Stig - see LICENSE file in the root directory.
