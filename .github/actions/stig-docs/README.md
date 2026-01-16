# Stig Documentation Generator Action

A GitHub Action for generating C/C++ documentation using [Stig](https://github.com/bresilla/stig).

## Features

- 🚀 Automatic documentation generation from C/C++ headers
- 📚 Multiple output formats: Markdown, mdbook, JSON, HTML
- 📊 Built-in coverage checking
- ⚙️ Configurable via `stig.toml`
- 🎨 Customizable titles and options

## Usage

### Basic Example

```yaml
name: Documentation

on:
  push:
    branches: [main]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate Documentation
        uses: ./.github/actions/stig-docs
        with:
          input: 'include/*.hpp'
          output: 'docs'
          format: 'mdbook'
          title: 'My Library API'
```

### With Coverage Check

```yaml
- name: Generate Documentation with Coverage
  uses: ./.github/actions/stig-docs
  with:
    input: 'include/**/*.hpp'
    output: 'docs'
    format: 'mdbook'
    coverage: 'true'
    coverage-threshold: '80'
```

### With Custom Config

```yaml
- name: Generate Documentation
  uses: ./.github/actions/stig-docs
  with:
    input: 'src/*.h'
    output: 'api-docs'
    config: 'stig.toml'
```

### Deploy to GitHub Pages

```yaml
jobs:
  docs:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate Documentation
        uses: ./.github/actions/stig-docs
        with:
          input: 'include/*.hpp'
          output: 'docs'
          format: 'mdbook'
      
      - name: Install mdbook
        run: cargo install mdbook
      
      - name: Build mdbook
        run: mdbook build docs
      
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        if: github.ref == 'refs/heads/main'
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: docs/book
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `input` | Input files or glob pattern | Yes | - |
| `output` | Output directory or file | Yes | `docs` |
| `format` | Output format (markdown, mdbook, json, html) | No | `mdbook` |
| `title` | Documentation title | No | `API Documentation` |
| `config` | Path to stig.toml config file | No | - |
| `zig-version` | Zig version for building Stig | No | `0.13.0` |
| `stig-version` | Stig version (git ref or "latest") | No | `latest` |
| `coverage` | Run coverage check | No | `false` |
| `coverage-threshold` | Minimum coverage percentage | No | `80` |

## Outputs

| Output | Description |
|--------|-------------|
| `output-path` | Path to generated documentation |
| `coverage` | Documentation coverage percentage (if coverage enabled) |

## Examples

### Multiple Formats

```yaml
- name: Generate Markdown
  uses: ./.github/actions/stig-docs
  with:
    input: 'include/*.hpp'
    output: 'docs/api.md'
    format: 'markdown'

- name: Generate JSON
  uses: ./.github/actions/stig-docs
  with:
    input: 'include/*.hpp'
    output: 'docs/api.json'
    format: 'json'
```

### Matrix Build

```yaml
jobs:
  docs:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        format: [markdown, mdbook, json, html]
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate Documentation
        uses: ./.github/actions/stig-docs
        with:
          input: 'include/*.hpp'
          output: 'docs-${{ matrix.format }}'
          format: ${{ matrix.format }}
```

## Configuration

Create a `stig.toml` file in your repository:

```toml
title = "My Library API"
format = "mdbook"
output = "docs"

[coverage]
min_coverage = 80
require_param_docs = true
require_return_docs = true

[output]
show_source_location = true
code_language = "cpp"
```

## License

MIT
