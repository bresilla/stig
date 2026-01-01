# /tmp/test_backslash.hpp

## Functions

### `open_file`

```cpp
int open_file(const char path);
```

Opens a file

**Parameters:**
- `path` (const char): The file path

**Returns:** (int) File handle

**Return Values:**
- `0`: Success
- `-1`: Error

**Throws:**
- `std::runtime_error`: If permission denied

**Preconditions:**
- path must not be null

**Postconditions:**
- File is open

> **Deprecated:** Use open_file_v2 instead

> **Note:** Thread-safe

> **Warning:** May block

**See also:** `close_file`

**Since:** 1.0

---

