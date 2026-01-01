# /tmp/test_variadic.hpp

## Classes

### `Tuple&lt;Args...&gt;`

```cpp
template<typename... Args>
class Tuple {
};
```

A tuple-like container

**Template Parameters:**
- `Args...` (typename...): The types to store

---

### `Container&lt;T&gt;`

```cpp
template<typename T = int>
class Container {
};
```

Template with default

**Template Parameters:**
- `T` (typename) = `int`: The type (defaults to int)

---

