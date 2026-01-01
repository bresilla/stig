# test/fixtures/complex.h

## Functions

### `sort_array`

```cpp
void sort_array(void *base base, size_t count, size_t size, compare_fn cmp);
```

Sorts an array using a custom comparator.

**Parameters:**
- `base` (void *base): Pointer to the first element
- `count` (size_t): Number of elements
- `size` (size_t): Size of each element in bytes
- `cmp` (compare_fn): Comparison function

---

### `container_create`

```cpp
void container_create(destructor_fn destroy_fn);
```

Creates a new container with the given callbacks.

**Parameters:**
- `add_fn`: Function to add elements
- `remove_fn`: Function to remove elements
- `destroy_fn` (destructor_fn): Destructor for cleanup

**Returns:** (void) Newly allocated container, or NULL on failure

---

### `process_data`

```cpp
int process_data(const void *input input, size_t len);
```

Processes data with optional callback.

---

### `log_printf`

```cpp
int log_printf(const char *fmt fmt);
```

Variadic function example.

**Parameters:**
- `fmt` (const char *fmt): Format string
- `...`: Variable arguments

**Returns:** (int) Number of characters written

---

### `read_register`

```cpp
unsigned int read_register(volatile unsigned int *addr addr);
```

Reads a value from a memory-mapped register.

**Parameters:**
- `addr` (volatile unsigned int *addr): Register address

**Returns:** (unsigned int) Value at the address

---

### `write_register`

```cpp
void write_register(volatile unsigned int *addr addr, unsigned int value);
```

Writes a value to a memory-mapped register.

**Parameters:**
- `addr` (volatile unsigned int *addr): Register address
- `value` (unsigned int): Value to write

---

### `get_version_string`

```cpp
char get_version_string();
```

Gets a read-only string constant.

---

### `swap_int`

```cpp
void swap_int(int *a a, int *b b);
```

Swaps two integers.

**Parameters:**
- `a` (int *a): Pointer to first integer
- `b` (int *b): Pointer to second integer

---

### `clamp`

```cpp
int clamp(int value, int min, int max);
```

Clamps a value to a range.

---

