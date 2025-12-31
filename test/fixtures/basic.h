/**
 * @file basic.h
 * @brief Basic test fixture for stinger
 */

#ifndef BASIC_H
#define BASIC_H

/**
 * @brief Adds two integers together.
 * @param a First operand
 * @param b Second operand
 * @return Sum of a and b
 */
int add(int a, int b);

/**
 * @brief Subtracts b from a.
 * @param a Minuend
 * @param b Subtrahend
 * @return Difference (a - b)
 */
int subtract(int a, int b);

/// A simple 2D point structure.
/// Used for representing coordinates.
struct Point {
    int x; ///< X coordinate
    int y; ///< Y coordinate
};

/**
 * Color enumeration.
 * Represents basic RGB colors.
 */
enum Color {
    RED = 0,   /**< Red color */
    GREEN = 1, /**< Green color */
    BLUE = 2   /**< Blue color */
};

/// Typedef for unsigned 32-bit integer
typedef unsigned int uint32;

#endif /* BASIC_H */
