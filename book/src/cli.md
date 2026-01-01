# CLI Reference

```
stig [OPTIONS] <INPUT_FILES>...
```

## Arguments

### INPUT_FILES

C/C++ header files to process. Supports glob patterns.

```bash
stig include/mylib.h
stig include/*.h
stig src/**/*.hpp
```

## Options

### -o, --output PATH

Output file or directory.

- For markdown format: output file path (default: stdout)
- For mdbook format: output directory (default: "docs")

```bash
stig input.h -o api.md
stig input.h -f mdbook -o docs/
```

### -f, --format FORMAT

Output format selection.

| Format | Description |
|--------|-------------|
| `markdown` | Single markdown file (default) |
| `mdbook` | mdbook directory structure |

```bash
stig input.h -f markdown
stig input.h -f mdbook -o docs/
```

### --title TITLE

Book title for mdbook format.

```bash
stig input.h -f mdbook --title "My Library API"
```

### -c, --config FILE

Path to configuration file.

```bash
stig -c myconfig.toml
stig -c path/to/stig.toml
```

Default: `stig.toml` in current directory.

### -w, --watch

Watch for file changes and regenerate documentation.

```bash
stig include/*.h -f mdbook -o docs/ --watch
```

### --serve

Watch mode with live preview. Spawns `mdbook serve` for hot reloading.

```bash
stig include/*.h -f mdbook -o docs/ --serve
```

### -h, --help

Show help message.

### -v, --version

Show version information.

## Subcommands

### preprocessor

Run as mdbook preprocessor. Reads JSON from stdin, writes to stdout.

```bash
stig preprocessor
```

Used in `book.toml`:

```toml
[preprocessor.stig]
command = "stig preprocessor"
```

## Examples

```bash
# Basic usage
stig input.h                              # Output to stdout
stig input.h -o output.md                 # Output to file

# Multiple files
stig src/*.h -o api.md                    # Glob pattern
stig a.h b.h c.h -o combined.md           # Multiple files

# mdbook generation
stig src/*.h -f mdbook -o docs/           # Generate mdbook
stig src/*.h -f mdbook --title "My API"   # With title

# Watch modes
stig src/*.h -f mdbook -o docs/ --watch   # Watch for changes
stig src/*.h -f mdbook -o docs/ --serve   # Watch + live preview

# Config file
stig                                       # Use stig.toml
stig -c custom.toml                        # Custom config
```
