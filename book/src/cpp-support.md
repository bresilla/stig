# C++ Support

Stig has full support for modern C++ features including templates, classes, namespaces, and C++20 concepts.

## Templates

### Template Classes

```cpp
/**
 * @brief A fixed-size array
 * @tparam T Element type
 * @tparam N Array size
 */
template<typename T, size_t N>
class Array {
public:
    T& operator[](size_t i);
    constexpr size_t size() const;
};
```

Stig extracts:
- Template parameter list with kinds (type, non-type, variadic)
- `@tparam` documentation
- Default template arguments

### Template Functions

```cpp
/**
 * @brief Swaps two values
 * @tparam T The value type
 */
template<typename T>
void swap(T& a, T& b) noexcept;
```

### Template Template Parameters

```cpp
template<template<typename> class Container, typename T>
class Wrapper { };
```

## Classes

### Inheritance

```cpp
template<typename T>
class Vec2 : public Vector<T, 2> {
    // ...
};
```

Stig shows inheritance with access specifiers:

> **Inherits from:** public Vector&lt;T, 2&gt;

### Special Member Functions

Stig categorizes and groups methods:

**Constructors:**
- `Point2()` - Default constructor
- `Point2(T x, T y)` - Construct from coordinates
- `Point2(const Point2&)` - Copy constructor
- `Point2(Point2&&)` - Move constructor

**Destructor:**
- `~Point2()`

**Operators:**

*Arithmetic:*
- `operator+(const Vec2&) -> Point2`
- `operator-(const Vec2&) -> Point2`

*Comparison:*
- `operator==(const Point2&) -> bool`
- `operator<=>(const Point2&) -> auto`

### Method Specifiers

Stig detects:

| Specifier | Example |
|-----------|---------|
| `constexpr` | `constexpr T length() const` |
| `consteval` | `consteval int compute()` |
| `noexcept` | `void swap(T&) noexcept` |
| `explicit` | `explicit Point2(const Vec2&)` |
| `= default` | `Point2() = default` |
| `= delete` | `Point2(const Point2&) = delete` |
| `virtual` | `virtual ~Base()` |

### Nested Types

```cpp
class Outer {
public:
    class Inner { };
    enum class Status { Ok, Error };
};
```

Stig documents nested classes and enums within their parent class.

## Namespaces

```cpp
namespace spatial {
    class Point2 { };
    class Point3 { };
}
```

Types are shown with their full namespace: `spatial::Point2`

## Type Aliases

```cpp
using Vec2f = Vec2<float>;
using Vec2d = Vec2<double>;

template<typename T>
using Vec = std::vector<T>;
```

Stig documents both simple aliases and alias templates.

## C++20 Features

### Concepts

```cpp
template<typename T>
concept Numeric = std::is_arithmetic_v<T>;

template<Numeric T>
T add(T a, T b);
```

### Requires Clauses

```cpp
template<typename T>
requires std::integral<T>
class IntWrapper { };
```

### Spaceship Operator

```cpp
auto operator<=>(const Point2&) const = default;
```

Grouped with comparison operators in the output.

## Conversion Operators

```cpp
class Boolean {
    explicit operator bool() const;
    operator int() const;
};
```

Detected and documented as conversion operators.
