/**
 * @file real_world.h
 * @brief A realistic header file simulating a small library API
 * @author Stinger Test Suite
 * @version 1.0.0
 *
 * This header demonstrates a realistic C library API with:
 * - Memory management
 * - Data structures
 * - Error handling
 * - Configuration
 */

#ifndef REAL_WORLD_H
#define REAL_WORLD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================
 * Version Information
 * ============================================ */

#define REALWORLD_VERSION_MAJOR 1
#define REALWORLD_VERSION_MINOR 0
#define REALWORLD_VERSION_PATCH 0

/* ============================================
 * Error Handling
 * ============================================ */

/**
 * @brief Result codes for library operations.
 *
 * All functions return these codes to indicate success or failure.
 * Use rw_strerror() to get a human-readable description.
 */
typedef enum {
    RW_OK = 0,             /**< Operation succeeded */
    RW_ERR_NOMEM = -1,     /**< Memory allocation failed */
    RW_ERR_INVALID = -2,   /**< Invalid argument */
    RW_ERR_NOT_FOUND = -3, /**< Item not found */
    RW_ERR_EXISTS = -4,    /**< Item already exists */
    RW_ERR_FULL = -5,      /**< Container is full */
    RW_ERR_EMPTY = -6,     /**< Container is empty */
    RW_ERR_IO = -7         /**< I/O operation failed */
} rw_result_t;

/**
 * @brief Returns a human-readable error description.
 * @param result The result code to describe
 * @return Static string describing the error (never NULL)
 */
const char *rw_strerror(rw_result_t result);

/* ============================================
 * Memory Allocator Interface
 * ============================================ */

/**
 * @brief Custom memory allocator interface.
 *
 * Allows users to provide their own memory allocation functions.
 * All fields must be non-NULL for a valid allocator.
 */
typedef struct {
    /**
     * @brief Allocates memory.
     * @param size Number of bytes to allocate
     * @param user_data User-provided context
     * @return Pointer to allocated memory, or NULL on failure
     */
    void *(*alloc)(size_t size, void *user_data);

    /**
     * @brief Reallocates memory.
     * @param ptr Pointer to existing allocation (may be NULL)
     * @param size New size in bytes
     * @param user_data User-provided context
     * @return Pointer to reallocated memory, or NULL on failure
     */
    void *(*realloc)(void *ptr, size_t size, void *user_data);

    /**
     * @brief Frees memory.
     * @param ptr Pointer to free (may be NULL)
     * @param user_data User-provided context
     */
    void (*free)(void *ptr, void *user_data);

    void *user_data; /**< User-provided context passed to all functions */
} rw_allocator_t;

/// Default allocator using malloc/realloc/free.
extern const rw_allocator_t rw_default_allocator;

/* ============================================
 * String Buffer
 * ============================================ */

/**
 * @brief Dynamic string buffer for efficient string building.
 *
 * Automatically grows as needed. Must be initialized before use
 * and freed when done.
 *
 * @code
 * rw_strbuf_t buf;
 * rw_strbuf_init(&buf, NULL);
 * rw_strbuf_append(&buf, "Hello, ");
 * rw_strbuf_append(&buf, "World!");
 * printf("%s\n", rw_strbuf_cstr(&buf));
 * rw_strbuf_free(&buf);
 * @endcode
 */
typedef struct {
    char *data;            /**< Internal buffer (may be NULL if empty) */
    size_t len;            /**< Current string length (excluding null) */
    size_t cap;            /**< Allocated capacity */
    rw_allocator_t *alloc; /**< Allocator (NULL for default) */
} rw_strbuf_t;

/**
 * @brief Initializes a string buffer.
 * @param buf Buffer to initialize
 * @param alloc Custom allocator (NULL for default)
 */
void rw_strbuf_init(rw_strbuf_t *buf, rw_allocator_t *alloc);

/**
 * @brief Frees a string buffer's resources.
 * @param buf Buffer to free
 */
void rw_strbuf_free(rw_strbuf_t *buf);

/**
 * @brief Appends a string to the buffer.
 * @param buf Target buffer
 * @param str String to append (must not be NULL)
 * @return RW_OK on success, error code on failure
 */
rw_result_t rw_strbuf_append(rw_strbuf_t *buf, const char *str);

/**
 * @brief Appends formatted text to the buffer.
 * @param buf Target buffer
 * @param fmt Format string (printf-style)
 * @param ... Format arguments
 * @return RW_OK on success, error code on failure
 */
rw_result_t rw_strbuf_appendf(rw_strbuf_t *buf, const char *fmt, ...);

/**
 * @brief Returns the buffer contents as a C string.
 * @param buf Buffer to read
 * @return Null-terminated string (empty string if buffer is empty)
 */
const char *rw_strbuf_cstr(const rw_strbuf_t *buf);

/**
 * @brief Clears the buffer without freeing memory.
 * @param buf Buffer to clear
 */
void rw_strbuf_clear(rw_strbuf_t *buf);

/* ============================================
 * Hash Map
 * ============================================ */

/// Opaque hash map handle.
typedef struct rw_hashmap rw_hashmap_t;

/**
 * @brief Hash function type.
 * @param key Key to hash
 * @param len Key length in bytes
 * @return Hash value
 */
typedef uint64_t (*rw_hash_fn)(const void *key, size_t len);

/**
 * @brief Key comparison function type.
 * @param a First key
 * @param b Second key
 * @param len Key length in bytes
 * @return Non-zero if keys are equal, zero otherwise
 */
typedef int (*rw_equal_fn)(const void *a, const void *b, size_t len);

/**
 * @brief Hash map configuration.
 */
typedef struct {
    size_t initial_capacity; /**< Initial bucket count (0 for default) */
    size_t key_size;         /**< Size of keys in bytes */
    size_t value_size;       /**< Size of values in bytes */
    rw_hash_fn hash;         /**< Hash function (NULL for default) */
    rw_equal_fn equal;       /**< Equality function (NULL for default) */
    rw_allocator_t *alloc;   /**< Custom allocator (NULL for default) */
} rw_hashmap_config_t;

/**
 * @brief Creates a new hash map.
 * @param config Configuration (NULL for all defaults)
 * @return New hash map, or NULL on allocation failure
 */
rw_hashmap_t *rw_hashmap_create(const rw_hashmap_config_t *config);

/**
 * @brief Destroys a hash map and frees all resources.
 * @param map Map to destroy (may be NULL)
 */
void rw_hashmap_destroy(rw_hashmap_t *map);

/**
 * @brief Inserts or updates a key-value pair.
 * @param map Target map
 * @param key Key to insert
 * @param value Value to associate with key
 * @return RW_OK on success, error code on failure
 */
rw_result_t rw_hashmap_put(rw_hashmap_t *map, const void *key, const void *value);

/**
 * @brief Retrieves a value by key.
 * @param map Map to search
 * @param key Key to look up
 * @param value_out Output buffer for value (may be NULL to check existence)
 * @return RW_OK if found, RW_ERR_NOT_FOUND otherwise
 */
rw_result_t rw_hashmap_get(const rw_hashmap_t *map, const void *key, void *value_out);

/**
 * @brief Removes a key-value pair.
 * @param map Target map
 * @param key Key to remove
 * @return RW_OK if removed, RW_ERR_NOT_FOUND if not present
 */
rw_result_t rw_hashmap_remove(rw_hashmap_t *map, const void *key);

/**
 * @brief Returns the number of entries in the map.
 * @param map Map to query
 * @return Number of key-value pairs
 */
size_t rw_hashmap_size(const rw_hashmap_t *map);

/**
 * @brief Checks if the map is empty.
 * @param map Map to query
 * @return Non-zero if empty, zero otherwise
 */
int rw_hashmap_empty(const rw_hashmap_t *map);

/**
 * @brief Removes all entries from the map.
 * @param map Map to clear
 */
void rw_hashmap_clear(rw_hashmap_t *map);

/* ============================================
 * Iterator Interface
 * ============================================ */

/**
 * @brief Hash map iterator for traversing entries.
 *
 * @code
 * rw_hashmap_iter_t iter;
 * rw_hashmap_iter_init(&iter, map);
 * while (rw_hashmap_iter_next(&iter)) {
 *     const char *key = rw_hashmap_iter_key(&iter);
 *     int *value = rw_hashmap_iter_value(&iter);
 *     printf("%s = %d\n", key, *value);
 * }
 * @endcode
 */
typedef struct {
    rw_hashmap_t *map; /**< Map being iterated */
    size_t index;      /**< Current bucket index */
    void *current;     /**< Current entry (internal) */
} rw_hashmap_iter_t;

/**
 * @brief Initializes an iterator for a hash map.
 * @param iter Iterator to initialize
 * @param map Map to iterate over
 */
void rw_hashmap_iter_init(rw_hashmap_iter_t *iter, rw_hashmap_t *map);

/**
 * @brief Advances the iterator to the next entry.
 * @param iter Iterator to advance
 * @return Non-zero if there is a next entry, zero if iteration complete
 */
int rw_hashmap_iter_next(rw_hashmap_iter_t *iter);

/**
 * @brief Returns the current key.
 * @param iter Iterator positioned at an entry
 * @return Pointer to the key
 */
const void *rw_hashmap_iter_key(const rw_hashmap_iter_t *iter);

/**
 * @brief Returns the current value.
 * @param iter Iterator positioned at an entry
 * @return Pointer to the value
 */
void *rw_hashmap_iter_value(const rw_hashmap_iter_t *iter);

/* ============================================
 * Logging
 * ============================================ */

/// Log severity levels.
typedef enum {
    RW_LOG_TRACE = 0, /**< Detailed trace information */
    RW_LOG_DEBUG = 1, /**< Debug information */
    RW_LOG_INFO = 2,  /**< General information */
    RW_LOG_WARN = 3,  /**< Warning messages */
    RW_LOG_ERROR = 4, /**< Error messages */
    RW_LOG_FATAL = 5  /**< Fatal errors */
} rw_log_level_t;

/**
 * @brief Log callback function type.
 * @param level Severity level
 * @param file Source file name
 * @param line Source line number
 * @param message Log message
 * @param user_data User-provided context
 */
typedef void (*rw_log_fn)(rw_log_level_t level, const char *file, int line, const char *message, void *user_data);

/**
 * @brief Sets the global log callback.
 * @param fn Callback function (NULL to disable logging)
 * @param user_data Context passed to callback
 */
void rw_log_set_callback(rw_log_fn fn, void *user_data);

/**
 * @brief Sets the minimum log level.
 * @param level Minimum level to log (messages below this are ignored)
 */
void rw_log_set_level(rw_log_level_t level);

/* ============================================
 * Utility Functions
 * ============================================ */

/**
 * @brief Returns the library version string.
 * @return Version string in "major.minor.patch" format
 */
const char *rw_version(void);

/**
 * @brief Returns the library version as a packed integer.
 * @return Version as (major << 16) | (minor << 8) | patch
 */
uint32_t rw_version_number(void);

/**
 * @brief Initializes the library.
 *
 * Must be called before using any other functions.
 * Safe to call multiple times.
 *
 * @return RW_OK on success, error code on failure
 */
rw_result_t rw_init(void);

/**
 * @brief Cleans up library resources.
 *
 * Should be called when done using the library.
 * After this call, rw_init() must be called again before use.
 */
void rw_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* REAL_WORLD_H */
