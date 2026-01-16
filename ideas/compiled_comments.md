# Executable Documentation Proposal for Stig

## Background

This proposal is inspired by the blog post "What If Software Documentation Was Executable?" which identifies the core problem with traditional documentation: **it's static while software is dynamic**.

The key insight is that documentation should be:
1. **Verifiable** - You can run it to check if it's still valid
2. **Connected** - Linked to actual code, tests, and execution
3. **Self-updating** - Broken execution is immediately visible

## Current Stig Capabilities

Stig already implements several "executable documentation" concepts:

### Already Implemented

| Feature | Description | Executable Aspect |
|---------|-------------|-------------------|
| `@snippet` | Embeds code from external files | Real code, not copy-paste |
| `@test` | Links to test cases | Connects docs to verification |
| Godbolt | Links to Compiler Explorer | Code can be run online |
| `@mermaid` | Inline diagrams | Diagrams live with code |
| LSP Server | Real-time diagnostics | Immediate feedback |
| Coverage | Detects undocumented code | Drift detection |
| Watch Mode | Auto-regenerates | Stays current |
| `@ref` | Cross-references | Linked documentation |
| Linting | Validates doc quality | Quality enforcement |

## Proposed Enhancements

### Phase 1: Code Verification (High Priority)

#### 1.1 Compile Code Examples (`stig verify`)

Add a new subcommand that compiles `@code` blocks and `@snippet` content:

```bash
stig verify include/*.hpp
```

**Implementation:**
- Extract all `@code{.cpp}` blocks and `@snippet` references
- Generate a temporary compilation unit
- Compile with configurable compiler (g++, clang++)
- Report compilation errors with source location mapping

**Config:**
```toml
[verify]
enabled = true
compiler = "g++"
flags = ["-std=c++20", "-fsyntax-only"]
include_paths = ["include/"]
```

**New tag:**
```cpp
/**
 * @brief Calculates factorial
 * @code{.cpp,verify}
 * int result = factorial(5);  // This will be compiled!
 * assert(result == 120);
 * @endcode
 */
```

#### 1.2 Run Code Examples (`stig run`)

For examples that should actually execute:

```cpp
/**
 * @brief Prints hello world
 * @code{.cpp,run}
 * std::cout << "Hello, World!" << std::endl;
 * @endcode
 * @expect Hello, World!
 */
```

**New tags:**
- `@expect <output>` - Expected stdout
- `@expect_error <pattern>` - Expected stderr
- `@expect_exit <code>` - Expected exit code

### Phase 2: Test Integration (Medium Priority)

#### 2.1 Test Execution Status

Enhance `@test` to show pass/fail status:

```cpp
/**
 * @brief Sorts an array
 * @test test_sort_empty tests/test_sort.cpp
 * @test test_sort_single tests/test_sort.cpp
 */
```

**Output in docs:**
```markdown
### Tests
- [x] `test_sort_empty` (tests/test_sort.cpp:42) - PASSED
- [ ] `test_sort_single` (tests/test_sort.cpp:58) - FAILED
```

**Config:**
```toml
[verify.tests]
enabled = true
runner = "ctest"
build_dir = "build"
```

#### 2.2 Test Discovery

Auto-discover tests that reference documented functions:

```bash
stig check --discover-tests include/*.hpp
```

### Phase 3: Reference Validation (Medium Priority)

#### 3.1 Cross-Reference Verification

Already partially implemented in lint. Enhance to:
- Verify `@ref` targets exist
- Check external links are reachable
- Validate `@copydoc` sources

#### 3.2 API Contract Verification

For functions with `@pre`, `@post`, `@throws`:

```cpp
/**
 * @brief Divides two numbers
 * @pre b != 0
 * @throws std::invalid_argument if b is zero
 * @contract  // New tag to enable contract checking
 */
double divide(double a, double b);
```

### Phase 4: Freshness Detection (Lower Priority)

#### 4.1 Documentation Age Tracking

Track when documentation was last verified:

```bash
stig check --freshness include/*.hpp
```

Output:
```
shapes.hpp:
  Circle::area() - docs verified 2 days ago, code changed 1 day ago [STALE]
  Circle::perimeter() - docs verified 5 days ago, code unchanged [OK]
```

#### 4.2 Git Integration

```toml
[freshness]
enabled = true
max_age_days = 30
track_code_changes = true
```

## Implementation Plan

### New Files

```
src/
  verify.zig          # Code compilation/execution
  test_runner.zig     # Test execution integration
  freshness.zig       # Documentation age tracking
```

### CLI Changes

```
stig verify [OPTIONS] <FILES>...     # Compile/run code examples
  -c, --config <FILE>                # Config file
  --compile-only                     # Only check compilation
  --run                              # Actually execute examples
  --tests                            # Run referenced tests

stig check [OPTIONS] <FILES>...      # Existing, enhanced
  --discover-tests                   # Find tests for documented functions
  --freshness                        # Check documentation age
```

### Config Additions

```toml
[verify]
enabled = true
compiler = "g++"
std = "c++20"
flags = ["-Wall", "-Wextra"]
include_paths = ["include/"]
timeout_ms = 5000

[verify.tests]
enabled = true
runner = "ctest"  # or "catch2", "gtest", "doctest"
build_dir = "build"
test_pattern = "test_*"

[freshness]
enabled = false
max_age_days = 30
track_code_changes = true
```

### New Doxygen Tags

| Tag | Description |
|-----|-------------|
| `@code{.cpp,verify}` | Code block that should compile |
| `@code{.cpp,run}` | Code block that should execute |
| `@expect <output>` | Expected output from `@code{run}` |
| `@expect_error <pattern>` | Expected stderr pattern |
| `@expect_exit <code>` | Expected exit code |
| `@contract` | Enable contract verification |
| `@verified <date>` | Manual verification timestamp |

## Benefits

1. **Trust** - Developers trust docs because they're verified
2. **Onboarding** - Examples actually work
3. **Maintenance** - Broken docs are immediately visible
4. **CI/CD** - `stig verify` in pipelines catches doc rot

## Comparison with DevScribe

The blog mentions DevScribe as a solution. Here's how Stig compares:

| Feature | DevScribe | Stig (Current) | Stig (Proposed) |
|---------|-----------|----------------|-----------------|
| API execution | Yes | Via Godbolt | Local + Godbolt |
| Database queries | Yes | No | No (out of scope) |
| Diagrams | Yes | Mermaid | Mermaid |
| Offline | Yes | Yes | Yes |
| Code-first | No | Yes | Yes |
| C/C++ focused | No | Yes | Yes |
| LSP integration | No | Yes | Yes |
| CI/CD friendly | Unknown | Yes | Yes |

Stig's advantage is being **code-first** - documentation lives in the source code, not a separate tool.

## Next Steps

1. Implement `stig verify --compile-only` for basic compilation checking
2. Add `@code{.cpp,verify}` tag support
3. Enhance `@test` to show execution status
4. Add freshness tracking with git integration

## References

- Blog: "What If Software Documentation Was Executable?" by Avinash Kumar
- DevScribe: https://devscribe.app
- Stig: https://github.com/bresilla/stig
