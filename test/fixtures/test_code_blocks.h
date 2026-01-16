/**
 * @file test_code_blocks.h
 * @brief Test file for @code/@endcode blocks with language hints
 */

/**
 * @brief Example function with multiple code blocks
 *
 * This function demonstrates different code block formats.
 *
 * @code{.cpp}
 * int x = 42;
 * std::cout << x << std::endl;
 * @endcode
 *
 * @code{.python}
 * x = 42
 * print(x)
 * @endcode
 *
 * @code{.cpp,lineno}
 * // Line numbers will be shown
 * int a = 1;
 * int b = 2;
 * @endcode
 *
 * @code
 * // Default language (cpp)
 * auto val = getValue();
 * @endcode
 *
 * @param value The input value
 * @return The processed result
 */
int example(int value);

/**
 * @brief Another function with backslash-style code block
 *
 * \code{.javascript}
 * const x = 42;
 * console.log(x);
 * \endcode
 */
void another_example();
