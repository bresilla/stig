# /tmp/test_std_sections.hpp

## Classes

### `Container&lt;T&gt;`

```cpp
template<typename T>
class Container {
};
```

A container class

**Invariants:**
- size() <= capacity()
- data() != nullptr || size() == 0

**Template Parameters:**
- `T` (typename): Element type

---

