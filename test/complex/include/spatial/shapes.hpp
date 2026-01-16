/**
 * @file shapes.hpp
 * @brief 2D shape classes for geometric primitives
 * @author Stig Test Suite
 * @version 1.0.0
 * 
 * Provides abstract Shape base class and concrete implementations
 * for common 2D shapes: Circle, Rectangle, Triangle, and Polygon.
 */

#pragma once

#include "geometry.hpp"
#include <vector>
#include <memory>
#include <algorithm>
#include <numeric>

namespace spatial {

//=============================================================================
// Forward Declarations
//=============================================================================

template<typename T> class Shape;
template<typename T> class Circle;
template<typename T> class Rectangle;
template<typename T> class Triangle;
template<typename T> class Polygon;

//=============================================================================
// Axis-Aligned Bounding Box
//=============================================================================

/**
 * @brief An axis-aligned bounding box (AABB)
 * @tparam T The scalar type
 * 
 * Represents a rectangular region aligned with the coordinate axes.
 * Used for fast overlap tests and spatial queries.
 * 
 * @code
 * AABB<f64> box{{0, 0}, {10, 10}};
 * bool inside = box.contains(Point2d{5, 5});  // true
 * @endcode
 * 
 * @see Shape::bounding_box
 */
template<typename T>
struct AABB {
    Point2<T> min;  ///< Minimum corner (bottom-left)
    Point2<T> max;  ///< Maximum corner (top-right)
    
    /// @brief Default constructor, creates an invalid (inverted) box
    constexpr AABB() 
        : min{std::numeric_limits<T>::max(), std::numeric_limits<T>::max()}
        , max{std::numeric_limits<T>::lowest(), std::numeric_limits<T>::lowest()} {}
    
    /**
     * @brief Constructs an AABB from min and max corners
     * @param min The minimum corner
     * @param max The maximum corner
     */
    constexpr AABB(Point2<T> min, Point2<T> max) : min(min), max(max) {}
    
    /// @brief Gets the width of the box
    constexpr T width() const { return max.x() - min.x(); }
    
    /// @brief Gets the height of the box
    constexpr T height() const { return max.y() - min.y(); }
    
    /// @brief Gets the center point of the box
    constexpr Point2<T> center() const {
        return Point2<T>{(min.x() + max.x()) / T{2}, (min.y() + max.y()) / T{2}};
    }
    
    /// @brief Gets the area of the box
    constexpr T area() const { return width() * height(); }
    
    /**
     * @brief Checks if a point is inside the box
     * @param p The point to test
     * @return true if the point is inside or on the boundary
     */
    constexpr bool contains(const Point2<T>& p) const {
        return p.x() >= min.x() && p.x() <= max.x() &&
               p.y() >= min.y() && p.y() <= max.y();
    }
    
    /**
     * @brief Checks if this box overlaps with another
     * @param other The other box
     * @return true if the boxes overlap
     */
    constexpr bool overlaps(const AABB& other) const {
        return min.x() <= other.max.x() && max.x() >= other.min.x() &&
               min.y() <= other.max.y() && max.y() >= other.min.y();
    }
    
    /**
     * @brief Expands the box to include a point
     * @param p The point to include
     * @return Reference to this box
     */
    AABB& expand(const Point2<T>& p) {
        min = Point2<T>{std::min(min.x(), p.x()), std::min(min.y(), p.y())};
        max = Point2<T>{std::max(max.x(), p.x()), std::max(max.y(), p.y())};
        return *this;
    }
    
    /**
     * @brief Merges this box with another
     * @param other The other box
     * @return A new box containing both
     */
    AABB merged(const AABB& other) const {
        return AABB{
            Point2<T>{std::min(min.x(), other.min.x()), std::min(min.y(), other.min.y())},
            Point2<T>{std::max(max.x(), other.max.x()), std::max(max.y(), other.max.y())}
        };
    }
};

//=============================================================================
// Abstract Shape Base Class
//=============================================================================

/**
 * @brief Abstract base class for 2D shapes
 * @tparam T The scalar type
 * 
 * Defines the interface for all 2D shapes. Concrete shapes must implement
 * area(), perimeter(), contains(), and bounding_box().
 * 
 * @see Circle, Rectangle, Triangle, Polygon
 */
template<typename T>
class Shape {
public:
    /// @brief Virtual destructor for proper cleanup
    virtual ~Shape() = default;
    
    /**
     * @brief Computes the area of the shape
     * @return The area
     */
    virtual T area() const = 0;
    
    /**
     * @brief Computes the perimeter of the shape
     * @return The perimeter
     */
    virtual T perimeter() const = 0;
    
    /**
     * @brief Checks if a point is inside the shape
     * @param p The point to test
     * @return true if the point is inside the shape
     */
    virtual bool contains(const Point2<T>& p) const = 0;
    
    /**
     * @brief Gets the axis-aligned bounding box
     * @return The bounding box
     */
    virtual AABB<T> bounding_box() const = 0;
    
    /**
     * @brief Gets the centroid (center of mass) of the shape
     * @return The centroid point
     */
    virtual Point2<T> centroid() const = 0;
    
    /**
     * @brief Creates a transformed copy of this shape
     * @param transform The transformation to apply
     * @return A new transformed shape
     */
    virtual std::unique_ptr<Shape> transformed(const Transform2<T>& transform) const = 0;
};

//=============================================================================
// Circle
//=============================================================================

/**
 * @brief A circle defined by center and radius
 * @tparam T The scalar type
 * 
 * @code
 * Circle<f64> c{Point2d{0, 0}, 5.0};
 * f64 area = c.area();  // π * 25
 * bool inside = c.contains(Point2d{3, 4});  // true (distance = 5)
 * @endcode
 * 
 * @see Shape, AABB
 */
template<typename T>
class Circle : public Shape<T> {
public:
    /**
     * @brief Constructs a circle from center and radius
     * @param center The center point
     * @param radius The radius (must be positive)
     */
    Circle(Point2<T> center, T radius) : center_(center), radius_(radius) {}
    
    /// @brief Gets the center point
    const Point2<T>& center() const { return center_; }
    
    /// @brief Gets the radius
    T radius() const { return radius_; }
    
    /// @brief Sets the center point
    void set_center(const Point2<T>& center) { center_ = center; }
    
    /// @brief Sets the radius
    void set_radius(T radius) { radius_ = radius; }
    
    /**
     * @brief Computes the area (π * r²)
     * @return The area
     */
    T area() const override {
        return static_cast<T>(constants::PI) * radius_ * radius_;
    }
    
    /**
     * @brief Computes the circumference (2 * π * r)
     * @return The perimeter
     */
    T perimeter() const override {
        return static_cast<T>(constants::TWO_PI) * radius_;
    }
    
    /**
     * @brief Checks if a point is inside the circle
     * @param p The point to test
     * @return true if distance from center <= radius
     */
    bool contains(const Point2<T>& p) const override {
        return center_.distance_squared(p) <= radius_ * radius_;
    }
    
    /**
     * @brief Gets the bounding box
     * @return An AABB containing the circle
     */
    AABB<T> bounding_box() const override {
        return AABB<T>{
            Point2<T>{center_.x() - radius_, center_.y() - radius_},
            Point2<T>{center_.x() + radius_, center_.y() + radius_}
        };
    }
    
    /**
     * @brief Gets the centroid (same as center for a circle)
     * @return The center point
     */
    Point2<T> centroid() const override { return center_; }
    
    /**
     * @brief Creates a transformed copy
     * @param transform The transformation
     * @return A new circle with transformed center
     * @note Rotation doesn't affect circles, only translation
     */
    std::unique_ptr<Shape<T>> transformed(const Transform2<T>& transform) const override {
        return std::make_unique<Circle>(transform.apply(center_), radius_);
    }
    
    /**
     * @brief Checks if this circle intersects another
     * @param other The other circle
     * @return true if the circles overlap
     */
    bool intersects(const Circle& other) const {
        T dist_sq = center_.distance_squared(other.center_);
        T sum_radii = radius_ + other.radius_;
        return dist_sq <= sum_radii * sum_radii;
    }

private:
    Point2<T> center_;
    T radius_;
};

//=============================================================================
// Rectangle
//=============================================================================

/**
 * @brief An axis-aligned rectangle
 * @tparam T The scalar type
 * 
 * Defined by a center point, width, and height.
 * 
 * @code
 * Rectangle<f64> rect{Point2d{5, 5}, 10, 6};
 * f64 area = rect.area();  // 60
 * @endcode
 * 
 * @see Shape, AABB
 */
template<typename T>
class Rectangle : public Shape<T> {
public:
    /**
     * @brief Constructs a rectangle from center, width, and height
     * @param center The center point
     * @param width The width (x extent)
     * @param height The height (y extent)
     */
    Rectangle(Point2<T> center, T width, T height)
        : center_(center), width_(width), height_(height) {}
    
    /**
     * @brief Constructs a rectangle from an AABB
     * @param box The bounding box
     */
    explicit Rectangle(const AABB<T>& box)
        : center_(box.center())
        , width_(box.width())
        , height_(box.height()) {}
    
    /// @brief Gets the center point
    const Point2<T>& center() const { return center_; }
    
    /// @brief Gets the width
    T width() const { return width_; }
    
    /// @brief Gets the height
    T height() const { return height_; }
    
    /**
     * @brief Computes the area (width * height)
     * @return The area
     */
    T area() const override {
        return width_ * height_;
    }
    
    /**
     * @brief Computes the perimeter (2 * (width + height))
     * @return The perimeter
     */
    T perimeter() const override {
        return T{2} * (width_ + height_);
    }
    
    /**
     * @brief Checks if a point is inside the rectangle
     * @param p The point to test
     * @return true if inside
     */
    bool contains(const Point2<T>& p) const override {
        T half_w = width_ / T{2};
        T half_h = height_ / T{2};
        return std::abs(p.x() - center_.x()) <= half_w &&
               std::abs(p.y() - center_.y()) <= half_h;
    }
    
    /**
     * @brief Gets the bounding box (same as the rectangle for axis-aligned)
     * @return The bounding box
     */
    AABB<T> bounding_box() const override {
        T half_w = width_ / T{2};
        T half_h = height_ / T{2};
        return AABB<T>{
            Point2<T>{center_.x() - half_w, center_.y() - half_h},
            Point2<T>{center_.x() + half_w, center_.y() + half_h}
        };
    }
    
    /**
     * @brief Gets the centroid
     * @return The center point
     */
    Point2<T> centroid() const override { return center_; }
    
    /**
     * @brief Creates a transformed copy
     * @param transform The transformation
     * @return A new rectangle (note: rotation makes it non-axis-aligned)
     * @warning After rotation, this is still axis-aligned, which may not be desired
     */
    std::unique_ptr<Shape<T>> transformed(const Transform2<T>& transform) const override {
        // Note: This doesn't handle rotation properly for rectangles
        // A proper implementation would convert to a polygon
        return std::make_unique<Rectangle>(transform.apply(center_), width_, height_);
    }
    
    /**
     * @brief Gets the four corner points
     * @return Array of corner points (counter-clockwise from bottom-left)
     */
    std::array<Point2<T>, 4> corners() const {
        T half_w = width_ / T{2};
        T half_h = height_ / T{2};
        return {{
            Point2<T>{center_.x() - half_w, center_.y() - half_h},
            Point2<T>{center_.x() + half_w, center_.y() - half_h},
            Point2<T>{center_.x() + half_w, center_.y() + half_h},
            Point2<T>{center_.x() - half_w, center_.y() + half_h}
        }};
    }

private:
    Point2<T> center_;
    T width_;
    T height_;
};

//=============================================================================
// Triangle
//=============================================================================

/**
 * @brief A triangle defined by three vertices
 * @tparam T The scalar type
 * 
 * @code
 * Triangle<f64> tri{
 *     Point2d{0, 0},
 *     Point2d{4, 0},
 *     Point2d{2, 3}
 * };
 * f64 area = tri.area();  // 6.0
 * @endcode
 * 
 * @see Shape, Polygon
 */
template<typename T>
class Triangle : public Shape<T> {
public:
    /**
     * @brief Constructs a triangle from three vertices
     * @param a First vertex
     * @param b Second vertex
     * @param c Third vertex
     */
    Triangle(Point2<T> a, Point2<T> b, Point2<T> c)
        : vertices_{{a, b, c}} {}
    
    /// @brief Gets vertex A
    const Point2<T>& a() const { return vertices_[0]; }
    /// @brief Gets vertex B
    const Point2<T>& b() const { return vertices_[1]; }
    /// @brief Gets vertex C
    const Point2<T>& c() const { return vertices_[2]; }
    
    /// @brief Gets a vertex by index (0, 1, or 2)
    const Point2<T>& vertex(usize i) const { return vertices_[i % 3]; }
    
    /**
     * @brief Computes the area using the cross product formula
     * @return The area (always positive)
     */
    T area() const override {
        Vec2<T> ab = vertices_[1] - vertices_[0];
        Vec2<T> ac = vertices_[2] - vertices_[0];
        return std::abs(ab.cross(ac)) / T{2};
    }
    
    /**
     * @brief Computes the perimeter (sum of edge lengths)
     * @return The perimeter
     */
    T perimeter() const override {
        return vertices_[0].distance_to(vertices_[1]) +
               vertices_[1].distance_to(vertices_[2]) +
               vertices_[2].distance_to(vertices_[0]);
    }
    
    /**
     * @brief Checks if a point is inside using barycentric coordinates
     * @param p The point to test
     * @return true if inside
     */
    bool contains(const Point2<T>& p) const override {
        // Compute barycentric coordinates
        Vec2<T> v0 = vertices_[2] - vertices_[0];
        Vec2<T> v1 = vertices_[1] - vertices_[0];
        Vec2<T> v2 = p - vertices_[0];
        
        T dot00 = v0.dot(v0);
        T dot01 = v0.dot(v1);
        T dot02 = v0.dot(v2);
        T dot11 = v1.dot(v1);
        T dot12 = v1.dot(v2);
        
        T inv_denom = T{1} / (dot00 * dot11 - dot01 * dot01);
        T u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
        T v = (dot00 * dot12 - dot01 * dot02) * inv_denom;
        
        return (u >= T{0}) && (v >= T{0}) && (u + v <= T{1});
    }
    
    /**
     * @brief Gets the bounding box
     * @return The smallest AABB containing the triangle
     */
    AABB<T> bounding_box() const override {
        AABB<T> box;
        for (const auto& v : vertices_) {
            box.expand(v);
        }
        return box;
    }
    
    /**
     * @brief Gets the centroid (average of vertices)
     * @return The centroid point
     */
    Point2<T> centroid() const override {
        return Point2<T>{
            (vertices_[0].x() + vertices_[1].x() + vertices_[2].x()) / T{3},
            (vertices_[0].y() + vertices_[1].y() + vertices_[2].y()) / T{3}
        };
    }
    
    /**
     * @brief Creates a transformed copy
     * @param transform The transformation
     * @return A new triangle with transformed vertices
     */
    std::unique_ptr<Shape<T>> transformed(const Transform2<T>& transform) const override {
        return std::make_unique<Triangle>(
            transform.apply(vertices_[0]),
            transform.apply(vertices_[1]),
            transform.apply(vertices_[2])
        );
    }
    
    /**
     * @brief Checks if the triangle is degenerate (zero area)
     * @param epsilon The tolerance
     * @return true if the area is less than epsilon
     */
    bool is_degenerate(T epsilon = static_cast<T>(constants::EPSILON)) const {
        return area() < epsilon;
    }

private:
    std::array<Point2<T>, 3> vertices_;
};

//=============================================================================
// Polygon
//=============================================================================

/**
 * @brief A general polygon defined by a list of vertices
 * @tparam T The scalar type
 * 
 * Vertices should be in counter-clockwise order for a positive area.
 * The polygon is assumed to be simple (non-self-intersecting).
 * 
 * @code
 * Polygon<f64> pentagon{{
 *     {0, 0}, {2, 0}, {3, 1}, {1, 2}, {-1, 1}
 * }};
 * @endcode
 * 
 * @see Shape, Triangle
 */
template<typename T>
class Polygon : public Shape<T> {
public:
    /**
     * @brief Constructs a polygon from a list of vertices
     * @param vertices The vertices in order (counter-clockwise for positive area)
     */
    explicit Polygon(std::vector<Point2<T>> vertices)
        : vertices_(std::move(vertices)) {}
    
    /**
     * @brief Constructs a polygon from an initializer list
     * @param vertices The vertices
     */
    Polygon(std::initializer_list<Point2<T>> vertices)
        : vertices_(vertices) {}
    
    /// @brief Gets the number of vertices
    usize vertex_count() const { return vertices_.size(); }
    
    /// @brief Gets a vertex by index
    const Point2<T>& vertex(usize i) const { return vertices_[i % vertices_.size()]; }
    
    /// @brief Gets all vertices
    const std::vector<Point2<T>>& vertices() const { return vertices_; }
    
    /**
     * @brief Computes the signed area using the shoelace formula
     * @return The signed area (positive if CCW, negative if CW)
     */
    T signed_area() const {
        T sum = T{0};
        usize n = vertices_.size();
        for (usize i = 0; i < n; ++i) {
            const auto& p1 = vertices_[i];
            const auto& p2 = vertices_[(i + 1) % n];
            sum += (p1.x() * p2.y() - p2.x() * p1.y());
        }
        return sum / T{2};
    }
    
    /**
     * @brief Computes the area (absolute value of signed area)
     * @return The area
     */
    T area() const override {
        return std::abs(signed_area());
    }
    
    /**
     * @brief Computes the perimeter (sum of edge lengths)
     * @return The perimeter
     */
    T perimeter() const override {
        T sum = T{0};
        usize n = vertices_.size();
        for (usize i = 0; i < n; ++i) {
            sum += vertices_[i].distance_to(vertices_[(i + 1) % n]);
        }
        return sum;
    }
    
    /**
     * @brief Checks if a point is inside using ray casting
     * @param p The point to test
     * @return true if inside
     */
    bool contains(const Point2<T>& p) const override {
        // Ray casting algorithm
        bool inside = false;
        usize n = vertices_.size();
        for (usize i = 0, j = n - 1; i < n; j = i++) {
            const auto& vi = vertices_[i];
            const auto& vj = vertices_[j];
            
            if (((vi.y() > p.y()) != (vj.y() > p.y())) &&
                (p.x() < (vj.x() - vi.x()) * (p.y() - vi.y()) / (vj.y() - vi.y()) + vi.x())) {
                inside = !inside;
            }
        }
        return inside;
    }
    
    /**
     * @brief Gets the bounding box
     * @return The smallest AABB containing the polygon
     */
    AABB<T> bounding_box() const override {
        AABB<T> box;
        for (const auto& v : vertices_) {
            box.expand(v);
        }
        return box;
    }
    
    /**
     * @brief Gets the centroid
     * @return The centroid point
     */
    Point2<T> centroid() const override {
        T cx = T{0}, cy = T{0};
        T a = signed_area();
        usize n = vertices_.size();
        
        for (usize i = 0; i < n; ++i) {
            const auto& p1 = vertices_[i];
            const auto& p2 = vertices_[(i + 1) % n];
            T cross = p1.x() * p2.y() - p2.x() * p1.y();
            cx += (p1.x() + p2.x()) * cross;
            cy += (p1.y() + p2.y()) * cross;
        }
        
        T factor = T{1} / (T{6} * a);
        return Point2<T>{cx * factor, cy * factor};
    }
    
    /**
     * @brief Creates a transformed copy
     * @param transform The transformation
     * @return A new polygon with transformed vertices
     */
    std::unique_ptr<Shape<T>> transformed(const Transform2<T>& transform) const override {
        std::vector<Point2<T>> new_verts;
        new_verts.reserve(vertices_.size());
        for (const auto& v : vertices_) {
            new_verts.push_back(transform.apply(v));
        }
        return std::make_unique<Polygon>(std::move(new_verts));
    }
    
    /**
     * @brief Checks if the polygon is convex
     * @return true if all interior angles are less than 180°
     */
    bool is_convex() const {
        usize n = vertices_.size();
        if (n < 3) return false;
        
        bool sign = false;
        for (usize i = 0; i < n; ++i) {
            Vec2<T> d1 = vertices_[(i + 1) % n] - vertices_[i];
            Vec2<T> d2 = vertices_[(i + 2) % n] - vertices_[(i + 1) % n];
            T cross = d1.cross(d2);
            
            if (i == 0) {
                sign = cross > T{0};
            } else if ((cross > T{0}) != sign) {
                return false;
            }
        }
        return true;
    }

private:
    std::vector<Point2<T>> vertices_;
};

//=============================================================================
// Common Type Aliases
//=============================================================================

/// @brief AABB with double precision
using AABBd = AABB<f64>;

/// @brief Circle with double precision
using Circled = Circle<f64>;

/// @brief Rectangle with double precision
using Rectangled = Rectangle<f64>;

/// @brief Triangle with double precision
using Triangled = Triangle<f64>;

/// @brief Polygon with double precision
using Polygond = Polygon<f64>;

} // namespace spatial
