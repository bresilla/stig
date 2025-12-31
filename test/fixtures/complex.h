/**
 * @file complex.h
 * @brief Test fixture for complex C constructs and edge cases
 */

#ifndef COMPLEX_H
#define COMPLEX_H

#include <stddef.h>

/* ============================================
 * Macros (should be ignored or handled gracefully)
 * ============================================ */

#define MAX_BUFFER_SIZE 1024
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define STRINGIFY(x) #x

/* ============================================
 * Forward declarations
 * ============================================ */

struct Node;
struct Tree;
typedef struct Node Node;

/* ============================================
 * Function pointers
 * ============================================ */

/**
 * @brief Comparison function type.
 * @param a First element to compare
 * @param b Second element to compare
 * @return Negative if a < b, zero if equal, positive if a > b
 */
typedef int (*compare_fn)(const void *a, const void *b);

/**
 * @brief Callback function for iteration.
 * @param item Current item being visited
 * @param user_data User-provided context
 * @return Non-zero to continue, zero to stop iteration
 */
typedef int (*iterator_fn)(void *item, void *user_data);

/// Destructor function type for cleanup.
typedef void (*destructor_fn)(void *ptr);

/* ============================================
 * Nested structs
 * ============================================ */

/**
 * @brief A 3D vector with nested components.
 */
struct Vector3D {
    /**
     * @brief X-Y plane component.
     */
    struct {
        float x; /**< X coordinate */
        float y; /**< Y coordinate */
    } xy;
    float z; /**< Z coordinate */
};

/**
 * @brief Configuration with nested options.
 */
struct Config {
    /// Display settings
    struct {
        int width;      ///< Screen width in pixels
        int height;     ///< Screen height in pixels
        int fullscreen; ///< Non-zero for fullscreen mode
    } display;

    /// Audio settings
    struct {
        float volume; /**< Volume level (0.0 to 1.0) */
        int muted;    /**< Non-zero if muted */
    } audio;

    const char *name; ///< Configuration name
};

/* ============================================
 * Struct with function pointer members
 * ============================================ */

/**
 * @brief Generic container interface.
 *
 * Provides a vtable-like structure for polymorphic containers.
 */
struct Container {
    void *data;      /**< Internal data storage */
    size_t size;     /**< Number of elements */
    size_t capacity; /**< Allocated capacity */

    /// Adds an element to the container.
    int (*add)(struct Container *self, void *element);

    /// Removes an element from the container.
    int (*remove)(struct Container *self, void *element);

    /// Finds an element in the container.
    void *(*find)(struct Container *self, const void *key, compare_fn cmp);

    /// Iterates over all elements.
    void (*foreach)(struct Container *self, iterator_fn fn, void *user_data);

    /// Destroys the container and frees resources.
    void (*destroy)(struct Container *self);
};

/* ============================================
 * Complex typedefs
 * ============================================ */

/// Pointer to a function returning a pointer to a function.
typedef int (*(*factory_fn)(const char *name))(int, int);

/// Array of function pointers.
typedef void (*callback_array[8])(int);

/// Pointer to const pointer to const char (immutable string handle).
typedef const char *const *string_handle;

/// Unsigned 8-bit byte type.
typedef unsigned char byte_t;

/// Signed size type for differences.
typedef long ssize_t;

/* ============================================
 * Enums with explicit values and gaps
 * ============================================ */

/**
 * @brief Error codes with explicit values.
 */
enum ErrorCode {
    ERR_OK = 0,             /**< Success */
    ERR_INVALID_ARG = -1,   /**< Invalid argument */
    ERR_OUT_OF_MEMORY = -2, /**< Memory allocation failed */
    ERR_IO = -100,          /**< I/O error (gap in values) */
    ERR_NETWORK = -101,     /**< Network error */
    ERR_TIMEOUT = -102,     /**< Operation timed out */
    ERR_UNKNOWN = -999      /**< Unknown error */
};

/// Bit flags for file permissions.
enum FilePermissions {
    PERM_NONE = 0,                                ///< No permissions
    PERM_READ = 1 << 0,                           ///< Read permission
    PERM_WRITE = 1 << 1,                          ///< Write permission
    PERM_EXEC = 1 << 2,                           ///< Execute permission
    PERM_ALL = PERM_READ | PERM_WRITE | PERM_EXEC ///< All permissions
};

/* ============================================
 * Functions with complex signatures
 * ============================================ */

/**
 * @brief Sorts an array using a custom comparator.
 * @param base Pointer to the first element
 * @param count Number of elements
 * @param size Size of each element in bytes
 * @param cmp Comparison function
 */
void sort_array(void *base, size_t count, size_t size, compare_fn cmp);

/**
 * @brief Creates a new container with the given callbacks.
 * @param add_fn Function to add elements
 * @param remove_fn Function to remove elements
 * @param destroy_fn Destructor for cleanup
 * @return Newly allocated container, or NULL on failure
 */
struct Container *container_create(int (*add_fn)(struct Container *, void *),
                                   int (*remove_fn)(struct Container *, void *), destructor_fn destroy_fn);

/// Processes data with optional callback.
int process_data(const void *input, size_t len, void (*callback)(int status));

/**
 * @brief Variadic function example.
 * @param fmt Format string
 * @param ... Variable arguments
 * @return Number of characters written
 */
int log_printf(const char *fmt, ...);

/* ============================================
 * Const and volatile qualifiers
 * ============================================ */

/**
 * @brief Reads a value from a memory-mapped register.
 * @param addr Register address
 * @return Value at the address
 */
unsigned int read_register(volatile unsigned int *addr);

/**
 * @brief Writes a value to a memory-mapped register.
 * @param addr Register address
 * @param value Value to write
 */
void write_register(volatile unsigned int *addr, unsigned int value);

/// Gets a read-only string constant.
const char *get_version_string(void);

/* ============================================
 * Static inline functions (common in headers)
 * ============================================ */

/**
 * @brief Swaps two integers.
 * @param a Pointer to first integer
 * @param b Pointer to second integer
 */
static inline void swap_int(int *a, int *b) {
    int tmp = *a;
    *a = *b;
    *b = tmp;
}

/// Clamps a value to a range.
static inline int clamp(int value, int min, int max) {
    if (value < min)
        return min;
    if (value > max)
        return max;
    return value;
}

/* ============================================
 * Extern declarations
 * ============================================ */

/// Global error message buffer.
extern char error_message[256];

/// Global debug flag.
extern int debug_enabled;

#endif /* COMPLEX_H */
