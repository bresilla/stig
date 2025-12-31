/**
 * @file docstrings.h
 * @brief Test fixture for various docstring formats
 */

#ifndef DOCSTRINGS_H
#define DOCSTRINGS_H

/* ============================================
 * Doxygen-style documentation
 * ============================================ */

/**
 * @brief Multiplies two integers.
 *
 * This function performs integer multiplication.
 * It handles negative numbers correctly.
 *
 * @param x First factor
 * @param y Second factor
 * @return Product of x and y
 *
 * @note This is a simple implementation.
 * @deprecated Use multiply_safe() instead for overflow checking.
 */
int multiply(int x, int y);

/**
 * Divides a by b.
 * @param a Dividend
 * @param b Divisor (must not be zero)
 * @return Quotient
 * @warning Division by zero is undefined behavior.
 */
int divide(int a, int b);

/* ============================================
 * Triple-slash style documentation
 * ============================================ */

/// Calculates the absolute value of an integer.
///
/// Returns the non-negative value of the input.
/// For INT_MIN, behavior is undefined due to overflow.
///
/// @param n Input integer
/// @return Absolute value of n
int abs_value(int n);

/// Finds the maximum of two integers.
/// @param a First value
/// @param b Second value
/// @return The larger of a and b
int max(int a, int b);

/// Finds the minimum of two integers.
int min(int a, int b);

/* ============================================
 * Multi-line block comments
 * ============================================ */

/*
 * Computes the factorial of n.
 *
 * This uses an iterative approach for efficiency.
 * For n > 20, the result may overflow.
 */
long factorial(int n);

/**
   Computes the power of base raised to exp.

   Uses repeated multiplication.
   Negative exponents return 0 (integer division).
 */
long power(int base, int exp);

/* ============================================
 * No documentation (should still be parsed)
 * ============================================ */

int undocumented_function(int x);

void another_undocumented(void);

/* ============================================
 * Mixed styles in structs
 * ============================================ */

/**
 * @brief A rectangle defined by position and size.
 */
struct Rectangle {
    int x;      /**< X position of top-left corner */
    int y;      /**< Y position of top-left corner */
    int width;  ///< Width of the rectangle
    int height; ///< Height of the rectangle
};

/// A circle defined by center and radius.
struct Circle {
    int cx;     ///< Center X coordinate
    int cy;     ///< Center Y coordinate
    int radius; /**< Radius of the circle */
};

/* ============================================
 * Enum with mixed documentation
 * ============================================ */

/**
 * Log levels for the application.
 */
enum LogLevel {
    LOG_DEBUG = 0,   /**< Debug messages */
    LOG_INFO = 1,    ///< Informational messages
    LOG_WARNING = 2, /* Warning messages */
    LOG_ERROR = 3,   /**< Error messages */
    LOG_FATAL = 4    // Fatal errors (no doc marker)
};

#endif /* DOCSTRINGS_H */
