# Configuration

Stig can be configured via a `stig.toml` file in your project root. CLI arguments override config file settings.

## Configuration File

```toml
# Project title for documentation
title = "My Library API"

# Output directory (for mdbook) or file (for markdown)
output = "docs"

# Output format: "markdown" or "mdbook"
format = "mdbook"

# Input file patterns (glob patterns supported)
inputs = ["include/*.h", "include/*.hpp", "src/**/*.h"]

# Language for mdbook
language = "en"

# Whether to generate introduction page
generate_intro = true

# Grouping strategy: "by_header", "by_prefix", or "flat"
grouping = "by_header"

# Authors list
authors = ["Your Name"]
```

## Configuration Options

### title

The title used for the generated documentation. For mdbook, this becomes the book title.

```toml
title = "My Awesome Library"
```

### output

Output destination. For markdown format, this is a file path. For mdbook, this is a directory.

```toml
output = "docs"           # mdbook directory
output = "api.md"         # markdown file
```

### format

Output format selection.

```toml
format = "mdbook"    # Generate mdbook structure
format = "markdown"  # Generate single markdown file
```

### inputs

Array of input file patterns. Supports glob patterns.

```toml
inputs = [
    "include/*.h",
    "include/*.hpp",
    "src/**/*.h"
]
```

### grouping

How to organize the generated documentation.

```toml
grouping = "by_header"  # Group by source header file (default)
grouping = "by_prefix"  # Group by function/type name prefix
grouping = "flat"       # No grouping, single list
```

### generate_intro

Whether to generate an introduction page for mdbook.

```toml
generate_intro = true   # Generate introduction.md
generate_intro = false  # Skip introduction page
```

## Section Styles

Stig supports multiple configuration section styles for flexibility:

### Root Level

```toml
title = "My API"
output = "docs"
format = "mdbook"
```

### [stig] Section

```toml
[stig]
title = "My API"
output = "docs"
format = "mdbook"
inputs = ["include/*.h"]
```

### [book] Section (mdbook compatibility)

```toml
[book]
title = "My API"
authors = ["Author Name"]
language = "en"
```

All styles can be mixed. Precedence: root level > [stig] > [book]
