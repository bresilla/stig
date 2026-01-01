# /tmp/test_attributes.hpp

## Classes

### `Result`

```cpp
[[nodiscard]]
class Result {
public:
    int value;
};
```

**Attributes:** `[[nodiscard]]`

A class with attributes

---

### `OldClass`

```cpp
[[deprecated("Use NewClass")]]
class OldClass {
};
```

> **Deprecated**: Use NewClass

A deprecated class

---

