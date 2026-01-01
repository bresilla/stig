# test/fixtures/macros.h

## Macros

### `MACROS_H`

```c
#define MACROS_H
```

---

### `VERSION`

```c
#define VERSION 1
```

Version number

---

### `VERSION_MAJOR`

```c
#define VERSION_MAJOR 1
```

Major version

---

### `VERSION_MINOR`

```c
#define VERSION_MINOR 0
```

Minor version

---

### `VERSION_PATCH`

```c
#define VERSION_PATCH 0
```

Patch version

---

### `MAX`

```c
#define MAX(a, b) ((a) > (b) ? (a) : (b))
```

Returns the maximum of two values.

**Parameters:**
- `a`: First value
- `b`: Second value

> **Warning:** Both arguments are evaluated twice

---

### `MIN`

```c
#define MIN(a, b) ((a) < (b) ? (a) : (b))
```

Returns the minimum of two values.

**Parameters:**
- `a`: First value
- `b`: Second value

---

### `SWAP`

```c
#define SWAP(a, b, type) do {                                                                                                               \
        type _tmp = (a);                                                                                               \
        (a) = (b);                                                                                                     \
        (b) = _tmp;                                                                                                    \
    } while (0)
```

Swaps two values.

**Parameters:**
- `a`: First value (will contain b's value)
- `b`: Second value (will contain a's value)
- `type`: The type of the values

> **Note:** Uses a temporary variable

---

### `ARRAY_SIZE`

```c
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))
```

Array size helper

---

### `STRINGIFY`

```c
#define STRINGIFY(x) #x
```

Stringify macro argument.

**Parameters:**
- `x`: Value to stringify

---

### `CONCAT`

```c
#define CONCAT(a, b) a##b
```

Concatenate two tokens.

**Parameters:**
- `a`: First token
- `b`: Second token

---

### `DEBUG_PRINT`

```c
#define DEBUG_PRINT(fmt) printf("DEBUG: " fmt "\n", ##__VA_ARGS__)
```

---

### `DEBUG_PRINT`

```c
#define DEBUG_PRINT(fmt)
```

---

### `UNUSED`

```c
#define UNUSED(x) (void)(x)
```

Unused parameter marker

---

### `ALIGN`

```c
#define ALIGN(x, align) (((x) + ((align) - 1)) & ~((align) - 1))
```

Alignment macro.

**Parameters:**
- `x`: Value to align
- `align`: Alignment boundary (must be power of 2)

---

### `STATIC_ASSERT`

```c
#define STATIC_ASSERT(cond, msg) typedef char static_assertion_##msg[(cond) ? 1 : -1]
```

Compile-time assertion

---

