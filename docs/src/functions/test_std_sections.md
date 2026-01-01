# /tmp/test_std_sections.hpp

## Functions

### `swap&lt;T&gt;`

```cpp
template<typename T>
void swap(T a, T b);
```

Swaps two values

**Parameters:**
- `a` (T): First value
- `b` (T): Second value

*Effects:* Exchanges values stored in a and b

*Requires:* Type T shall be MoveConstructible and MoveAssignable

*Complexity:* O(1)

*Remarks:* This function is noexcept if T is nothrow swappable

*Thread Safety:* Thread-safe if a and b are distinct objects

**Template Parameters:**
- `T` (typename): The value type

---

