# test/fixtures/test_snippet.h

## Functions

### `show_hello`

```cpp
void show_hello();
```

Demonstrates the hello world example

This function shows a simple greeting.

**Examples:**

```cpp
std::cout << "Hello, World!" << std::endl;
```

---

### `show_basic_usage`

```cpp
void show_basic_usage();
```

Demonstrates basic vector usage

This function shows how to use vectors.

**Examples:**

```cpp
    std::vector<int> numbers = {1, 2, 3, 4, 5};
    for (int n : numbers) {
        std::cout << n << " ";
    }
    std::cout << std::endl;
    
```

---

### `show_advanced`

```cpp
void show_advanced();
```

Shows advanced vector operations

This function demonstrates advanced patterns.

**Examples:**

```cpp
    std::vector<int> data;
    data.reserve(100);
    
    for (int i = 0; i < 100; ++i) {
        data.push_back(i * i);
    }
    
    // Find sum
    int sum = 0;
    for (int v : data) {
        sum += v;
    }
    
```

---

### `show_calculator`

```cpp
void show_calculator();
```

A Calculator class example

See how to implement a calculator:

> **Note:** This is a simple implementation

**Examples:**

```cpp
class Calculator {
public:
    int add(int a, int b) { return a + b; }
    int subtract(int a, int b) { return a - b; }
    int multiply(int a, int b) { return a * b; }
    double divide(int a, int b) { 
        if (b == 0) throw std::runtime_error("Division by zero");
        return static_cast<double>(a) / b;
    }
};
```

---

### `mixed_examples`

```cpp
void mixed_examples();
```

Function with inline example and snippet

**Examples:**

```c
int x = 42;
```

```cpp
std::cout << "Hello, World!" << std::endl;
```

---

### `missing_file_test`

```cpp
void missing_file_test();
```

Test missing snippet file

**Examples:**

```
// Snippet not found: nonexistent.cpp [missing]
// Error: File not found
```

---

### `missing_anchor_test`

```cpp
void missing_anchor_test();
```

Test missing anchor

**Examples:**

```
// Snippet not found: examples/test_snippet.cpp [nonexistent_anchor]
// Error: Anchor not found in file
```

---

### `explicit_language_test`

```cpp
void explicit_language_test();
```

Test with explicit language override

**Examples:**

```c
std::cout << "Hello, World!" << std::endl;
```

---

