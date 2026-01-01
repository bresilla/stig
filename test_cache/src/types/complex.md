# test/fixtures/complex.h

## Structures

### `Node`

```c
struct Node {
};
```

---

### `Tree`

```c
struct Tree {
};
```

---

### `Node`

```c
struct Node {
};
```

---

### `Vector3D`

```c
struct Vector3D {
     xy;
    float z;
};
```

A 3D vector with nested components.

**Fields:**
- `xy` ()
- `z` (float): Z coordinate

---

### `Config`

```c
struct Config {
     display;
     audio;
};
```

Configuration with nested options.

**Fields:**
- `display` ()
- `audio` ()

---

### `Container`

```c
struct Container {
    size_t size;
    size_t capacity;
};
```

Generic container interface.

**Fields:**
- `size` (size_t): Number of elements
- `capacity` (size_t): Allocated capacity

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

Creates a new container with the given callbacks.

---

### `Container`

```c
struct Container {
};
```

---

### `Container`

```c
struct Container {
};
```

---

## Enumerations

### `ErrorCode`

```c
enum ErrorCode {
    ERR_OK = 0,
    ERR_INVALID_ARG = -1,
    ERR_OUT_OF_MEMORY = -2,
    ERR_IO = -100,
    ERR_NETWORK = -101,
    ERR_TIMEOUT = -102,
    ERR_UNKNOWN = -999,
};
```

Error codes with explicit values.

**Values:**
- `ERR_OK`
- `ERR_INVALID_ARG`
- `ERR_OUT_OF_MEMORY`
- `ERR_IO`
- `ERR_NETWORK`
- `ERR_TIMEOUT`
- `ERR_UNKNOWN`: Unknown error

---

### `FilePermissions`

```c
enum FilePermissions {
    PERM_NONE = 0,
    PERM_READ,
    PERM_WRITE,
    PERM_EXEC,
    PERM_ALL,
};
```

Bit flags for file permissions.

**Values:**
- `PERM_NONE`
- `PERM_READ`
- `PERM_WRITE`
- `PERM_EXEC`
- `PERM_ALL`: All permissions

---

## Type Definitions

### `byte_t`

```c
typedef unsigned char byte_t;
```

Unsigned 8-bit byte type.

---

