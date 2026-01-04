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
        std.debug.print("  1. Write tests in test/test_*.cpp using STIG_TEST macro\n", .{});
        std.debug.print("  2. Run 'stig test' to compile and run tests\n", .{});
        std.debug.print("  3. Add @test tags to your documentation to link tests\n", .{});
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
            \\# See: https://github.com/your-repo/stig
            \\
            \\# Documentation settings
            \\title = "API Reference"
            \\output = "docs"
            \\format = "mdbook"
            \\inputs = ["include/**/*.hpp", "include/**/*.h"]
            \\
        ;

        const file = try std.fs.cwd().createFile(self.config_path, .{});
        defer file.close();
        try file.writeAll(config_content);

        std.debug.print("  Created: {s}\n", .{self.config_path});
    }

    fn generateTestHeader(self: *Self) !void {
        const path = "test/stig_test.h";

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
            \\// Example test file - demonstrates stig test macros
            \\// Delete this file and create your own test_*.cpp files
            \\
            \\#include "stig_test.h"
            \\
            \\// Basic test example
            \\STIG_TEST(test_example_basic) {
            \\    STIG_CHECK(1 + 1 == 2);
            \\    STIG_CHECK_EQ(2 * 3, 6);
            \\    STIG_CHECK_NE(1, 2);
            \\}
            \\
            \\// Test with REQUIRE (stops on failure)
            \\STIG_TEST(test_example_require) {
            \\    int* ptr = nullptr;
            \\    // STIG_REQUIRE stops the test if it fails
            \\    // STIG_REQUIRE(ptr != nullptr);
            \\    
            \\    // This would only run if the above passed
            \\    STIG_CHECK(true);
            \\}
            \\
            \\// Comparison macros
            \\STIG_TEST(test_example_comparisons) {
            \\    STIG_CHECK_LT(1, 2);   // less than
            \\    STIG_CHECK_LE(2, 2);   // less or equal
            \\    STIG_CHECK_GT(3, 2);   // greater than
            \\    STIG_CHECK_GE(3, 3);   // greater or equal
            \\}
            \\
            \\// Exception testing (C++ only)
            \\STIG_TEST(test_example_exceptions) {
            \\    // Check that an expression throws
            \\    STIG_CHECK_THROWS(throw std::runtime_error("expected"));
            \\    
            \\    // Check that an expression does NOT throw
            \\    STIG_CHECK_NOTHROW(int x = 42; (void)x);
            \\}
            \\
        ;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(example_content);

        std.debug.print("  Created: {s}\n", .{path});
    }
};

/// The stig_test.h header content - a single-header test framework
const stig_test_header =
    \\// =============================================================================
    \\// stig_test.h - Single-header C++ test framework
    \\// Auto-generated by stig - https://github.com/your-repo/stig
    \\// =============================================================================
    \\//
    \\// Usage:
    \\//   #include "stig_test.h"
    \\//
    \\//   STIG_TEST(test_name) {
    \\//       STIG_CHECK(condition);
    \\//       STIG_CHECK_EQ(a, b);
    \\//       STIG_REQUIRE(must_be_true);
    \\//   }
    \\//
    \\// =============================================================================
    \\
    \\#ifndef STIG_TEST_H
    \\#define STIG_TEST_H
    \\
    \\#include <iostream>
    \\#include <vector>
    \\#include <string>
    \\#include <functional>
    \\#include <cstring>
    \\#include <exception>
    \\#include <sstream>
    \\
    \\namespace stig {
    \\namespace test {
    \\
    \\// =============================================================================
    \\// Test Registration
    \\// =============================================================================
    \\
    \\struct TestCase {
    \\    const char* name;
    \\    const char* file;
    \\    int line;
    \\    std::function<void()> func;
    \\};
    \\
    \\inline std::vector<TestCase>& registry() {
    \\    static std::vector<TestCase> tests;
    \\    return tests;
    \\}
    \\
    \\struct TestRegistrar {
    \\    TestRegistrar(const char* name, const char* file, int line, std::function<void()> func) {
    \\        registry().push_back({name, file, line, func});
    \\    }
    \\};
    \\
    \\// =============================================================================
    \\// Test Context (tracks assertions and failures)
    \\// =============================================================================
    \\
    \\struct Context {
    \\    int assertions = 0;
    \\    int failures = 0;
    \\    const char* current_test = nullptr;
    \\    const char* current_file = nullptr;
    \\    int current_line = 0;
    \\};
    \\
    \\inline Context& ctx() {
    \\    static Context c;
    \\    return c;
    \\}
    \\
    \\// =============================================================================
    \\// Reporting
    \\// =============================================================================
    \\
    \\inline void report_failure(const char* expr, const char* file, int line) {
    \\    std::cerr << file << ":" << line << ": FAILED: " << expr << "\n";
    \\    ctx().failures++;
    \\}
    \\
    \\inline void report_failure_with_values(const char* expr, const char* file, int line,
    \\                                        const std::string& lhs, const std::string& rhs) {
    \\    std::cerr << file << ":" << line << ": FAILED: " << expr << "\n";
    \\    std::cerr << "  Left:  " << lhs << "\n";
    \\    std::cerr << "  Right: " << rhs << "\n";
    \\    ctx().failures++;
    \\}
    \\
    \\inline void report_success() {
    \\    ctx().assertions++;
    \\}
    \\
    \\// =============================================================================
    \\// Value to string conversion
    \\// =============================================================================
    \\
    \\template<typename T>
    \\inline std::string to_string(const T& value) {
    \\    std::ostringstream oss;
    \\    oss << value;
    \\    return oss.str();
    \\}
    \\
    \\// Specialization for bool
    \\template<>
    \\inline std::string to_string(const bool& value) {
    \\    return value ? "true" : "false";
    \\}
    \\
    \\// Specialization for nullptr
    \\inline std::string to_string(std::nullptr_t) {
    \\    return "nullptr";
    \\}
    \\
    \\// =============================================================================
    \\// Test Runner
    \\// =============================================================================
    \\
    \\inline int run_all() {
    \\    int failed = 0;
    \\    int passed = 0;
    \\    
    \\    std::cout << "Running " << registry().size() << " test(s)...\n\n";
    \\    
    \\    for (auto& tc : registry()) {
    \\        ctx().current_test = tc.name;
    \\        ctx().current_file = tc.file;
    \\        ctx().current_line = tc.line;
    \\        ctx().assertions = 0;
    \\        ctx().failures = 0;
    \\        
    \\        std::cout << "[ RUN      ] " << tc.name << "\n";
    \\        
    \\        try {
    \\            tc.func();
    \\        } catch (const std::exception& e) {
    \\            std::cerr << tc.file << ":" << tc.line << ": EXCEPTION: " << e.what() << "\n";
    \\            ctx().failures++;
    \\        } catch (...) {
    \\            std::cerr << tc.file << ":" << tc.line << ": UNKNOWN EXCEPTION\n";
    \\            ctx().failures++;
    \\        }
    \\        
    \\        if (ctx().failures > 0) {
    \\            failed++;
    \\            std::cout << "[  FAILED  ] " << tc.name << " (" << ctx().failures << " failure(s))\n";
    \\        } else {
    \\            passed++;
    \\            std::cout << "[       OK ] " << tc.name << " (" << ctx().assertions << " assertion(s))\n";
    \\        }
    \\    }
    \\    
    \\    std::cout << "\n";
    \\    std::cout << "==========================================================\n";
    \\    std::cout << "Total: " << registry().size() << " test(s)\n";
    \\    std::cout << "Passed: " << passed << "\n";
    \\    std::cout << "Failed: " << failed << "\n";
    \\    std::cout << "==========================================================\n";
    \\    
    \\    return failed > 0 ? 1 : 0;
    \\}
    \\
    \\} // namespace test
    \\} // namespace stig
    \\
    \\// =============================================================================
    \\// MACROS
    \\// =============================================================================
    \\
    \\// Define a test case
    \\#define STIG_TEST(name) \
    \\    static void stig_test_##name(); \
    \\    static stig::test::TestRegistrar stig_reg_##name(#name, __FILE__, __LINE__, stig_test_##name); \
    \\    static void stig_test_##name()
    \\
    \\// Basic check - continues on failure
    \\#define STIG_CHECK(expr) \
    \\    do { \
    \\        if (!(expr)) { \
    \\            stig::test::report_failure(#expr, __FILE__, __LINE__); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\// Require - stops test on failure
    \\#define STIG_REQUIRE(expr) \
    \\    do { \
    \\        if (!(expr)) { \
    \\            stig::test::report_failure(#expr, __FILE__, __LINE__); \
    \\            return; \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\// Comparison checks with value reporting
    \\#define STIG_CHECK_EQ(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a == _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " == " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_NE(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a != _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " != " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_LT(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a < _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " < " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_LE(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a <= _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " <= " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_GT(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a > _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " > " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_GE(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a >= _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " >= " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\// Require variants (stop on failure)
    \\#define STIG_REQUIRE_EQ(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a == _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " == " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\            return; \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_REQUIRE_NE(a, b) \
    \\    do { \
    \\        auto _stig_a = (a); \
    \\        auto _stig_b = (b); \
    \\        if (!(_stig_a != _stig_b)) { \
    \\            stig::test::report_failure_with_values(#a " != " #b, __FILE__, __LINE__, \
    \\                stig::test::to_string(_stig_a), stig::test::to_string(_stig_b)); \
    \\            return; \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\// Exception testing
    \\#define STIG_CHECK_THROWS(expr) \
    \\    do { \
    \\        bool _stig_threw = false; \
    \\        try { expr; } catch (...) { _stig_threw = true; } \
    \\        if (!_stig_threw) { \
    \\            stig::test::report_failure(#expr " should throw", __FILE__, __LINE__); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_CHECK_NOTHROW(expr) \
    \\    do { \
    \\        bool _stig_threw = false; \
    \\        try { expr; } catch (...) { _stig_threw = true; } \
    \\        if (_stig_threw) { \
    \\            stig::test::report_failure(#expr " should not throw", __FILE__, __LINE__); \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_REQUIRE_THROWS(expr) \
    \\    do { \
    \\        bool _stig_threw = false; \
    \\        try { expr; } catch (...) { _stig_threw = true; } \
    \\        if (!_stig_threw) { \
    \\            stig::test::report_failure(#expr " should throw", __FILE__, __LINE__); \
    \\            return; \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\#define STIG_REQUIRE_NOTHROW(expr) \
    \\    do { \
    \\        bool _stig_threw = false; \
    \\        try { expr; } catch (...) { _stig_threw = true; } \
    \\        if (_stig_threw) { \
    \\            stig::test::report_failure(#expr " should not throw", __FILE__, __LINE__); \
    \\            return; \
    \\        } else { \
    \\            stig::test::report_success(); \
    \\        } \
    \\    } while(0)
    \\
    \\// =============================================================================
    \\// MAIN - Auto-generated entry point
    \\// =============================================================================
    \\
    \\int main(int argc, char** argv) {
    \\    (void)argc;
    \\    (void)argv;
    \\    return stig::test::run_all();
    \\}
    \\
    \\#endif // STIG_TEST_H
    \\
;

/// Runs the init command
pub fn runInit(allocator: std.mem.Allocator, config_path: ?[]const u8, force: bool) !void {
    var cmd = InitCommand.init(allocator, config_path, force);
    try cmd.run();
}
