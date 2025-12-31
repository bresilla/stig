/**
 * @file algorithms.hpp
 * @brief Spatial algorithms and utility functions
 * @author Stinger Test Suite
 * @version 1.0.0
 * 
 * Provides free functions for common spatial operations:
 * distance calculations, intersection tests, containment checks,
 * and geometric utilities.
 */

#pragma once

#include "shapes.hpp"
#include <optional>
#include <cmath>

namespace spatial {

//=============================================================================
// Distance Functions
//=============================================================================

/**
 * @brief Computes the Euclidean distance between two 2D points
 * @tparam T The scalar type
 * @param a First point
 * @param b Second point
 * @return The distance
 * 
 * @see Point2::distance_to
 */
template<typename T>
T distance(const Point2<T>& a, const Point2<T>& b) {
    return a.distance_to(b);
}

/**
 * @brief Computes the Euclidean distance between two 3D points
 * @tparam T The scalar type
 * @param a First point
 * @param b Second point
 * @return The distance
 * 
 * @see Point3::distance_to
 */
template<typename T>
T distance(const Point3<T>& a, const Point3<T>& b) {
    return a.distance_to(b);
}

/**
 * @brief Computes the squared distance between two 2D points
 * @tparam T The scalar type
 * @param a First point
 * @param b Second point
 * @return The squared distance
 * 
 * More efficient than distance() when only comparing distances.
 */
template<typename T>
constexpr T distance_squared(const Point2<T>& a, const Point2<T>& b) {
    return a.distance_squared(b);
}

/**
 * @brief Computes the minimum distance from a point to a line segment
 * @tparam T The scalar type
 * @param point The query point
 * @param seg_start Start of the line segment
 * @param seg_end End of the line segment
 * @return The minimum distance
 * 
 * @code
 * Point2d p{5, 5};
 * Point2d a{0, 0}, b{10, 0};
 * f64 dist = distance_to_segment(p, a, b);  // 5.0
 * @endcode
 */
template<typename T>
T distance_to_segment(const Point2<T>& point, const Point2<T>& seg_start, const Point2<T>& seg_end) {
    Vec2<T> v = seg_end - seg_start;
    Vec2<T> w = point - seg_start;
    
    T c1 = w.dot(v);
    if (c1 <= T{0}) {
        return point.distance_to(seg_start);
    }
    
    T c2 = v.dot(v);
    if (c2 <= c1) {
        return point.distance_to(seg_end);
    }
    
    T t = c1 / c2;
    Point2<T> projection{seg_start.x() + t * v.x(), seg_start.y() + t * v.y()};
    return point.distance_to(projection);
}

/**
 * @brief Computes the minimum distance from a point to a circle's boundary
 * @tparam T The scalar type
 * @param point The query point
 * @param circle The circle
 * @return The distance (negative if inside)
 */
template<typename T>
T distance_to_circle(const Point2<T>& point, const Circle<T>& circle) {
    return point.distance_to(circle.center()) - circle.radius();
}

//=============================================================================
// Intersection Tests
//=============================================================================

/**
 * @brief Result of a line-line intersection test
 * @tparam T The scalar type
 */
template<typename T>
struct LineIntersection {
    bool intersects;      ///< Whether the lines intersect
    Point2<T> point;      ///< The intersection point (if intersects)
    T t;                  ///< Parameter along first line [0,1] if segment
    T u;                  ///< Parameter along second line [0,1] if segment
};

/**
 * @brief Computes the intersection of two line segments
 * @tparam T The scalar type
 * @param a1 Start of first segment
 * @param a2 End of first segment
 * @param b1 Start of second segment
 * @param b2 End of second segment
 * @return Intersection result
 * 
 * @code
 * auto result = segment_intersection(
 *     Point2d{0, 0}, Point2d{10, 10},
 *     Point2d{0, 10}, Point2d{10, 0}
 * );
 * if (result.intersects) {
 *     // Intersection at (5, 5)
 * }
 * @endcode
 * 
 * @see LineIntersection
 */
template<typename T>
LineIntersection<T> segment_intersection(
    const Point2<T>& a1, const Point2<T>& a2,
    const Point2<T>& b1, const Point2<T>& b2
) {
    Vec2<T> r = a2 - a1;
    Vec2<T> s = b2 - b1;
    Vec2<T> qp = b1 - a1;
    
    T rxs = r.cross(s);
    T qpxr = qp.cross(r);
    
    // Parallel lines
    if (std::abs(rxs) < static_cast<T>(constants::EPSILON)) {
        return {false, Point2<T>{}, T{0}, T{0}};
    }
    
    T t = qp.cross(s) / rxs;
    T u = qpxr / rxs;
    
    // Check if intersection is within both segments
    if (t >= T{0} && t <= T{1} && u >= T{0} && u <= T{1}) {
        Point2<T> intersection{a1.x() + t * r.x(), a1.y() + t * r.y()};
        return {true, intersection, t, u};
    }
    
    return {false, Point2<T>{}, t, u};
}

/**
 * @brief Checks if two circles intersect
 * @tparam T The scalar type
 * @param c1 First circle
 * @param c2 Second circle
 * @return true if the circles overlap
 * 
 * @see Circle::intersects
 */
template<typename T>
bool circles_intersect(const Circle<T>& c1, const Circle<T>& c2) {
    return c1.intersects(c2);
}

/**
 * @brief Checks if two AABBs overlap
 * @tparam T The scalar type
 * @param a First bounding box
 * @param b Second bounding box
 * @return true if the boxes overlap
 * 
 * @see AABB::overlaps
 */
template<typename T>
bool aabb_overlap(const AABB<T>& a, const AABB<T>& b) {
    return a.overlaps(b);
}

/**
 * @brief Checks if a circle and AABB overlap
 * @tparam T The scalar type
 * @param circle The circle
 * @param box The bounding box
 * @return true if they overlap
 */
template<typename T>
bool circle_aabb_overlap(const Circle<T>& circle, const AABB<T>& box) {
    // Find closest point on AABB to circle center
    T closest_x = std::clamp(circle.center().x(), box.min.x(), box.max.x());
    T closest_y = std::clamp(circle.center().y(), box.min.y(), box.max.y());
    
    Point2<T> closest{closest_x, closest_y};
    return circle.center().distance_squared(closest) <= circle.radius() * circle.radius();
}

//=============================================================================
// Containment Tests
//=============================================================================

/**
 * @brief Checks if a point is inside a convex polygon using cross products
 * @tparam T The scalar type
 * @param point The query point
 * @param polygon The convex polygon
 * @return true if the point is inside
 * 
 * @note This is faster than Polygon::contains() for convex polygons
 * @warning Only works correctly for convex polygons
 */
template<typename T>
bool point_in_convex_polygon(const Point2<T>& point, const Polygon<T>& polygon) {
    const auto& verts = polygon.vertices();
    usize n = verts.size();
    if (n < 3) return false;
    
    bool sign = false;
    for (usize i = 0; i < n; ++i) {
        Vec2<T> edge = verts[(i + 1) % n] - verts[i];
        Vec2<T> to_point = point - verts[i];
        T cross = edge.cross(to_point);
        
        if (i == 0) {
            sign = cross > T{0};
        } else if ((cross > T{0}) != sign) {
            return false;
        }
    }
    return true;
}

/**
 * @brief Checks if one AABB completely contains another
 * @tparam T The scalar type
 * @param outer The potentially containing box
 * @param inner The potentially contained box
 * @return true if outer contains inner
 */
template<typename T>
bool aabb_contains(const AABB<T>& outer, const AABB<T>& inner) {
    return outer.min.x() <= inner.min.x() && outer.max.x() >= inner.max.x() &&
           outer.min.y() <= inner.min.y() && outer.max.y() >= inner.max.y();
}

//=============================================================================
// Geometric Utilities
//=============================================================================

/**
 * @brief Computes the signed area of a triangle
 * @tparam T The scalar type
 * @param a First vertex
 * @param b Second vertex
 * @param c Third vertex
 * @return Signed area (positive if CCW, negative if CW)
 * 
 * Useful for determining point orientation and winding order.
 */
template<typename T>
constexpr T signed_triangle_area(const Point2<T>& a, const Point2<T>& b, const Point2<T>& c) {
    return ((b.x() - a.x()) * (c.y() - a.y()) - (c.x() - a.x()) * (b.y() - a.y())) / T{2};
}

/**
 * @brief Determines the orientation of three points
 * @tparam T The scalar type
 * @param a First point
 * @param b Second point
 * @param c Third point
 * @return 1 if CCW, -1 if CW, 0 if collinear
 */
template<typename T>
int orientation(const Point2<T>& a, const Point2<T>& b, const Point2<T>& c) {
    T area = signed_triangle_area(a, b, c);
    if (area > static_cast<T>(constants::EPSILON)) return 1;   // CCW
    if (area < -static_cast<T>(constants::EPSILON)) return -1; // CW
    return 0; // Collinear
}

/**
 * @brief Computes the convex hull of a set of points
 * @tparam T The scalar type
 * @param points The input points
 * @return A polygon representing the convex hull
 * 
 * Uses the Graham scan algorithm. Returns an empty polygon if
 * fewer than 3 points are provided.
 * 
 * @code
 * std::vector<Point2d> points = {{0,0}, {1,1}, {2,0}, {1,2}, {0.5,0.5}};
 * Polygon<f64> hull = convex_hull(points);
 * // hull contains: {0,0}, {2,0}, {1,2}
 * @endcode
 */
template<typename T>
Polygon<T> convex_hull(std::vector<Point2<T>> points) {
    usize n = points.size();
    if (n < 3) return Polygon<T>{{}};
    
    // Find the bottom-most point (or left-most in case of tie)
    usize min_idx = 0;
    for (usize i = 1; i < n; ++i) {
        if (points[i].y() < points[min_idx].y() ||
            (points[i].y() == points[min_idx].y() && points[i].x() < points[min_idx].x())) {
            min_idx = i;
        }
    }
    std::swap(points[0], points[min_idx]);
    Point2<T> pivot = points[0];
    
    // Sort by polar angle with respect to pivot
    std::sort(points.begin() + 1, points.end(), [&pivot](const Point2<T>& a, const Point2<T>& b) {
        int o = orientation(pivot, a, b);
        if (o == 0) {
            // Collinear - sort by distance
            return pivot.distance_squared(a) < pivot.distance_squared(b);
        }
        return o > 0;
    });
    
    // Build hull using stack
    std::vector<Point2<T>> hull;
    for (const auto& p : points) {
        while (hull.size() > 1 && orientation(hull[hull.size()-2], hull[hull.size()-1], p) <= 0) {
            hull.pop_back();
        }
        hull.push_back(p);
    }
    
    return Polygon<T>{std::move(hull)};
}

/**
 * @brief Computes the centroid of a set of points
 * @tparam T The scalar type
 * @param points The input points
 * @return The centroid (average position)
 * 
 * @note Returns origin if points is empty
 */
template<typename T>
Point2<T> centroid(const std::vector<Point2<T>>& points) {
    if (points.empty()) return Point2<T>::origin();
    
    T sum_x = T{0}, sum_y = T{0};
    for (const auto& p : points) {
        sum_x += p.x();
        sum_y += p.y();
    }
    T n = static_cast<T>(points.size());
    return Point2<T>{sum_x / n, sum_y / n};
}

/**
 * @brief Computes the bounding box of a set of points
 * @tparam T The scalar type
 * @param points The input points
 * @return The smallest AABB containing all points
 */
template<typename T>
AABB<T> bounding_box(const std::vector<Point2<T>>& points) {
    AABB<T> box;
    for (const auto& p : points) {
        box.expand(p);
    }
    return box;
}

/**
 * @brief Computes the bounding box of multiple shapes
 * @tparam T The scalar type
 * @param shapes The input shapes
 * @return The smallest AABB containing all shapes
 */
template<typename T>
AABB<T> combined_bounding_box(const std::vector<std::unique_ptr<Shape<T>>>& shapes) {
    AABB<T> box;
    for (const auto& shape : shapes) {
        box = box.merged(shape->bounding_box());
    }
    return box;
}

//=============================================================================
// Angle Utilities
//=============================================================================

/**
 * @brief Normalizes an angle to the range [-π, π]
 * @tparam T The scalar type
 * @param radians The angle in radians
 * @return The normalized angle
 */
template<typename T>
T normalize_angle(T radians) {
    while (radians > static_cast<T>(constants::PI)) {
        radians -= static_cast<T>(constants::TWO_PI);
    }
    while (radians < -static_cast<T>(constants::PI)) {
        radians += static_cast<T>(constants::TWO_PI);
    }
    return radians;
}

/**
 * @brief Computes the angle between two vectors
 * @tparam T The scalar type
 * @param a First vector
 * @param b Second vector
 * @return The angle in radians [0, π]
 */
template<typename T>
T angle_between(const Vec2<T>& a, const Vec2<T>& b) {
    T dot = a.dot(b);
    T mags = a.magnitude() * b.magnitude();
    if (mags < static_cast<T>(constants::EPSILON)) return T{0};
    return std::acos(std::clamp(dot / mags, T{-1}, T{1}));
}

/**
 * @brief Computes the signed angle from vector a to vector b
 * @tparam T The scalar type
 * @param a First vector
 * @param b Second vector
 * @return The signed angle in radians [-π, π]
 * 
 * Positive angle means counter-clockwise rotation from a to b.
 */
template<typename T>
T signed_angle_between(const Vec2<T>& a, const Vec2<T>& b) {
    return std::atan2(a.cross(b), a.dot(b));
}

/**
 * @brief Converts degrees to radians
 * @tparam T The scalar type
 * @param degrees The angle in degrees
 * @return The angle in radians
 */
template<typename T>
constexpr T deg_to_rad(T degrees) {
    return degrees * static_cast<T>(constants::DEG_TO_RAD);
}

/**
 * @brief Converts radians to degrees
 * @tparam T The scalar type
 * @param radians The angle in radians
 * @return The angle in degrees
 */
template<typename T>
constexpr T rad_to_deg(T radians) {
    return radians * static_cast<T>(constants::RAD_TO_DEG);
}

//=============================================================================
// Interpolation
//=============================================================================

/**
 * @brief Linearly interpolates between two values
 * @tparam T The value type
 * @param a Start value
 * @param b End value
 * @param t Interpolation factor [0, 1]
 * @return The interpolated value
 */
template<typename T>
constexpr T lerp(T a, T b, T t) {
    return a + (b - a) * t;
}

/**
 * @brief Computes the inverse lerp (finds t given a, b, and value)
 * @tparam T The value type
 * @param a Start value
 * @param b End value
 * @param value The value to find t for
 * @return The interpolation factor
 */
template<typename T>
constexpr T inverse_lerp(T a, T b, T value) {
    return (value - a) / (b - a);
}

/**
 * @brief Remaps a value from one range to another
 * @tparam T The value type
 * @param value The input value
 * @param in_min Input range minimum
 * @param in_max Input range maximum
 * @param out_min Output range minimum
 * @param out_max Output range maximum
 * @return The remapped value
 */
template<typename T>
constexpr T remap(T value, T in_min, T in_max, T out_min, T out_max) {
    return lerp(out_min, out_max, inverse_lerp(in_min, in_max, value));
}

/**
 * @brief Smoothly interpolates between two values using smoothstep
 * @tparam T The value type
 * @param a Start value
 * @param b End value
 * @param t Interpolation factor [0, 1]
 * @return The smoothly interpolated value
 * 
 * Uses the smoothstep function: 3t² - 2t³
 */
template<typename T>
T smoothstep(T a, T b, T t) {
    t = std::clamp(t, T{0}, T{1});
    t = t * t * (T{3} - T{2} * t);
    return lerp(a, b, t);
}

} // namespace spatial
