# Docstring Formats

Stig extracts documentation from Doxygen-style comments in C and C++ source files.

## Comment Styles

### Block Comments

```c
/**
 * @brief Brief description of the function.
 * 
 * Detailed description goes here. Can span
 * multiple lines.
 * 
 * @param x First parameter
 * @param y Second parameter
 * @return The result
 */
int add(int x, int y);
```

### Triple-Slash Comments

```c
/// Brief description of the function.
/// 
/// Detailed description here.
/// 
/// @param x First parameter
/// @return The result
int square(int x);
```

### Inline Comments

```c
struct Point {
    int x;  /**< X coordinate */
    int y;  ///< Y coordinate
};
```

## Supported Tags

### Basic Tags

| Tag | Description |
|-----|-------------|
| `@brief` | Brief one-line description |
| `@param name` | Parameter documentation |
| `@return` | Return value documentation |
| `@see` | Cross-reference to related items |
| `@note` | Important note |
| `@warning` | Warning message |
| `@deprecated` | Deprecation notice |

### Template Tags

| Tag | Description |
|-----|-------------|
| `@tparam name` | Template parameter documentation |

```cpp
/**
 * @brief A generic container
 * @tparam T The element type
 * @tparam N The capacity
 */
template<typename T, size_t N>
class Array { };
```

### Code Examples

| Tag | Description |
|-----|-------------|
| `@code` | Start code block |
| `@endcode` | End code block |
| `@code{.cpp}` | Code block with language hint |

```cpp
/**
 * @brief Creates a point
 * 
 * @code{.cpp}
 * Point2<float> p{1.0f, 2.0f};
 * auto len = p.length();
 * @endcode
 */
```

### Exception Tags

| Tag | Description |
|-----|-------------|
| `@throw type` | Exception that may be thrown |
| `@exception type` | Same as @throw |

```cpp
/**
 * @brief Divides two numbers
 * @throw std::invalid_argument if divisor is zero
 */
double divide(double a, double b);
```

### Condition Tags

| Tag | Description |
|-----|-------------|
| `@pre` | Precondition |
| `@post` | Postcondition |

```cpp
/**
 * @brief Computes square root
 * @pre x >= 0
 * @post result >= 0
 */
double sqrt(double x);
```

## Output Example

Given:

```cpp
/**
 * @brief Computes the distance between two points
 * 
 * Uses the Euclidean distance formula.
 * 
 * @param a First point
 * @param b Second point
 * @return The distance
 * 
 * @code{.cpp}
 * Point2 p1{0, 0};
 * Point2 p2{3, 4};
 * auto d = distance(p1, p2);  // 5.0
 * @endcode
 */
double distance(Point2 a, Point2 b);
```

Stig generates:

---

### `distance`

```cpp
double distance(Point2 a, Point2 b);
```

Computes the distance between two points

Uses the Euclidean distance formula.

```cpp
Point2 p1{0, 0};
Point2 p2{3, 4};
auto d = distance(p1, p2);  // 5.0
```

**Parameters:**
- `a`: First point
- `b`: Second point

**Returns:** The distance

---
