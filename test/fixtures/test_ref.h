/**
 * @file test_ref.h
 * @brief Test file for @ref tag functionality
 */

/**
 * @brief A simple point structure for 2D coordinates
 */
struct Point {
    int x;  /**< X coordinate */
    int y;  /**< Y coordinate */
};

/**
 * @brief A 3D vector structure
 */
struct Vector3D {
    float x;  /**< X component */
    float y;  /**< Y component */
    float z;  /**< Z component */
};

/**
 * @brief See @ref Point for a simple 2D point structure
 */
void describe_point();

/**
 * @brief Uses @ref Point "the Point struct" for input coordinates
 * @param p A @ref Point to process
 * @return See @ref Vector3D for the return type
 */
struct Vector3D process_point(struct Point p);

/**
 * @brief Refer to @ref overview_section "the overview" for more details
 * 
 * Also see @ref NonExistent for something that doesn't exist.
 */
void another_function();

/**
 * @brief Both \ref Point and @ref Vector3D are used here
 * 
 * This function demonstrates cross-references in documentation.
 * See \ref Point "Point struct" and @ref Vector3D "Vector class".
 */
void mixed_refs();

/**
 * @brief Converts from @ref Point to @ref Vector3D
 * @param p Input @ref Point
 * @return Output @ref Vector3D with z=0
 */
struct Vector3D point_to_vector(struct Point p);
