# mdbook Integration

Stig integrates with mdbook in two ways: generating complete mdbook structures, or running as a preprocessor.

## Generating mdbook Structure

```bash
stig include/*.h -f mdbook -o docs/
```

This creates:

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

Build with:

```bash
cd docs && mdbook build
```

## Watch Mode

```bash
# Watch for changes and regenerate
stig include/*.h -f mdbook -o docs/ --watch

# Watch + live preview
stig include/*.h -f mdbook -o docs/ --serve
```

The `--serve` flag spawns `mdbook serve` automatically for hot reloading.

## Preprocessor Mode

Stig can run as an mdbook preprocessor, allowing you to embed API documentation directly in your mdbook chapters.

### Setup

Add to your `book.toml`:

```toml
[preprocessor.stig]
command = "stig preprocessor"
```

### Usage

In your markdown files:

```markdown
# API Reference

Here's the full API:

{{#stig api ../include/mylib.h}}

## Specific Function

{{#stig function my_function}}

## Specific Type

{{#stig struct MyStruct}}
```

### Directives

| Directive | Description |
|-----------|-------------|
| `{{#stig api <file>}}` | Embed full API from file |
| `{{#stig function <name>}}` | Embed specific function |
| `{{#stig struct <name>}}` | Embed specific struct |
| `{{#stig class <name>}}` | Embed specific class |
| `{{#stig enum <name>}}` | Embed specific enum |

### Example

Given `mylib.h`:

```c
/**
 * @brief Adds two integers
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 */
int add(int a, int b);
```

And in your chapter:

```markdown
# Math Functions

{{#stig function add}}
```

Produces:

---

### `add`

```c
int add(int a, int b);
```

Adds two integers

**Parameters:**
- `a`: First operand
- `b`: Second operand

**Returns:** Sum of a and b

---

## Cross-References

When generating mdbook output, stig creates cross-reference links between types.

For example, if a function returns `Point2`:

```cpp
Point2 get_origin();
```

The `Point2` in the output will link to its definition page.

## Custom Styling

The generated markdown uses standard elements that work with mdbook themes:

- Headers for type/function names
- Code blocks for signatures
- Bold for section headers
- Lists for parameters
- Inline code for type names
