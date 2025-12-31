/**
 * @file types.hpp
 * @brief Core type definitions for the spatial geometry library
 * @author Stig Test Suite
 * @version 1.0.0
 * 
 * This header provides fundamental type aliases and utility types
 * used throughout the spatial geometry library.
 */

#pragma once

#include <cstdint>
#include <cstddef>
#include <type_traits>

namespace spatial {

//=============================================================================
// Numeric Type Aliases
//=============================================================================

/// @brief Single precision floating point (32-bit)
using f32 = float;

/// @brief Double precision floating point (64-bit)
using f64 = double;

/// @brief Signed 32-bit integer
using i32 = std::int32_t;

/// @brief Unsigned 32-bit integer
using u32 = std::uint32_t;

/// @brief Signed 64-bit integer
using i64 = std::int64_t;

/// @brief Unsigned 64-bit integer
using u64 = std::uint64_t;

/// @brief Size type for indexing and counts
using usize = std::size_t;

//=============================================================================
// Constants
//=============================================================================

/**
 * @brief Mathematical constants with high precision
 */
namespace constants {
    /// @brief Pi constant (3.14159...)
    constexpr f64 PI = 3.14159265358979323846;
    
    /// @brief Two times Pi
    constexpr f64 TWO_PI = 2.0 * PI;
    
    /// @brief Pi divided by two
    constexpr f64 HALF_PI = PI / 2.0;
    
    /// @brief Default epsilon for floating point comparisons
    constexpr f64 EPSILON = 1e-9;
    
    /// @brief Conversion factor from degrees to radians
    constexpr f64 DEG_TO_RAD = PI / 180.0;
    
    /// @brief Conversion factor from radians to degrees
    constexpr f64 RAD_TO_DEG = 180.0 / PI;
}

//=============================================================================
// Result Type
//=============================================================================

/**
 * @brief Error codes for spatial operations
 * 
 * Used with Result<T> to indicate failure conditions.
 * 
 * @see Result
 */
enum class ErrorCode : u32 {
    None = 0,           ///< No error
    InvalidInput,       ///< Input parameters are invalid
    OutOfBounds,        ///< Index or value out of valid range
    DivisionByZero,     ///< Attempted division by zero
    NotNormalized,      ///< Vector is not normalized when required
    Degenerate,         ///< Degenerate geometry (e.g., zero-area triangle)
    NoIntersection,     ///< No intersection found
    NotImplemented      ///< Feature not yet implemented
};

/**
 * @brief Converts an error code to a human-readable string
 * @param code The error code to convert
 * @return String representation of the error
 */
inline const char* error_to_string(ErrorCode code) {
    switch (code) {
        case ErrorCode::None:           return "No error";
        case ErrorCode::InvalidInput:   return "Invalid input";
        case ErrorCode::OutOfBounds:    return "Out of bounds";
        case ErrorCode::DivisionByZero: return "Division by zero";
        case ErrorCode::NotNormalized:  return "Not normalized";
        case ErrorCode::Degenerate:     return "Degenerate geometry";
        case ErrorCode::NoIntersection: return "No intersection";
        case ErrorCode::NotImplemented: return "Not implemented";
        default:                        return "Unknown error";
    }
}

/**
 * @brief A result type that holds either a value or an error
 * @tparam T The success value type
 * 
 * Provides a safe way to return values that may fail.
 * 
 * @code
 * Result<f64> safe_divide(f64 a, f64 b) {
 *     if (b == 0.0) return Result<f64>::error(ErrorCode::DivisionByZero);
 *     return Result<f64>::ok(a / b);
 * }
 * 
 * auto result = safe_divide(10.0, 2.0);
 * if (result.is_ok()) {
 *     std::cout << "Result: " << result.value() << std::endl;
 * }
 * @endcode
 * 
 * @see ErrorCode
 */
template<typename T>
class Result {
public:
    /// @brief Creates a successful result with the given value
    /// @param val The success value
    /// @return A Result containing the value
    static Result ok(T val) { return Result(val, ErrorCode::None); }
    
    /// @brief Creates a failed result with the given error code
    /// @param code The error code
    /// @return A Result containing the error
    static Result error(ErrorCode code) { return Result(T{}, code); }
    
    /// @brief Checks if the result is successful
    /// @return true if the result contains a value, false if it contains an error
    bool is_ok() const { return error_ == ErrorCode::None; }
    
    /// @brief Checks if the result is an error
    /// @return true if the result contains an error, false if it contains a value
    bool is_error() const { return error_ != ErrorCode::None; }
    
    /// @brief Gets the success value
    /// @return The contained value
    /// @warning Undefined behavior if is_error() is true
    const T& value() const { return value_; }
    
    /// @brief Gets the success value (mutable)
    /// @return The contained value
    /// @warning Undefined behavior if is_error() is true
    T& value() { return value_; }
    
    /// @brief Gets the error code
    /// @return The error code (None if successful)
    ErrorCode error() const { return error_; }
    
    /// @brief Gets the value or a default if error
    /// @param default_val The default value to return on error
    /// @return The contained value or the default
    T value_or(T default_val) const {
        return is_ok() ? value_ : default_val;
    }

private:
    Result(T val, ErrorCode err) : value_(val), error_(err) {}
    
    T value_;
    ErrorCode error_;
};

//=============================================================================
// Type Traits
//=============================================================================

/**
 * @brief Type trait to check if a type is a floating point number
 * @tparam T The type to check
 */
template<typename T>
struct is_floating_point : std::is_floating_point<T> {};

/**
 * @brief Helper variable template for is_floating_point
 * @tparam T The type to check
 */
template<typename T>
inline constexpr bool is_floating_point_v = is_floating_point<T>::value;

/**
 * @brief Type trait to check if a type is numeric (integral or floating point)
 * @tparam T The type to check
 */
template<typename T>
struct is_numeric : std::bool_constant<std::is_arithmetic_v<T>> {};

/**
 * @brief Helper variable template for is_numeric
 * @tparam T The type to check
 */
template<typename T>
inline constexpr bool is_numeric_v = is_numeric<T>::value;

} // namespace spatial
