/**
 * @file geometry.hpp
 * @brief Point and Transform classes for spatial geometry
 * @author Stig Test Suite
 * @version 1.0.0
 * 
 * Provides Point classes (wrappers around vectors with geometric semantics)
 * and Transform classes for 2D/3D transformations.
 */

#pragma once

#include "vector.hpp"
#include <cmath>

namespace spatial {

//=============================================================================
// Forward Declarations
//=============================================================================

template<typename T> class Point2;
template<typename T> class Point3;
template<typename T> class Transform2;
template<typename T> class Transform3;

//=============================================================================
// 2D Point
//=============================================================================

/**
 * @brief A 2D point in Cartesian coordinates
 * @tparam T The scalar type
 * 
 * Represents a position in 2D space. Unlike Vec2, Point2 has
 * geometric semantics - you can compute distances between points,
 * but adding two points doesn't make geometric sense.
 * 
 * @code
 * Point2<f64> p1{0.0, 0.0};
 * Point2<f64> p2{3.0, 4.0};
 * f64 dist = p1.distance_to(p2);  // 5.0
 * @endcode
 * 
 * @see Vec2, Point3
 */
template<typename T>
class Point2 {
public:
    /// @brief Default constructor, initializes to origin (0, 0)
    constexpr Point2() : x_(T{}), y_(T{}) {}
    
    /**
     * @brief Constructs a point from x and y coordinates
     * @param x The x coordinate
     * @param y The y coordinate
     */
    constexpr Point2(T x, T y) : x_(x), y_(y) {}
    
    /**
     * @brief Constructs a point from a vector (position vector)
     * @param v The position vector
     */
    explicit constexpr Point2(const Vec2<T>& v) : x_(v.x()), y_(v.y()) {}
    
    /// @brief Gets the x coordinate
    constexpr T x() const { return x_; }
    /// @brief Gets the y coordinate
    constexpr T y() const { return y_; }
    
    /// @brief Sets the x coordinate
    constexpr void set_x(T x) { x_ = x; }
    /// @brief Sets the y coordinate
    constexpr void set_y(T y) { y_ = y; }
    
    /**
     * @brief Converts to a position vector
     * @return The position vector from origin to this point
     */
    constexpr Vec2<T> to_vec() const { return Vec2<T>{x_, y_}; }
    
    /**
     * @brief Computes the Euclidean distance to another point
     * @param other The other point
     * @return The distance
     */
    T distance_to(const Point2& other) const {
        T dx = x_ - other.x_;
        T dy = y_ - other.y_;
        return std::sqrt(dx * dx + dy * dy);
    }
    
    /**
     * @brief Computes the squared distance to another point
     * @param other The other point
     * @return The squared distance
     * @note More efficient than distance_to() when only comparing distances
     */
    constexpr T distance_squared(const Point2& other) const {
        T dx = x_ - other.x_;
        T dy = y_ - other.y_;
        return dx * dx + dy * dy;
    }
    
    /**
     * @brief Computes the midpoint between this point and another
     * @param other The other point
     * @return The midpoint
     */
    constexpr Point2 midpoint(const Point2& other) const {
        return Point2{(x_ + other.x_) / T{2}, (y_ + other.y_) / T{2}};
    }
    
    /**
     * @brief Linearly interpolates between this point and another
     * @param other The target point
     * @param t The interpolation factor (0 = this, 1 = other)
     * @return The interpolated point
     */
    constexpr Point2 lerp(const Point2& other, T t) const {
        return Point2{
            x_ + (other.x_ - x_) * t,
            y_ + (other.y_ - y_) * t
        };
    }
    
    /// @brief Translates the point by a vector
    constexpr Point2 operator+(const Vec2<T>& v) const {
        return Point2{x_ + v.x(), y_ + v.y()};
    }
    
    /// @brief Translates the point by the negation of a vector
    constexpr Point2 operator-(const Vec2<T>& v) const {
        return Point2{x_ - v.x(), y_ - v.y()};
    }
    
    /// @brief Computes the vector from another point to this point
    constexpr Vec2<T> operator-(const Point2& other) const {
        return Vec2<T>{x_ - other.x_, y_ - other.y_};
    }
    
    /// @brief Checks if two points are equal
    constexpr bool operator==(const Point2& other) const {
        return x_ == other.x_ && y_ == other.y_;
    }
    
    /// @brief Checks if two points are not equal
    constexpr bool operator!=(const Point2& other) const {
        return !(*this == other);
    }
    
    /**
     * @brief Checks if two points are approximately equal
     * @param other The other point
     * @param epsilon The tolerance
     * @return true if the distance is less than epsilon
     */
    bool approx_equal(const Point2& other, T epsilon = static_cast<T>(constants::EPSILON)) const {
        return distance_squared(other) < epsilon * epsilon;
    }
    
    /// @brief The origin point (0, 0)
    static constexpr Point2 origin() { return Point2{T{0}, T{0}}; }

private:
    T x_, y_;
};

//=============================================================================
// 3D Point
//=============================================================================

/**
 * @brief A 3D point in Cartesian coordinates
 * @tparam T The scalar type
 * 
 * Represents a position in 3D space with geometric semantics.
 * 
 * @see Vec3, Point2
 */
template<typename T>
class Point3 {
public:
    /// @brief Default constructor, initializes to origin (0, 0, 0)
    constexpr Point3() : x_(T{}), y_(T{}), z_(T{}) {}
    
    /**
     * @brief Constructs a point from x, y, z coordinates
     * @param x The x coordinate
     * @param y The y coordinate
     * @param z The z coordinate
     */
    constexpr Point3(T x, T y, T z) : x_(x), y_(y), z_(z) {}
    
    /**
     * @brief Constructs a point from a vector (position vector)
     * @param v The position vector
     */
    explicit constexpr Point3(const Vec3<T>& v) : x_(v.x()), y_(v.y()), z_(v.z()) {}
    
    /**
     * @brief Constructs a 3D point from a 2D point with z=0
     * @param p2 The 2D point
     * @param z The z coordinate (default 0)
     */
    explicit constexpr Point3(const Point2<T>& p2, T z = T{}) 
        : x_(p2.x()), y_(p2.y()), z_(z) {}
    
    /// @brief Gets the x coordinate
    constexpr T x() const { return x_; }
    /// @brief Gets the y coordinate
    constexpr T y() const { return y_; }
    /// @brief Gets the z coordinate
    constexpr T z() const { return z_; }
    
    /// @brief Sets the x coordinate
    constexpr void set_x(T x) { x_ = x; }
    /// @brief Sets the y coordinate
    constexpr void set_y(T y) { y_ = y; }
    /// @brief Sets the z coordinate
    constexpr void set_z(T z) { z_ = z; }
    
    /**
     * @brief Converts to a position vector
     * @return The position vector from origin to this point
     */
    constexpr Vec3<T> to_vec() const { return Vec3<T>{x_, y_, z_}; }
    
    /**
     * @brief Projects to a 2D point (drops z coordinate)
     * @return The 2D projection
     */
    constexpr Point2<T> xy() const { return Point2<T>{x_, y_}; }
    
    /**
     * @brief Computes the Euclidean distance to another point
     * @param other The other point
     * @return The distance
     */
    T distance_to(const Point3& other) const {
        T dx = x_ - other.x_;
        T dy = y_ - other.y_;
        T dz = z_ - other.z_;
        return std::sqrt(dx * dx + dy * dy + dz * dz);
    }
    
    /**
     * @brief Computes the squared distance to another point
     * @param other The other point
     * @return The squared distance
     */
    constexpr T distance_squared(const Point3& other) const {
        T dx = x_ - other.x_;
        T dy = y_ - other.y_;
        T dz = z_ - other.z_;
        return dx * dx + dy * dy + dz * dz;
    }
    
    /**
     * @brief Computes the midpoint between this point and another
     * @param other The other point
     * @return The midpoint
     */
    constexpr Point3 midpoint(const Point3& other) const {
        return Point3{
            (x_ + other.x_) / T{2},
            (y_ + other.y_) / T{2},
            (z_ + other.z_) / T{2}
        };
    }
    
    /**
     * @brief Linearly interpolates between this point and another
     * @param other The target point
     * @param t The interpolation factor (0 = this, 1 = other)
     * @return The interpolated point
     */
    constexpr Point3 lerp(const Point3& other, T t) const {
        return Point3{
            x_ + (other.x_ - x_) * t,
            y_ + (other.y_ - y_) * t,
            z_ + (other.z_ - z_) * t
        };
    }
    
    /// @brief Translates the point by a vector
    constexpr Point3 operator+(const Vec3<T>& v) const {
        return Point3{x_ + v.x(), y_ + v.y(), z_ + v.z()};
    }
    
    /// @brief Translates the point by the negation of a vector
    constexpr Point3 operator-(const Vec3<T>& v) const {
        return Point3{x_ - v.x(), y_ - v.y(), z_ - v.z()};
    }
    
    /// @brief Computes the vector from another point to this point
    constexpr Vec3<T> operator-(const Point3& other) const {
        return Vec3<T>{x_ - other.x_, y_ - other.y_, z_ - other.z_};
    }
    
    /// @brief Checks if two points are equal
    constexpr bool operator==(const Point3& other) const {
        return x_ == other.x_ && y_ == other.y_ && z_ == other.z_;
    }
    
    /// @brief Checks if two points are not equal
    constexpr bool operator!=(const Point3& other) const {
        return !(*this == other);
    }
    
    /// @brief The origin point (0, 0, 0)
    static constexpr Point3 origin() { return Point3{T{0}, T{0}, T{0}}; }

private:
    T x_, y_, z_;
};

//=============================================================================
// 2D Transform
//=============================================================================

/**
 * @brief A 2D rigid transformation (rotation + translation)
 * @tparam T The scalar type
 * 
 * Represents a 2D transformation consisting of a rotation around the origin
 * followed by a translation. Can be used to transform points and vectors.
 * 
 * @code
 * Transform2<f64> t = Transform2<f64>::from_rotation(constants::HALF_PI);
 * t = t.then_translate(Vec2d{1.0, 0.0});
 * 
 * Point2<f64> p{1.0, 0.0};
 * Point2<f64> transformed = t.apply(p);  // Rotated 90° then translated
 * @endcode
 * 
 * @see Transform3, Point2
 */
template<typename T>
class Transform2 {
public:
    /**
     * @brief Default constructor, creates an identity transform
     */
    constexpr Transform2() : rotation_(T{0}), translation_{T{0}, T{0}} {}
    
    /**
     * @brief Constructs a transform from rotation angle and translation
     * @param rotation The rotation angle in radians
     * @param translation The translation vector
     */
    constexpr Transform2(T rotation, Vec2<T> translation)
        : rotation_(rotation), translation_(translation) {}
    
    /// @brief Gets the rotation angle in radians
    constexpr T rotation() const { return rotation_; }
    
    /// @brief Gets the translation vector
    constexpr const Vec2<T>& translation() const { return translation_; }
    
    /**
     * @brief Applies this transform to a point
     * @param p The point to transform
     * @return The transformed point
     */
    Point2<T> apply(const Point2<T>& p) const {
        // Rotate then translate
        T cos_r = std::cos(rotation_);
        T sin_r = std::sin(rotation_);
        T rx = p.x() * cos_r - p.y() * sin_r;
        T ry = p.x() * sin_r + p.y() * cos_r;
        return Point2<T>{rx + translation_.x(), ry + translation_.y()};
    }
    
    /**
     * @brief Applies this transform to a vector (rotation only)
     * @param v The vector to transform
     * @return The transformed vector
     * @note Vectors are not affected by translation
     */
    Vec2<T> apply(const Vec2<T>& v) const {
        T cos_r = std::cos(rotation_);
        T sin_r = std::sin(rotation_);
        return Vec2<T>{
            v.x() * cos_r - v.y() * sin_r,
            v.x() * sin_r + v.y() * cos_r
        };
    }
    
    /**
     * @brief Computes the inverse transform
     * @return The inverse transform
     */
    Transform2 inverse() const {
        T inv_rot = -rotation_;
        T cos_r = std::cos(inv_rot);
        T sin_r = std::sin(inv_rot);
        Vec2<T> inv_trans{
            -(translation_.x() * cos_r - translation_.y() * sin_r),
            -(translation_.x() * sin_r + translation_.y() * cos_r)
        };
        return Transform2{inv_rot, inv_trans};
    }
    
    /**
     * @brief Composes this transform with another (this * other)
     * @param other The transform to apply after this one
     * @return The composed transform
     */
    Transform2 compose(const Transform2& other) const {
        T new_rot = rotation_ + other.rotation_;
        Vec2<T> rotated_trans = apply(other.translation_);
        return Transform2{new_rot, Vec2<T>{
            rotated_trans.x() + translation_.x() - other.translation_.x(),
            rotated_trans.y() + translation_.y() - other.translation_.y()
        }};
    }
    
    /**
     * @brief Creates a pure rotation transform
     * @param radians The rotation angle in radians
     * @return A rotation transform
     */
    static Transform2 from_rotation(T radians) {
        return Transform2{radians, Vec2<T>{T{0}, T{0}}};
    }
    
    /**
     * @brief Creates a pure translation transform
     * @param v The translation vector
     * @return A translation transform
     */
    static Transform2 from_translation(const Vec2<T>& v) {
        return Transform2{T{0}, v};
    }
    
    /**
     * @brief Returns a new transform with additional translation
     * @param v The additional translation
     * @return The new transform
     */
    Transform2 then_translate(const Vec2<T>& v) const {
        return Transform2{rotation_, translation_ + v};
    }
    
    /**
     * @brief Returns a new transform with additional rotation
     * @param radians The additional rotation angle
     * @return The new transform
     */
    Transform2 then_rotate(T radians) const {
        return Transform2{rotation_ + radians, translation_};
    }
    
    /// @brief The identity transform (no rotation, no translation)
    static constexpr Transform2 identity() {
        return Transform2{T{0}, Vec2<T>{T{0}, T{0}}};
    }

private:
    T rotation_;        ///< Rotation angle in radians
    Vec2<T> translation_;  ///< Translation vector
};

//=============================================================================
// 3D Transform (simplified - rotation around Z axis only)
//=============================================================================

/**
 * @brief A simplified 3D transformation (Z-axis rotation + translation)
 * @tparam T The scalar type
 * 
 * For simplicity, this transform only supports rotation around the Z axis.
 * For full 3D rotations, a quaternion-based transform would be needed.
 * 
 * @see Transform2, Point3
 * @deprecated Use a quaternion-based transform for full 3D rotations
 */
template<typename T>
class Transform3 {
public:
    /**
     * @brief Default constructor, creates an identity transform
     */
    constexpr Transform3() : rotation_z_(T{0}), translation_{T{0}, T{0}, T{0}} {}
    
    /**
     * @brief Constructs a transform from Z rotation and translation
     * @param rotation_z The rotation angle around Z axis in radians
     * @param translation The translation vector
     */
    constexpr Transform3(T rotation_z, Vec3<T> translation)
        : rotation_z_(rotation_z), translation_(translation) {}
    
    /// @brief Gets the rotation angle around Z axis
    constexpr T rotation_z() const { return rotation_z_; }
    
    /// @brief Gets the translation vector
    constexpr const Vec3<T>& translation() const { return translation_; }
    
    /**
     * @brief Applies this transform to a point
     * @param p The point to transform
     * @return The transformed point
     */
    Point3<T> apply(const Point3<T>& p) const {
        T cos_r = std::cos(rotation_z_);
        T sin_r = std::sin(rotation_z_);
        T rx = p.x() * cos_r - p.y() * sin_r;
        T ry = p.x() * sin_r + p.y() * cos_r;
        return Point3<T>{
            rx + translation_.x(),
            ry + translation_.y(),
            p.z() + translation_.z()
        };
    }
    
    /**
     * @brief Creates a pure translation transform
     * @param v The translation vector
     * @return A translation transform
     */
    static Transform3 from_translation(const Vec3<T>& v) {
        return Transform3{T{0}, v};
    }
    
    /// @brief The identity transform
    static constexpr Transform3 identity() {
        return Transform3{T{0}, Vec3<T>{T{0}, T{0}, T{0}}};
    }

private:
    T rotation_z_;
    Vec3<T> translation_;
};

//=============================================================================
// Common Type Aliases
//=============================================================================

/// @brief 2D point with single precision
using Point2f = Point2<f32>;

/// @brief 2D point with double precision
using Point2d = Point2<f64>;

/// @brief 3D point with single precision
using Point3f = Point3<f32>;

/// @brief 3D point with double precision
using Point3d = Point3<f64>;

/// @brief 2D transform with double precision
using Transform2d = Transform2<f64>;

/// @brief 3D transform with double precision
using Transform3d = Transform3<f64>;

} // namespace spatial
