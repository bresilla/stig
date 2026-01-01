# test/fixtures/test_synopsis.hpp

## Functions

### `synopsis_test::process&lt;Args...&gt;`

```cpp
void process(Args... args)
```

Process variadic arguments

**Parameters:**
- `args`: The arguments to process

**Template Parameters:**
- `Args...` (typename...): Variadic template arguments

---

### `synopsis_test::transform&lt;Container, Func, ResultType&gt;`

```cpp
auto transform(Container c, Func f) -> ResultType
```

Complex template function with simplified synopsis

**Parameters:**
- `container` (Container): The input container
- `func` (Func): The transformation function

**Returns:** (void) The transformed result

**Template Parameters:**
- `Container` (typename): The container type
- `Func` (typename): The transformation function type
- `ResultType` (typename)

---

### `synopsis_test::double_value`

```cpp
int synopsis_test::double_value(int x);
```

Normal function without synopsis override

**Parameters:**
- `x` (int): The input value

**Returns:** (int) The doubled value

---

### `synopsis_test::format&lt;Args...&gt;`

```cpp
std::string format(const char* fmt, ...)
```

Using backslash prefix for synopsis

**Parameters:**
- `fmt` (const char): The format string

**Returns:** (void) The formatted string

**Template Parameters:**
- `Args...` (typename...)

---

