# /tmp/test_friends.hpp

## Classes

### `Foo`

```cpp
class Foo {
public:
    int value;
private:
    int secret;
};
```

A class with friend declarations

**Friends:**

*Classes:*
- Bar

*Functions:*
- `void print_foo(const Foo& f)`

---

### `Container&lt;T&gt;`

```cpp
template<typename T>
class Container {
};
```

Another class with template friend

**Template Parameters:**
- `T` (typename)

**Friends:**

*Classes:*
- Allocator

*Functions:*
- `void swap(Container& a, Container& b)`

---

