/**
 * @file test_snippet.h
 * @brief Test file for @snippet tag functionality
 */

#ifndef TEST_SNIPPET_H
#define TEST_SNIPPET_H

/**
 * @brief Demonstrates the hello world example
 * 
 * This function shows a simple greeting.
 * 
 * @snippet examples/test_snippet.cpp hello
 */
void show_hello();

/**
 * @brief Demonstrates basic vector usage
 * 
 * This function shows how to use vectors.
 * 
 * \snippet examples/test_snippet.cpp basic_usage
 */
void show_basic_usage();

/**
 * @brief Shows advanced vector operations
 * 
 * This function demonstrates advanced patterns.
 * 
 * @snippet examples/test_snippet.cpp advanced_usage
 */
void show_advanced();

/**
 * @brief A Calculator class example
 * 
 * See how to implement a calculator:
 * 
 * @snippet examples/test_snippet.cpp multiline_example
 * 
 * @note This is a simple implementation
 */
void show_calculator();

/**
 * @brief Function with inline example and snippet
 * 
 * @example int x = 42;
 * @snippet examples/test_snippet.cpp hello
 */
void mixed_examples();

/**
 * @brief Test missing snippet file
 * 
 * @snippet nonexistent.cpp missing
 */
void missing_file_test();

/**
 * @brief Test missing anchor
 * 
 * @snippet examples/test_snippet.cpp nonexistent_anchor
 */
void missing_anchor_test();

/**
 * @brief Test with explicit language override
 * 
 * @snippet examples/test_snippet.cpp hello c
 */
void explicit_language_test();

#endif // TEST_SNIPPET_H
