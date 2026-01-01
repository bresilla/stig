# /tmp/test_variadic.hpp

## Functions

### `print&lt;T, Rest...&gt;`

```cpp
template<typename T, typename... Rest>
void print(T first);
```

Print multiple values

**Template Parameters:**
- `T` (typename): First type
- `Rest...` (typename...): Remaining types

---

### `sum&lt;Values...&gt;`

```cpp
template<auto... Values>
void sum();
```

Sum of compile-time values

**Template Parameters:**
- `Values...` (auto...): The values to sum

---

