/**
 * @file macros.h
 * @brief Test file for macro documentation
 */

#ifndef MACROS_H
#define MACROS_H

/** Version number */
#define VERSION 1

/** Major version */
#define VERSION_MAJOR 1

/** Minor version */
#define VERSION_MINOR 0

/** Patch version */
#define VERSION_PATCH 0

/**
 * Returns the maximum of two values.
 * @param a First value
 * @param b Second value
 * @warning Both arguments are evaluated twice
 */
#define MAX(a, b) ((a) > (b) ? (a) : (b))

/**
 * Returns the minimum of two values.
 * @param a First value
 * @param b Second value
 */
#define MIN(a, b) ((a) < (b) ? (a) : (b))

/**
 * Swaps two values.
 * @param a First value (will contain b's value)
 * @param b Second value (will contain a's value)
 * @param type The type of the values
 * @note Uses a temporary variable
 */
#define SWAP(a, b, type)                                                                                               \
    do {                                                                                                               \
        type _tmp = (a);                                                                                               \
        (a) = (b);                                                                                                     \
        (b) = _tmp;                                                                                                    \
    } while (0)

/** Array size helper */
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

/**
 * Stringify macro argument.
 * @param x Value to stringify
 */
#define STRINGIFY(x) #x

/**
 * Concatenate two tokens.
 * @param a First token
 * @param b Second token
 */
#define CONCAT(a, b) a##b

/** Debug print macro */
#ifdef DEBUG
#define DEBUG_PRINT(fmt, ...) printf("DEBUG: " fmt "\n", ##__VA_ARGS__)
#else
#define DEBUG_PRINT(fmt, ...)
#endif

/** Unused parameter marker */
#define UNUSED(x) (void)(x)

/**
 * Alignment macro.
 * @param x Value to align
 * @param align Alignment boundary (must be power of 2)
 */
#define ALIGN(x, align) (((x) + ((align) - 1)) & ~((align) - 1))

/** Compile-time assertion */
#define STATIC_ASSERT(cond, msg) typedef char static_assertion_##msg[(cond) ? 1 : -1]

#endif /* MACROS_H */
