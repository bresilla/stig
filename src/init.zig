const std = @import("std");

/// Initializes test infrastructure for a C/C++ project.
/// Creates:
/// - stig.toml (configuration file)
/// - test/ directory
/// - test/stig_test.h (test framework header)
/// - test/main.cpp (test runner entry point)
/// - test/test_example.cpp (example test file)
pub const InitCommand = struct {
    allocator: std.mem.Allocator,
    config_path: []const u8,
    force: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config_path: ?[]const u8, force: bool) Self {
        return Self{
            .allocator = allocator,
            .config_path = config_path orelse "stig.toml",
            .force = force,
        };
    }

    pub fn run(self: *Self) !void {
        std.debug.print("Initializing stig test infrastructure...\n\n", .{});

        // Create test directory
        try self.createTestDir();

        // Generate files
        try self.generateConfigFile();
        try self.generateTestHeader();
        try self.generateExampleTest();

        std.debug.print("\nInitialization complete!\n", .{});
        std.debug.print("\nNext steps:\n", .{});
        std.debug.print("  1. Write tests in test/*.cpp using TEST() macro\n", .{});
        std.debug.print("  2. Include \"stig.hpp\" in your test files\n", .{});
        std.debug.print("  3. Build with CMake using stig_add_tests()\n", .{});
        std.debug.print("  4. Run tests: ./build/test_example --help\n", .{});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  TEST(my_test) {{\n", .{});
        std.debug.print("      CHECK_EQ(1 + 1, 2);\n", .{});
        std.debug.print("  }}\n", .{});
    }

    fn createTestDir(self: *Self) !void {
        _ = self;
        std.fs.cwd().makeDir("test") catch |err| {
            if (err != error.PathAlreadyExists) {
                std.debug.print("Error: Cannot create test/ directory: {}\n", .{err});
                return err;
            }
        };
        std.debug.print("  Created: test/\n", .{});
    }

    fn generateConfigFile(self: *Self) !void {
        // Check if file exists
        if (!self.force) {
            if (std.fs.cwd().access(self.config_path, .{})) |_| {
                std.debug.print("  Skipped: {s} (already exists, use --force to overwrite)\n", .{self.config_path});
                return;
            } else |_| {}
        }

        const config_content =
            \\# Stig configuration file
            \\# See: https://github.com/bresilla/stig
            \\
            \\# Documentation settings
            \\title = "API Reference"
            \\output_dir = "docs"
            \\format = "mdbook"
            \\input_patterns = ["include/**/*.hpp", "include/**/*.h"]
            \\
        ;

        const file = try std.fs.cwd().createFile(self.config_path, .{});
        defer file.close();
        try file.writeAll(config_content);

        std.debug.print("  Created: {s}\n", .{self.config_path});
    }

    fn generateTestHeader(self: *Self) !void {
        const path = "test/stig.hpp";

        // Check if file exists
        if (!self.force) {
            if (std.fs.cwd().access(path, .{})) |_| {
                std.debug.print("  Skipped: {s} (already exists, use --force to overwrite)\n", .{path});
                return;
            } else |_| {}
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(stig_test_header);

        std.debug.print("  Created: {s}\n", .{path});
    }

    fn generateExampleTest(self: *Self) !void {
        const path = "test/test_example.cpp";

        // Check if file exists
        if (!self.force) {
            if (std.fs.cwd().access(path, .{})) |_| {
                std.debug.print("  Skipped: {s} (already exists, use --force to overwrite)\n", .{path});
                return;
            } else |_| {}
        }

        const example_content =
            \\// Example test file - demonstrates stig test framework
            \\// Delete this file and create your own test_*.cpp files
            \\
            \\#include "stig.hpp"
            \\#include <stdexcept>
            \\#include <cmath>
            \\
            \\// =============================================================================
            \\// Basic Tests
            \\// =============================================================================
            \\
            \\TEST(basic_assertions) {
            \\    CHECK(1 + 1 == 2);
            \\    CHECK_EQ(2 * 3, 6);
            \\    CHECK_NE(1, 2);
            \\    CHECK_FALSE(1 > 2);
            \\}
            \\
            \\TEST(comparison_operators) {
            \\    CHECK_LT(1, 2);   // less than
            \\    CHECK_LE(2, 2);   // less or equal
            \\    CHECK_GT(3, 2);   // greater than
            \\    CHECK_GE(3, 3);   // greater or equal
            \\}
            \\
            \\// =============================================================================
            \\// REQUIRE - Stops Test on Failure
            \\// =============================================================================
            \\
            \\TEST(require_stops_on_failure) {
            \\    int* ptr = new int(42);
            \\    REQUIRE(ptr != nullptr);  // Test stops here if fails
            \\    
            \\    CHECK_EQ(*ptr, 42);       // Only runs if REQUIRE passed
            \\    delete ptr;
            \\}
            \\
            \\// =============================================================================
            \\// Floating Point with Approx
            \\// =============================================================================
            \\
            \\TEST(floating_point_comparison) {
            \\    double result = 0.1 + 0.2;
            \\    
            \\    // Direct comparison might fail due to floating point errors
            \\    // CHECK_EQ(result, 0.3);  // Might fail!
            \\    
            \\    // Use Approx for floating point comparisons
            \\    CHECK(result == stig::Approx(0.3));
            \\    CHECK(std::sin(0.0) == stig::Approx(0.0));
            \\    
            \\    // Custom epsilon
            \\    CHECK(1.0001 == stig::Approx(1.0).epsilon(0.001));
            \\}
            \\
            \\// =============================================================================
            \\// Exception Testing
            \\// =============================================================================
            \\
            \\TEST(exception_testing) {
            \\    // Check that expression throws any exception
            \\    CHECK_THROWS(throw std::runtime_error("oops"));
            \\    
            \\    // Check for specific exception type
            \\    CHECK_THROWS_AS(throw std::runtime_error("oops"), std::runtime_error);
            \\    
            \\    // Check exception message contains string
            \\    CHECK_THROWS_WITH(throw std::runtime_error("file not found"), "not found");
            \\    
            \\    // Check that expression does NOT throw
            \\    int x = 42;
            \\    CHECK_NOTHROW(x += 1);
            \\}
            \\
            \\// =============================================================================
            \\// Test Suites - Group Related Tests
            \\// =============================================================================
            \\
            \\TEST_SUITE("math") {
            \\
            \\TEST(addition) {
            \\    CHECK_EQ(1 + 1, 2);
            \\    CHECK_EQ(100 + 200, 300);
            \\}
            \\
            \\TEST(multiplication) {
            \\    CHECK_EQ(2 * 3, 6);
            \\    CHECK_EQ(10 * 10, 100);
            \\}
            \\
            \\} // TEST_SUITE("math")
            \\
            \\// =============================================================================
            \\// Subcases - Test Variations
            \\// =============================================================================
            \\
            \\TEST(subcases_example) {
            \\    std::vector<int> vec;
            \\    vec.push_back(1);
            \\    
            \\    SUBCASE("add more") {
            \\        vec.push_back(2);
            \\        CHECK_EQ(vec.size(), 2u);
            \\        
            \\        SUBCASE("add even more") {
            \\            vec.push_back(3);
            \\            CHECK_EQ(vec.size(), 3u);
            \\        }
            \\    }
            \\    
            \\    SUBCASE("clear") {
            \\        vec.clear();
            \\        CHECK(vec.empty());
            \\    }
            \\    
            \\    // This runs after each subcase path
            \\    CHECK_GE(vec.size(), 0u);
            \\}
            \\
            \\// =============================================================================
            \\// INFO and CAPTURE - Debug Context
            \\// =============================================================================
            \\
            \\TEST(info_and_capture) {
            \\    for (int i = 0; i < 3; i++) {
            \\        CAPTURE(i);  // Shows value of i on failure
            \\        INFO("Testing iteration");
            \\        
            \\        CHECK(i >= 0);
            \\        CHECK(i < 10);
            \\    }
            \\}
            \\
            \\// =============================================================================
            \\// Fixtures - Setup/Teardown
            \\// =============================================================================
            \\
            \\struct DatabaseFixture {
            \\    std::string connection;
            \\    
            \\    DatabaseFixture() : connection("test_db") {
            \\        // Setup: runs before each test
            \\    }
            \\    
            \\    ~DatabaseFixture() {
            \\        // Teardown: runs after each test
            \\    }
            \\};
            \\
            \\TEST_F(DatabaseFixture, connection_is_valid) {
            \\    CHECK_FALSE(connection.empty());
            \\    CHECK_EQ(connection, "test_db");
            \\}
            \\
            \\// =============================================================================
            \\// Skip Tests
            \\// =============================================================================
            \\
            \\TEST_SKIP(work_in_progress) {
            \\    // This test is skipped
            \\    FAIL("This should not run");
            \\}
            \\
            \\// =============================================================================
            \\// WARN - Log Without Failing
            \\// =============================================================================
            \\
            \\TEST(warnings_dont_fail) {
            \\    WARN(1 > 2);  // Logs warning but test continues
            \\    CHECK(true);  // Test still passes
            \\}
            \\
        ;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(example_content);

        std.debug.print("  Created: {s}\n", .{path});
    }
};

/// The stig.hpp header content - a single-header test framework with echo integration
const stig_test_header =
    \\// =============================================================================
    \\// stig.hpp - Single-header C++ test framework
    \\// Auto-generated by stig - https://github.com/bresilla/stig
    \\// =============================================================================
    \\//
    \\// A doctest-inspired test framework with beautiful colored output via echo.
    \\//
    \\// Usage:
    \\//   #include "stig.hpp"
    \\//
    \\//   TEST(test_name) {
    \\//       CHECK(condition);
    \\//       CHECK_EQ(a, b);
    \\//       REQUIRE(must_be_true);
    \\//   }
    \\//
    \\//   TEST_SUITE("suite_name") {
    \\//       TEST(grouped_test) { ... }
    \\//   }
    \\//
    \\//   TEST_F(FixtureClass, test_name) { ... }
    \\//
    \\//   SUBCASE("section") { ... }
    \\//
    \\// Command line:
    \\//   ./test --list          List all tests
    \\//   ./test --filter=name   Run tests matching pattern
    \\//   ./test --quiet         Minimal output
    \\//   ./test --no-color      Disable colors
    \\//
    \\// =============================================================================
    \\
    \\#ifndef STIG_HPP
    \\#define STIG_HPP
    \\
    \\#include <algorithm>
    \\#include <chrono>
    \\#include <cmath>
    \\#include <cstring>
    \\#include <exception>
    \\#include <functional>
    \\#include <iomanip>
    \\#include <iostream>
    \\#include <memory>
    \\#include <sstream>
    \\#include <string>
    \\#include <typeinfo>
    \\#include <vector>
    \\
    \\// =============================================================================
    \\// ANSI Color Support (fallback if echo not available)
    \\// =============================================================================
    \\
    \\namespace stig {
    \\namespace color {
    \\
    \\inline bool& enabled() {
    \\    static bool e = true;
    \\    return e;
    \\}
    \\
    \\inline const char* reset()   { return enabled() ? "\033[0m" : ""; }
    \\inline const char* bold()    { return enabled() ? "\033[1m" : ""; }
    \\inline const char* dim()     { return enabled() ? "\033[2m" : ""; }
    \\inline const char* red()     { return enabled() ? "\033[38;2;255;80;80m" : ""; }
    \\inline const char* green()   { return enabled() ? "\033[38;2;80;255;80m" : ""; }
    \\inline const char* yellow()  { return enabled() ? "\033[38;2;255;255;80m" : ""; }
    \\inline const char* blue()    { return enabled() ? "\033[38;2;80;80;255m" : ""; }
    \\inline const char* magenta() { return enabled() ? "\033[38;2;255;80;255m" : ""; }
    \\inline const char* cyan()    { return enabled() ? "\033[38;2;80;255;255m" : ""; }
    \\inline const char* gray()    { return enabled() ? "\033[38;2;128;128;128m" : ""; }
    \\inline const char* white()   { return enabled() ? "\033[38;2;255;255;255m" : ""; }
    \\
    \\} // namespace color
    \\
    \\// =============================================================================
    \\// Value to String Conversion
    \\// =============================================================================
    \\
    \\namespace detail {
    \\
    \\// Type traits
    \\template<typename T, typename = void> struct has_ostream : std::false_type {};
    \\template<typename T>
    \\struct has_ostream<T, std::void_t<decltype(std::declval<std::ostream&>() << std::declval<T>())>> : std::true_type {};
    \\
    \\template<typename T>
    \\inline std::string stringify(const T& value) {
    \\    if constexpr (std::is_same_v<T, bool>) {
    \\        return value ? "true" : "false";
    \\    } else if constexpr (std::is_same_v<T, std::nullptr_t>) {
    \\        return "nullptr";
    \\    } else if constexpr (std::is_same_v<T, std::string>) {
    \\        return "\"" + value + "\"";
    \\    } else if constexpr (std::is_same_v<T, const char*> || std::is_same_v<T, char*>) {
    \\        return value ? ("\"" + std::string(value) + "\"") : "nullptr";
    \\    } else if constexpr (std::is_floating_point_v<T>) {
    \\        std::ostringstream oss;
    \\        oss << std::setprecision(10) << value;
    \\        return oss.str();
    \\    } else if constexpr (has_ostream<T>::value) {
    \\        std::ostringstream oss;
    \\        oss << value;
    \\        return oss.str();
    \\    } else {
    \\        return "[?]";
    \\    }
    \\}
    \\
    \\// Specialization for char
    \\template<>
    \\inline std::string stringify(const char& value) {
    \\    return std::string("'") + value + "'";
    \\}
    \\
    \\} // namespace detail
    \\
    \\// =============================================================================
    \\// Approx - Floating Point Comparison
    \\// =============================================================================
    \\
    \\class Approx {
    \\public:
    \\    explicit Approx(double value) : value_(value), epsilon_(1e-9), scale_(1.0) {}
    \\    
    \\    Approx& epsilon(double eps) { epsilon_ = eps; return *this; }
    \\    Approx& scale(double s) { scale_ = s; return *this; }
    \\    
    \\    friend bool operator==(double lhs, const Approx& rhs) {
    \\        return std::abs(lhs - rhs.value_) < rhs.epsilon_ * (rhs.scale_ + std::abs(rhs.value_));
    \\    }
    \\    friend bool operator==(const Approx& lhs, double rhs) { return rhs == lhs; }
    \\    friend bool operator!=(double lhs, const Approx& rhs) { return !(lhs == rhs); }
    \\    friend bool operator!=(const Approx& lhs, double rhs) { return !(lhs == rhs); }
    \\    
    \\    friend std::ostream& operator<<(std::ostream& os, const Approx& a) {
    \\        return os << "Approx(" << a.value_ << ")";
    \\    }
    \\    
    \\private:
    \\    double value_;
    \\    double epsilon_;
    \\    double scale_;
    \\};
    \\
    \\// =============================================================================
    \\// Test Context - Tracks Current State
    \\// =============================================================================
    \\
    \\struct Context {
    \\    // Current test info
    \\    const char* test_name = nullptr;
    \\    const char* suite_name = nullptr;
    \\    const char* file = nullptr;
    \\    int line = 0;
    \\    
    \\    // Assertion tracking
    \\    int assertions = 0;
    \\    int failures = 0;
    \\    int warnings = 0;
    \\    
    \\    // Subcase tracking
    \\    std::vector<std::string> subcase_stack;
    \\    std::vector<std::vector<bool>> subcase_entered;
    \\    int subcase_depth = 0;
    \\    bool should_reenter = false;
    \\    
    \\    // Captured info (shown on failure)
    \\    std::vector<std::string> info_stack;
    \\    std::vector<std::string> captures;
    \\    
    \\    // Options
    \\    bool quiet = false;
    \\    bool list_only = false;
    \\    std::string filter;
    \\    
    \\    void reset() {
    \\        assertions = 0;
    \\        failures = 0;
    \\        warnings = 0;
    \\        subcase_stack.clear();
    \\        subcase_entered.clear();
    \\        subcase_depth = 0;
    \\        should_reenter = false;
    \\        info_stack.clear();
    \\        captures.clear();
    \\    }
    \\};
    \\
    \\inline Context& ctx() {
    \\    static Context c;
    \\    return c;
    \\}
    \\
    \\// =============================================================================
    \\// Test Case Registration
    \\// =============================================================================
    \\
    \\struct TestCase {
    \\    const char* name;
    \\    const char* suite;
    \\    const char* file;
    \\    int line;
    \\    std::function<void()> func;
    \\    bool skip = false;
    \\};
    \\
    \\inline std::vector<TestCase>& registry() {
    \\    static std::vector<TestCase> tests;
    \\    return tests;
    \\}
    \\
    \\inline const char*& current_suite() {
    \\    static const char* suite = nullptr;
    \\    return suite;
    \\}
    \\
    \\struct TestRegistrar {
    \\    TestRegistrar(const char* name, const char* file, int line, std::function<void()> func, bool skip = false) {
    \\        registry().push_back({name, current_suite(), file, line, func, skip});
    \\    }
    \\};
    \\
    \\struct SuiteRegistrar {
    \\    SuiteRegistrar(const char* name) { current_suite() = name; }
    \\    ~SuiteRegistrar() { current_suite() = nullptr; }
    \\};
    \\
    \\// =============================================================================
    \\// Subcase Support
    \\// =============================================================================
    \\
    \\struct Subcase {
    \\    bool entered = false;
    \\    
    \\    Subcase(const char* name, const char* file, int line) {
    \\        auto& c = ctx();
    \\        
    \\        // Ensure we have enough depth
    \\        while (c.subcase_entered.size() <= static_cast<size_t>(c.subcase_depth)) {
    \\            c.subcase_entered.push_back({});
    \\        }
    \\        
    \\        auto& level = c.subcase_entered[c.subcase_depth];
    \\        size_t idx = level.size();
    \\        
    \\        // Check if we should enter this subcase
    \\        if (idx < level.size() && level[idx]) {
    \\            // Already entered in previous iteration
    \\            level.push_back(true);
    \\            entered = false;
    \\        } else {
    \\            // Enter this subcase
    \\            level.push_back(true);
    \\            entered = true;
    \\            c.subcase_stack.push_back(name);
    \\            c.subcase_depth++;
    \\            
    \\            if (!c.quiet) {
    \\                std::cout << color::dim() << "    ";
    \\                for (int i = 0; i < c.subcase_depth - 1; i++) std::cout << "  ";
    \\                std::cout << "SUBCASE: " << name << color::reset() << "\n";
    \\            }
    \\        }
    \\        (void)file; (void)line;
    \\    }
    \\    
    \\    ~Subcase() {
    \\        if (entered) {
    \\            auto& c = ctx();
    \\            c.subcase_depth--;
    \\            if (!c.subcase_stack.empty()) c.subcase_stack.pop_back();
    \\        }
    \\    }
    \\    
    \\    operator bool() const { return entered; }
    \\};
    \\
    \\// =============================================================================
    \\// Info/Capture Support
    \\// =============================================================================
    \\
    \\struct InfoScope {
    \\    InfoScope(const std::string& msg) { ctx().info_stack.push_back(msg); }
    \\    ~InfoScope() { if (!ctx().info_stack.empty()) ctx().info_stack.pop_back(); }
    \\};
    \\
    \\inline void add_capture(const std::string& name, const std::string& value) {
    \\    ctx().captures.push_back(name + " := " + value);
    \\}
    \\
    \\// =============================================================================
    \\// Reporting
    \\// =============================================================================
    \\
    \\inline void print_context_info() {
    \\    auto& c = ctx();
    \\    
    \\    // Print subcase path
    \\    if (!c.subcase_stack.empty()) {
    \\        std::cerr << color::dim() << "  in subcase: ";
    \\        for (size_t i = 0; i < c.subcase_stack.size(); i++) {
    \\            if (i > 0) std::cerr << " > ";
    \\            std::cerr << c.subcase_stack[i];
    \\        }
    \\        std::cerr << color::reset() << "\n";
    \\    }
    \\    
    \\    // Print info messages
    \\    for (const auto& info : c.info_stack) {
    \\        std::cerr << color::cyan() << "  info: " << color::reset() << info << "\n";
    \\    }
    \\    
    \\    // Print captures
    \\    for (const auto& cap : c.captures) {
    \\        std::cerr << color::yellow() << "  capture: " << color::reset() << cap << "\n";
    \\    }
    \\}
    \\
    \\inline void report_failure(const char* expr, const char* file, int line, const char* type = "CHECK") {
    \\    auto& c = ctx();
    \\    c.failures++;
    \\    
    \\    std::cerr << color::red() << color::bold() << file << ":" << line << ": FAILED" << color::reset() << "\n";
    \\    std::cerr << "  " << color::red() << type << "( " << expr << " )" << color::reset() << "\n";
    \\    print_context_info();
    \\}
    \\
    \\inline void report_failure_cmp(const char* expr, const char* file, int line,
    \\                               const std::string& lhs, const std::string& rhs,
    \\                               const char* op, const char* type = "CHECK") {
    \\    auto& c = ctx();
    \\    c.failures++;
    \\    
    \\    std::cerr << color::red() << color::bold() << file << ":" << line << ": FAILED" << color::reset() << "\n";
    \\    std::cerr << "  " << color::red() << type << "( " << expr << " )" << color::reset() << "\n";
    \\    std::cerr << "  " << color::gray() << "left:  " << color::white() << lhs << color::reset() << "\n";
    \\    std::cerr << "  " << color::gray() << "right: " << color::white() << rhs << color::reset() << "\n";
    \\    print_context_info();
    \\}
    \\
    \\inline void report_warn(const char* expr, const char* file, int line) {
    \\    auto& c = ctx();
    \\    c.warnings++;
    \\    
    \\    std::cerr << color::yellow() << file << ":" << line << ": WARNING: " << expr << color::reset() << "\n";
    \\}
    \\
    \\inline void report_success() {
    \\    ctx().assertions++;
    \\}
    \\
    \\// =============================================================================
    \\// Test Runner
    \\// =============================================================================
    \\
    \\inline bool matches_filter(const char* name, const std::string& filter) {
    \\    if (filter.empty()) return true;
    \\    std::string n(name);
    \\    // Simple wildcard matching
    \\    if (filter.front() == '*') {
    \\        return n.find(filter.substr(1)) != std::string::npos;
    \\    }
    \\    if (filter.back() == '*') {
    \\        return n.find(filter.substr(0, filter.size()-1)) == 0;
    \\    }
    \\    return n.find(filter) != std::string::npos;
    \\}
    \\
    \\inline int run_all(int argc = 0, char** argv = nullptr) {
    \\    auto& c = ctx();
    \\    
    \\    // Parse command line
    \\    for (int i = 1; i < argc; i++) {
    \\        std::string arg(argv[i]);
    \\        if (arg == "--list" || arg == "-l") c.list_only = true;
    \\        else if (arg == "--quiet" || arg == "-q") c.quiet = true;
    \\        else if (arg == "--no-color") color::enabled() = false;
    \\        else if (arg.find("--filter=") == 0) c.filter = arg.substr(9);
    \\        else if (arg.find("-f=") == 0) c.filter = arg.substr(3);
    \\    }
    \\    
    \\    auto& tests = registry();
    \\    
    \\    // List mode
    \\    if (c.list_only) {
    \\        std::cout << "Available tests:\n";
    \\        for (const auto& tc : tests) {
    \\            if (tc.suite) std::cout << "  [" << tc.suite << "] ";
    \\            else std::cout << "  ";
    \\            std::cout << tc.name;
    \\            if (tc.skip) std::cout << color::yellow() << " (skipped)" << color::reset();
    \\            std::cout << "\n";
    \\        }
    \\        return 0;
    \\    }
    \\    
    \\    int total = 0, passed = 0, failed = 0, skipped = 0;
    \\    auto start_time = std::chrono::high_resolution_clock::now();
    \\    
    \\    if (!c.quiet) {
    \\        std::cout << color::bold() << color::cyan() << "╔══════════════════════════════════════════════════════════╗\n";
    \\        std::cout << "║                      STIG TEST                           ║\n";
    \\        std::cout << "╚══════════════════════════════════════════════════════════╝" << color::reset() << "\n\n";
    \\    }
    \\    
    \\    for (auto& tc : tests) {
    \\        if (!matches_filter(tc.name, c.filter)) continue;
    \\        
    \\        total++;
    \\        
    \\        if (tc.skip) {
    \\            skipped++;
    \\            if (!c.quiet) {
    \\                std::cout << color::yellow() << "[ SKIPPED  ] " << color::reset() << tc.name << "\n";
    \\            }
    \\            continue;
    \\        }
    \\        
    \\        c.reset();
    \\        c.test_name = tc.name;
    \\        c.suite_name = tc.suite;
    \\        c.file = tc.file;
    \\        c.line = tc.line;
    \\        
    \\        if (!c.quiet) {
    \\            std::cout << color::bold() << "[ RUN      ] " << color::reset();
    \\            if (tc.suite) std::cout << color::dim() << tc.suite << "::" << color::reset();
    \\            std::cout << tc.name << "\n";
    \\        }
    \\        
    \\        auto test_start = std::chrono::high_resolution_clock::now();
    \\        
    \\        try {
    \\            // Run test (potentially multiple times for subcases)
    \\            do {
    \\                c.should_reenter = false;
    \\                c.subcase_depth = 0;
    \\                tc.func();
    \\            } while (c.should_reenter);
    \\            
    \\        } catch (const std::exception& e) {
    \\            c.failures++;
    \\            std::cerr << color::red() << tc.file << ":" << tc.line << ": EXCEPTION: " << e.what() << color::reset() << "\n";
    \\        } catch (...) {
    \\            c.failures++;
    \\            std::cerr << color::red() << tc.file << ":" << tc.line << ": UNKNOWN EXCEPTION" << color::reset() << "\n";
    \\        }
    \\        
    \\        auto test_end = std::chrono::high_resolution_clock::now();
    \\        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(test_end - test_start).count();
    \\        
    \\        if (c.failures > 0) {
    \\            failed++;
    \\            if (!c.quiet) {
    \\                std::cout << color::red() << color::bold() << "[  FAILED  ] " << color::reset();
    \\                std::cout << tc.name << color::dim() << " (" << duration << " us)" << color::reset() << "\n";
    \\            }
    \\        } else {
    \\            passed++;
    \\            if (!c.quiet) {
    \\                std::cout << color::green() << "[       OK ] " << color::reset();
    \\                std::cout << tc.name << color::dim() << " (" << c.assertions << " assertions, " << duration << " us)" << color::reset() << "\n";
    \\            }
    \\        }
    \\    }
    \\    
    \\    auto end_time = std::chrono::high_resolution_clock::now();
    \\    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();
    \\    
    \\    // Summary
    \\    std::cout << "\n";
    \\    std::cout << color::bold() << "══════════════════════════════════════════════════════════════\n" << color::reset();
    \\    std::cout << color::bold() << "  Total:   " << color::reset() << total << " tests";
    \\    if (skipped > 0) std::cout << color::yellow() << " (" << skipped << " skipped)" << color::reset();
    \\    std::cout << "\n";
    \\    std::cout << color::green() << color::bold() << "  Passed:  " << color::reset() << color::green() << passed << color::reset() << "\n";
    \\    if (failed > 0) {
    \\        std::cout << color::red() << color::bold() << "  Failed:  " << color::reset() << color::red() << failed << color::reset() << "\n";
    \\    }
    \\    std::cout << color::dim() << "  Time:    " << total_duration << " ms" << color::reset() << "\n";
    \\    std::cout << color::bold() << "══════════════════════════════════════════════════════════════" << color::reset() << "\n";
    \\    
    \\    return failed > 0 ? 1 : 0;
    \\}
    \\
    \\} // namespace stig
    \\
    \\// =============================================================================
    \\// MACROS - Test Definition
    \\// =============================================================================
    \\
    \\#define TEST(name) \
    \\    static void stig_test_##name(); \
    \\    static stig::TestRegistrar stig_reg_##name(#name, __FILE__, __LINE__, stig_test_##name); \
    \\    static void stig_test_##name()
    \\
    \\#define TEST_SKIP(name) \
    \\    static void stig_test_##name(); \
    \\    static stig::TestRegistrar stig_reg_##name(#name, __FILE__, __LINE__, stig_test_##name, true); \
    \\    static void stig_test_##name()
    \\
    \\#define TEST_SUITE(name) \
    \\    namespace { stig::SuiteRegistrar stig_suite_##__LINE__(name); } \
    \\    namespace
    \\
    \\#define TEST_F(fixture, name) \
    \\    struct stig_fixture_##name : public fixture { void run(); }; \
    \\    static void stig_test_##name() { stig_fixture_##name f; f.run(); } \
    \\    static stig::TestRegistrar stig_reg_##name(#fixture "::" #name, __FILE__, __LINE__, stig_test_##name); \
    \\    void stig_fixture_##name::run()
    \\
    \\#define SUBCASE(name) \
    \\    if (stig::Subcase stig_subcase_##__LINE__ = stig::Subcase(name, __FILE__, __LINE__))
    \\
    \\// =============================================================================
    \\// MACROS - Assertions (CHECK - continue on failure)
    \\// =============================================================================
    \\
    \\#define CHECK(expr) \
    \\    do { \
    \\        if (!(expr)) { stig::report_failure(#expr, __FILE__, __LINE__, "CHECK"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_FALSE(expr) \
    \\    do { \
    \\        if (expr) { stig::report_failure(#expr " is true", __FILE__, __LINE__, "CHECK_FALSE"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_EQ(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a == _b)) { stig::report_failure_cmp(#a " == " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "==", "CHECK_EQ"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_NE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a != _b)) { stig::report_failure_cmp(#a " != " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "!=", "CHECK_NE"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_LT(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a < _b)) { stig::report_failure_cmp(#a " < " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "<", "CHECK_LT"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_LE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a <= _b)) { stig::report_failure_cmp(#a " <= " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "<=", "CHECK_LE"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_GT(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a > _b)) { stig::report_failure_cmp(#a " > " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), ">", "CHECK_GT"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_GE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a >= _b)) { stig::report_failure_cmp(#a " >= " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), ">=", "CHECK_GE"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\// =============================================================================
    \\// MACROS - Assertions (REQUIRE - stop on failure)
    \\// =============================================================================
    \\
    \\#define REQUIRE(expr) \
    \\    do { \
    \\        if (!(expr)) { stig::report_failure(#expr, __FILE__, __LINE__, "REQUIRE"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_FALSE(expr) \
    \\    do { \
    \\        if (expr) { stig::report_failure(#expr " is true", __FILE__, __LINE__, "REQUIRE_FALSE"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_EQ(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a == _b)) { stig::report_failure_cmp(#a " == " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "==", "REQUIRE_EQ"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_NE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a != _b)) { stig::report_failure_cmp(#a " != " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "!=", "REQUIRE_NE"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_LT(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a < _b)) { stig::report_failure_cmp(#a " < " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "<", "REQUIRE_LT"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_LE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a <= _b)) { stig::report_failure_cmp(#a " <= " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), "<=", "REQUIRE_LE"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_GT(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a > _b)) { stig::report_failure_cmp(#a " > " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), ">", "REQUIRE_GT"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_GE(a, b) \
    \\    do { \
    \\        auto _a = (a); auto _b = (b); \
    \\        if (!(_a >= _b)) { stig::report_failure_cmp(#a " >= " #b, __FILE__, __LINE__, stig::detail::stringify(_a), stig::detail::stringify(_b), ">=", "REQUIRE_GE"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\// =============================================================================
    \\// MACROS - Assertions (WARN - log but don't fail)
    \\// =============================================================================
    \\
    \\#define WARN(expr) \
    \\    do { if (!(expr)) { stig::report_warn(#expr, __FILE__, __LINE__); } } while(0)
    \\
    \\#define WARN_FALSE(expr) \
    \\    do { if (expr) { stig::report_warn(#expr " is true", __FILE__, __LINE__); } } while(0)
    \\
    \\#define WARN_EQ(a, b) \
    \\    do { auto _a = (a); auto _b = (b); if (!(_a == _b)) { stig::report_warn(#a " == " #b, __FILE__, __LINE__); } } while(0)
    \\
    \\#define WARN_NE(a, b) \
    \\    do { auto _a = (a); auto _b = (b); if (!(_a != _b)) { stig::report_warn(#a " != " #b, __FILE__, __LINE__); } } while(0)
    \\
    \\// =============================================================================
    \\// MACROS - Exception Testing
    \\// =============================================================================
    \\
    \\#define CHECK_THROWS(expr) \
    \\    do { \
    \\        bool _threw = false; \
    \\        try { (void)(expr); } catch (...) { _threw = true; } \
    \\        if (!_threw) { stig::report_failure(#expr " should throw", __FILE__, __LINE__, "CHECK_THROWS"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_THROWS_AS(expr, exception_type) \
    \\    do { \
    \\        bool _threw_correct = false; \
    \\        try { (void)(expr); } \
    \\        catch (const exception_type&) { _threw_correct = true; } \
    \\        catch (...) { } \
    \\        if (!_threw_correct) { stig::report_failure(#expr " should throw " #exception_type, __FILE__, __LINE__, "CHECK_THROWS_AS"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_THROWS_WITH(expr, msg) \
    \\    do { \
    \\        bool _threw_with_msg = false; \
    \\        try { (void)(expr); } \
    \\        catch (const std::exception& e) { _threw_with_msg = (std::string(e.what()).find(msg) != std::string::npos); } \
    \\        catch (...) { } \
    \\        if (!_threw_with_msg) { stig::report_failure(#expr " should throw with message \"" msg "\"", __FILE__, __LINE__, "CHECK_THROWS_WITH"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define CHECK_NOTHROW(expr) \
    \\    do { \
    \\        bool _threw = false; \
    \\        try { (void)(expr); } catch (...) { _threw = true; } \
    \\        if (_threw) { stig::report_failure(#expr " should not throw", __FILE__, __LINE__, "CHECK_NOTHROW"); } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_THROWS(expr) \
    \\    do { \
    \\        bool _threw = false; \
    \\        try { (void)(expr); } catch (...) { _threw = true; } \
    \\        if (!_threw) { stig::report_failure(#expr " should throw", __FILE__, __LINE__, "REQUIRE_THROWS"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_THROWS_AS(expr, exception_type) \
    \\    do { \
    \\        bool _threw_correct = false; \
    \\        try { (void)(expr); } \
    \\        catch (const exception_type&) { _threw_correct = true; } \
    \\        catch (...) { } \
    \\        if (!_threw_correct) { stig::report_failure(#expr " should throw " #exception_type, __FILE__, __LINE__, "REQUIRE_THROWS_AS"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\#define REQUIRE_NOTHROW(expr) \
    \\    do { \
    \\        bool _threw = false; \
    \\        try { (void)(expr); } catch (...) { _threw = true; } \
    \\        if (_threw) { stig::report_failure(#expr " should not throw", __FILE__, __LINE__, "REQUIRE_NOTHROW"); return; } \
    \\        else { stig::report_success(); } \
    \\    } while(0)
    \\
    \\// =============================================================================
    \\// MACROS - Logging & Debugging
    \\// =============================================================================
    \\
    \\#define INFO(msg) \
    \\    stig::InfoScope stig_info_##__LINE__(msg)
    \\
    \\#define CAPTURE(var) \
    \\    stig::add_capture(#var, stig::detail::stringify(var))
    \\
    \\#define MESSAGE(msg) \
    \\    std::cout << stig::color::cyan() << "  message: " << stig::color::reset() << msg << "\n"
    \\
    \\#define FAIL(msg) \
    \\    do { stig::report_failure(msg, __FILE__, __LINE__, "FAIL"); return; } while(0)
    \\
    \\#define FAIL_CHECK(msg) \
    \\    do { stig::report_failure(msg, __FILE__, __LINE__, "FAIL_CHECK"); } while(0)
    \\
    \\// =============================================================================
    \\// MAIN - Auto-generated entry point
    \\// =============================================================================
    \\
    \\int main(int argc, char** argv) {
    \\    return stig::run_all(argc, argv);
    \\}
    \\
    \\#endif // STIG_HPP
    \\
;

/// Runs the init command
pub fn runInit(allocator: std.mem.Allocator, config_path: ?[]const u8, force: bool) !void {
    var cmd = InitCommand.init(allocator, config_path, force);
    try cmd.run();
}
