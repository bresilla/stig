/**
 * @file test_test_tag.h
 * @brief Test file for @test tag feature
 */

#ifndef TEST_TEST_TAG_H
#define TEST_TEST_TAG_H

/**
 * @brief Calculates the factorial of a number
 * 
 * This function computes the factorial of a non-negative integer.
 * 
 * @param n The input number (must be >= 0)
 * @return The factorial of n
 * @test test_factorial_basic
 * @test test_factorial_zero
 * @test test_factorial_negative test/test_math.cpp
 */
int factorial(int n);

/**
 * @brief Adds two numbers together
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 * \test test_add_positive
 * \test test_add_negative test/test_math.cpp
 */
int add(int a, int b);

/**
 * @brief A struct with test references
 * @test test_point_init
 * @test test_point_distance test/test_geometry.cpp
 */
typedef struct {
    int x;
    int y;
} Point;

#endif /* TEST_TEST_TAG_H */
