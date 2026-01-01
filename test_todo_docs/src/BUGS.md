# Known Bugs

This page lists all known bugs found in the codebase.

## test_todo_bug.h

### `sort()` (line 19)

- Does not handle empty arrays correctly (issue #123)
### `normalize()` (line 29)

- Division by zero possible when both components are zero
### `process()` (line 44)

- Crashes on null pointer
