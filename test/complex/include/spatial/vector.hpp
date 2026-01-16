/**
 * @file vector.hpp
 * @brief N-dimensional vector class template
 * @author Stig Test Suite
 * @version 1.0.0
 * 
 * Provides a generic Vector class with specializations for 2D and 3D vectors.
 * Supports common vector operations like dot product, cross product, and normalization.
 */

#pragma once

#include "types.hpp"
#include <cmath>
#include <array>
#include <initializer_list>

namespace spatial {

/**
 * @brief N-dimensional vector class
 * @tparam T The scalar type (must be numeric)
 * @tparam N The number of dimensions
 * 
 * A generic vector class supporting arbitrary dimensions.
 * Provides mathematical operations and utility functions.
 * 
 * @code
 * Vector<f64, 3> v1{1.0, 2.0, 3.0};
 * Vector<f64, 3> v2{4.0, 5.0, 6.0};
 * 
 * auto sum = v1 + v2;           // Vector addition
 * auto dot = v1.dot(v2);        // Dot product
 * auto normalized = v1.normalized();  // Unit vector
 * @endcode
 * 
 * @see Vec2, Vec3, Vec4
 */
template<typename T, usize N>
class Vector {
    static_assert(is_numeric_v<T>, "Vector requires a numeric type");
    static_assert(N > 0, "Vector dimension must be positive");

public:
    /// @brief The scalar type of vector components
    using value_type = T;
    
    /// @brief The number of dimensions
    static constexpr usize dimensions = N;

    //=========================================================================
    // Constructors
    //=========================================================================
    
    /// @brief Default constructor, initializes all components to zero
    constexpr Vector() : data_{} {}
    
    /**
     * @brief Constructs a vector with all components set to the same value
     * @param scalar The value for all components
     */
    explicit constexpr Vector(T scalar) {
        for (usize i = 0; i < N; ++i) data_[i] = scalar;
    }
    
    /**
     * @brief Constructs a vector from an initializer list
     * @param init The initializer list of values
     * @note If fewer values are provided, remaining components are zero-initialized
     */
    constexpr Vector(std::initializer_list<T> init) : data_{} {
        usize i = 0;
        for (auto val : init) {
            if (i >= N) break;
            data_[i++] = val;
        }
    }

    //=========================================================================
    // Element Access
    //=========================================================================
    
    /**
     * @brief Accesses a component by index
     * @param i The component index
     * @return Reference to the component
     * @warning No bounds checking is performed
     */
    constexpr T& operator[](usize i) { return data_[i]; }
    
    /**
     * @brief Accesses a component by index (const)
     * @param i The component index
     * @return Const reference to the component
     * @warning No bounds checking is performed
     */
    constexpr const T& operator[](usize i) const { return data_[i]; }
    
    /**
     * @brief Safely accesses a component by index
     * @param i The component index
     * @return Result containing the component or an error
     */
    Result<T> at(usize i) const {
        if (i >= N) return Result<T>::error(ErrorCode::OutOfBounds);
        return Result<T>::ok(data_[i]);
    }
    
    /// @brief Returns a pointer to the underlying data
    constexpr T* data() { return data_.data(); }
    
    /// @brief Returns a const pointer to the underlying data
    constexpr const T* data() const { return data_.data(); }

    //=========================================================================
    // Arithmetic Operators
    //=========================================================================
    
    /// @brief Adds two vectors component-wise
    constexpr Vector operator+(const Vector& other) const {
        Vector result;
        for (usize i = 0; i < N; ++i) result[i] = data_[i] + other[i];
        return result;
    }
    
    /// @brief Subtracts two vectors component-wise
    constexpr Vector operator-(const Vector& other) const {
        Vector result;
        for (usize i = 0; i < N; ++i) result[i] = data_[i] - other[i];
        return result;
    }
    
    /// @brief Multiplies vector by a scalar
    constexpr Vector operator*(T scalar) const {
        Vector result;
        for (usize i = 0; i < N; ++i) result[i] = data_[i] * scalar;
        return result;
    }
    
    /// @brief Divides vector by a scalar
    constexpr Vector operator/(T scalar) const {
        Vector result;
        for (usize i = 0; i < N; ++i) result[i] = data_[i] / scalar;
        return result;
    }
    
    /// @brief Negates the vector
    constexpr Vector operator-() const {
        Vector result;
        for (usize i = 0; i < N; ++i) result[i] = -data_[i];
        return result;
    }
    
    /// @brief Adds another vector to this one
    constexpr Vector& operator+=(const Vector& other) {
        for (usize i = 0; i < N; ++i) data_[i] += other[i];
        return *this;
    }
    
    /// @brief Subtracts another vector from this one
    constexpr Vector& operator-=(const Vector& other) {
        for (usize i = 0; i < N; ++i) data_[i] -= other[i];
        return *this;
    }
    
    /// @brief Multiplies this vector by a scalar
    constexpr Vector& operator*=(T scalar) {
        for (usize i = 0; i < N; ++i) data_[i] *= scalar;
        return *this;
    }
    
    /// @brief Divides this vector by a scalar
    constexpr Vector& operator/=(T scalar) {
        for (usize i = 0; i < N; ++i) data_[i] /= scalar;
        return *this;
    }

    //=========================================================================
    // Comparison Operators
    //=========================================================================
    
    /// @brief Checks if two vectors are exactly equal
    constexpr bool operator==(const Vector& other) const {
        for (usize i = 0; i < N; ++i) {
            if (data_[i] != other[i]) return false;
        }
        return true;
    }
    
    /// @brief Checks if two vectors are not equal
    constexpr bool operator!=(const Vector& other) const {
        return !(*this == other);
    }
    
    /**
     * @brief Checks if two vectors are approximately equal
     * @param other The vector to compare with
     * @param epsilon The tolerance for comparison
     * @return true if all components differ by less than epsilon
     */
    bool approx_equal(const Vector& other, T epsilon = static_cast<T>(constants::EPSILON)) const {
        for (usize i = 0; i < N; ++i) {
            if (std::abs(data_[i] - other[i]) >= epsilon) return false;
        }
        return true;
    }

    //=========================================================================
    // Vector Operations
    //=========================================================================
    
    /**
     * @brief Computes the dot product with another vector
     * @param other The other vector
     * @return The dot product (scalar)
     */
    constexpr T dot(const Vector& other) const {
        T result = T{};
        for (usize i = 0; i < N; ++i) result += data_[i] * other[i];
        return result;
    }
    
    /**
     * @brief Computes the squared magnitude (length squared)
     * @return The squared magnitude
     * @note More efficient than magnitude() when only comparing lengths
     */
    constexpr T magnitude_squared() const {
        return dot(*this);
    }
    
    /**
     * @brief Computes the magnitude (length) of the vector
     * @return The magnitude
     */
    T magnitude() const {
        return std::sqrt(magnitude_squared());
    }
    
    /**
     * @brief Returns a normalized (unit length) version of this vector
     * @return The normalized vector
     * @warning Returns zero vector if magnitude is zero
     */
    Vector normalized() const {
        T mag = magnitude();
        if (mag == T{}) return Vector{};
        return *this / mag;
    }
    
    /**
     * @brief Safely normalizes the vector
     * @return Result containing the normalized vector or an error
     */
    Result<Vector> safe_normalized() const {
        T mag = magnitude();
        if (mag == T{}) return Result<Vector>::error(ErrorCode::DivisionByZero);
        return Result<Vector>::ok(*this / mag);
    }
    
    /**
     * @brief Normalizes this vector in place
     * @return Reference to this vector
     */
    Vector& normalize() {
        T mag = magnitude();
        if (mag != T{}) *this /= mag;
        return *this;
    }
    
    /**
     * @brief Checks if this is a unit vector (magnitude ≈ 1)
     * @param epsilon The tolerance for comparison
     * @return true if the vector is normalized
     */
    bool is_normalized(T epsilon = static_cast<T>(constants::EPSILON)) const {
        return std::abs(magnitude_squared() - T{1}) < epsilon;
    }
    
    /**
     * @brief Checks if this is a zero vector
     * @return true if all components are zero
     */
    constexpr bool is_zero() const {
        for (usize i = 0; i < N; ++i) {
            if (data_[i] != T{}) return false;
        }
        return true;
    }

private:
    std::array<T, N> data_;
};

//=============================================================================
// Scalar * Vector operator
//=============================================================================

/**
 * @brief Multiplies a scalar by a vector
 * @tparam T The scalar type
 * @tparam N The vector dimension
 * @param scalar The scalar value
 * @param vec The vector
 * @return The scaled vector
 */
template<typename T, usize N>
constexpr Vector<T, N> operator*(T scalar, const Vector<T, N>& vec) {
    return vec * scalar;
}

//=============================================================================
// 2D Vector Specialization
//=============================================================================

/**
 * @brief 2D vector with named x, y accessors
 * @tparam T The scalar type
 * 
 * Extends the base Vector class with convenient x/y accessors
 * and 2D-specific operations.
 * 
 * @code
 * Vec2<f64> v{3.0, 4.0};
 * std::cout << "x=" << v.x() << ", y=" << v.y() << std::endl;
 * std::cout << "perpendicular: " << v.perpendicular() << std::endl;
 * @endcode
 */
template<typename T>
class Vec2 : public Vector<T, 2> {
public:
    using Vector<T, 2>::Vector;
    
    /**
     * @brief Constructs a 2D vector from x and y components
     * @param x The x component
     * @param y The y component
     */
    constexpr Vec2(T x, T y) : Vector<T, 2>{x, y} {}
    
    /// @brief Gets the x component
    constexpr T& x() { return (*this)[0]; }
    /// @brief Gets the x component (const)
    constexpr const T& x() const { return (*this)[0]; }
    
    /// @brief Gets the y component
    constexpr T& y() { return (*this)[1]; }
    /// @brief Gets the y component (const)
    constexpr const T& y() const { return (*this)[1]; }
    
    /**
     * @brief Returns a perpendicular vector (rotated 90° counter-clockwise)
     * @return The perpendicular vector
     */
    constexpr Vec2 perpendicular() const {
        return Vec2{-y(), x()};
    }
    
    /**
     * @brief Computes the 2D cross product (z-component of 3D cross)
     * @param other The other vector
     * @return The cross product scalar
     * 
     * This is equivalent to the z-component of the 3D cross product
     * when both vectors are in the xy-plane.
     */
    constexpr T cross(const Vec2& other) const {
        return x() * other.y() - y() * other.x();
    }
    
    /**
     * @brief Computes the angle of this vector from the positive x-axis
     * @return The angle in radians [-π, π]
     */
    T angle() const {
        return std::atan2(y(), x());
    }
    
    /**
     * @brief Creates a unit vector from an angle
     * @param radians The angle in radians
     * @return A unit vector pointing in that direction
     */
    static Vec2 from_angle(T radians) {
        return Vec2{std::cos(radians), std::sin(radians)};
    }
};

//=============================================================================
// 3D Vector Specialization
//=============================================================================

/**
 * @brief 3D vector with named x, y, z accessors
 * @tparam T The scalar type
 * 
 * Extends the base Vector class with convenient x/y/z accessors
 * and 3D-specific operations like cross product.
 * 
 * @code
 * Vec3<f64> v1{1.0, 0.0, 0.0};
 * Vec3<f64> v2{0.0, 1.0, 0.0};
 * auto cross = v1.cross(v2);  // {0, 0, 1}
 * @endcode
 * 
 * @see Vec2, Vector
 */
template<typename T>
class Vec3 : public Vector<T, 3> {
public:
    using Vector<T, 3>::Vector;
    
    /**
     * @brief Constructs a 3D vector from x, y, z components
     * @param x The x component
     * @param y The y component
     * @param z The z component
     */
    constexpr Vec3(T x, T y, T z) : Vector<T, 3>{x, y, z} {}
    
    /**
     * @brief Constructs a 3D vector from a 2D vector and z component
     * @param v2 The 2D vector (x, y)
     * @param z The z component
     */
    constexpr Vec3(const Vec2<T>& v2, T z) : Vector<T, 3>{v2.x(), v2.y(), z} {}
    
    /// @brief Gets the x component
    constexpr T& x() { return (*this)[0]; }
    /// @brief Gets the x component (const)
    constexpr const T& x() const { return (*this)[0]; }
    
    /// @brief Gets the y component
    constexpr T& y() { return (*this)[1]; }
    /// @brief Gets the y component (const)
    constexpr const T& y() const { return (*this)[1]; }
    
    /// @brief Gets the z component
    constexpr T& z() { return (*this)[2]; }
    /// @brief Gets the z component (const)
    constexpr const T& z() const { return (*this)[2]; }
    
    /**
     * @brief Returns the xy components as a 2D vector
     * @return A Vec2 containing x and y
     */
    constexpr Vec2<T> xy() const { return Vec2<T>{x(), y()}; }
    
    /**
     * @brief Computes the cross product with another vector
     * @param other The other vector
     * @return The cross product vector
     * 
     * The cross product produces a vector perpendicular to both inputs.
     * The magnitude equals the area of the parallelogram formed by the vectors.
     */
    constexpr Vec3 cross(const Vec3& other) const {
        return Vec3{
            y() * other.z() - z() * other.y(),
            z() * other.x() - x() * other.z(),
            x() * other.y() - y() * other.x()
        };
    }
    
    /// @brief Unit vector along the positive x-axis
    static constexpr Vec3 unit_x() { return Vec3{T{1}, T{0}, T{0}}; }
    
    /// @brief Unit vector along the positive y-axis
    static constexpr Vec3 unit_y() { return Vec3{T{0}, T{1}, T{0}}; }
    
    /// @brief Unit vector along the positive z-axis
    static constexpr Vec3 unit_z() { return Vec3{T{0}, T{0}, T{1}}; }
};

//=============================================================================
// Common Type Aliases
//=============================================================================

/// @brief 2D vector with single precision
using Vec2f = Vec2<f32>;

/// @brief 2D vector with double precision
using Vec2d = Vec2<f64>;

/// @brief 3D vector with single precision
using Vec3f = Vec3<f32>;

/// @brief 3D vector with double precision
using Vec3d = Vec3<f64>;

/// @brief 4D vector with double precision
using Vec4d = Vector<f64, 4>;

} // namespace spatial
