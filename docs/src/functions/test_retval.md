# /tmp/test_retval.hpp

## Functions

### `open_file`

```cpp
int open_file(const char path);
```

Opens a file

**Parameters:**
- `path` (const char): The file path

**Return Values:**
- `0`: Success
- `-1`: File not found
- `-2`: Permission denied
- `-3`: Invalid path

---

### `is_valid`

```cpp
bool is_valid(int value);
```

Checks if value is valid

**Parameters:**
- `value` (int): The value to check

**Return Values:**
- `true`: Value is valid
- `false`: Value is invalid

---

