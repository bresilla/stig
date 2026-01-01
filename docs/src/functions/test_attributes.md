# /tmp/test_attributes.hpp

## Functions

### `compute_value`

```cpp
[[nodiscard]]
int compute_value();
```

**Attributes:** `[[nodiscard]]`

A function that must use its return value

---

### `old_function`

```cpp
[[deprecated("Use new_function instead")]]
void old_function();
```

> **Deprecated**: Use new_function instead

Deprecated function with reason

---

### `check_status`

```cpp
[[nodiscard("Check for errors")]] [[maybe_unused]]
int check_status();
```

**Attributes:** `[[nodiscard("Check for errors")]]`, `[[maybe_unused]]`

Function with multiple attributes

---

