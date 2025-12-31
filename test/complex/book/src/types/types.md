# include/spatial/types.hpp

## Structures

### `spatial::is_floating_point`

```c
struct spatial::is_floating_point {
};
```

Type trait to check if a type is a floating point number

---

### `spatial::is_numeric`

```c
struct spatial::is_numeric {
};
```

Type trait to check if a type is numeric (integral or floating point)

---

## Enumerations

### `spatial::u32`

```c
enum spatial::u32 {
    None = 0,
    InvalidInput,
    OutOfBounds,
    DivisionByZero,
    NotNormalized,
    Degenerate,
    NoIntersection,
    NotImplemented,
};
```

Error codes for spatial operations

**Values:**
- `None`
- `InvalidInput`
- `OutOfBounds`
- `DivisionByZero`
- `NotNormalized`
- `Degenerate`
- `NoIntersection`
- `NotImplemented`: Feature not yet implemented

---

## Classes

### `spatial::Result`

```cpp
class spatial::Result {
public:
    static Result ok(T val);
    static Result error(ErrorCode code);
    bool is_ok() const;
    bool is_error() const;
    ErrorCode error() const;
    T value_or(T default_val) const;
private:
    T value_;
    ErrorCode error_;
    void Result(T val, ErrorCode err);
};
```

A result type that holds either a value or an error

@tparam T The success value type
 * 
 * Provides a safe way to return values that may fail.
 * 
 * @code
 * Result<f64> safe_divide(f64 a, f64 b) {
 *     if (b == 0.0) return Result<f64>::error(ErrorCode::DivisionByZero);
 *     return Result<f64>::ok(a / b);
 * }
 * 
 * auto result = safe_divide(10.0, 2.0);
 * if (result.is_ok()) {
 *     std::cout << "Result: " << result.value() << std::endl;
 * }
 * @endcode

**See also:** `ErrorCode`

**Public Methods:**

- `ok(T)`
- `error(ErrorCode)`
- `is_ok()`
- `is_error()`
- `error()`
- `value_or(T)`

---

