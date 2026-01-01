# /tmp/test_inheritance.cpp

## Classes

### `Base`

```cpp
class Base {
};
```

---

### `Derived`

**Inherits from:** [Base](../types/test_inheritance.md#base) (public)

```cpp
class Derived : public Base {
};
```

---

### `Multi`

**Inherits from:** [Base](../types/test_inheritance.md#base) (public), Other (protected), Third (private virtual)

```cpp
class Multi : public Base, protected Other, private virtual Third {
};
```

---

