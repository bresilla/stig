/**
 * @file test_todo_bug.h
 * @brief Test file for @todo and @bug tags
 */

#ifndef TEST_TODO_BUG_H
#define TEST_TODO_BUG_H

#include <stddef.h>

/**
 * @brief Sorts an array of integers
 * @param arr The array to sort
 * @param n The number of elements
 * @todo Implement parallel sorting for large arrays
 * @todo Add support for custom comparators
 * @bug Does not handle empty arrays correctly (issue #123)
 */
void sort(int* arr, size_t n);

/**
 * @brief Normalizes a vector to unit length
 * @param x The x component
 * @param y The y component
 * @return The normalized vector
 * \todo Handle zero-length vectors
 * \bug Division by zero possible when both components are zero
 */
float* normalize(float x, float y);

/**
 * @brief A sample class with todos and bugs
 * @todo Add serialization support
 * @bug Memory leak in destructor
 */
class SampleClass {
public:
    /**
     * @brief Process the data
     * @param data Input data
     * @todo Add validation for input data
     * @bug Crashes on null pointer
     */
    void process(void* data);
};

#endif // TEST_TODO_BUG_H
