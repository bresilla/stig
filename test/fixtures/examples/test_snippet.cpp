// Example file for testing @snippet tag extraction
#include <iostream>
#include <vector>

// [hello]
std::cout << "Hello, World!" << std::endl;
// [hello]

void basic_example() {
    // [basic_usage]
    std::vector<int> numbers = {1, 2, 3, 4, 5};
    for (int n : numbers) {
        std::cout << n << " ";
    }
    std::cout << std::endl;
    // [basic_usage]
}

void advanced_example() {
    // [advanced_usage]
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
    // [advanced_usage]
}

// [multiline_example]
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
// [multiline_example]
