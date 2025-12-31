# include/spatial/vector.hpp

## Classes

### `spatial::Vector`

```cpp
class spatial::Vector {
public:
    usize dimensions;
    void Vector();
    void Vector(T scalar);
    void Vector(std::initializer_list<T> init);
    void at(usize i) const;
    bool approx_equal(const Vector other) const;
    T dot(const Vector other) const;
    T magnitude_squared() const;
    T magnitude() const;
    Vector normalized() const;
    void safe_normalized() const;
    bool is_normalized() const;
    bool is_zero() const;
private:
    unknown data_;
};
```

N-dimensional vector class

@tparam T The scalar type (must be numeric)
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

**See also:** `Vec2, Vec3, Vec4`

**Public Methods:**

- `Vector()`: Default constructor, initializes all components to zero
- `Vector(T)`: Constructs a vector with all components set to the same value
- `Vector(std::initializer_list&lt;T&gt;)`: Constructs a vector from an initializer list
- `at(usize)`: Safely accesses a component by index
- `approx_equal(const Vector)`: Checks if two vectors are approximately equal
- `dot(const Vector)`: Computes the dot product with another vector
- `magnitude_squared()`: Computes the squared magnitude (length squared)
- `magnitude()`: Computes the magnitude (length) of the vector
- `normalized()`: Returns a normalized (unit length) version of this vector
- `safe_normalized()`: Safely normalizes the vector
- `is_normalized()`: Checks if this is a unit vector (magnitude ≈ 1)
- `is_zero()`: Checks if this is a zero vector

---

### `spatial::Vec2`

```cpp
class spatial::Vec2 {
public:
    void Vec2(T x, T y);
    Vec2 perpendicular() const;
    T cross(const Vec2 other) const;
    T angle() const;
    static Vec2 from_angle(T radians);
};
```

2D vector with named x, y accessors

@tparam T The scalar type
 * 
 * Extends the base Vector class with convenient x/y accessors
 * and 2D-specific operations.
 * 
 * @code
 * Vec2<f64> v{3.0, 4.0};
 * std::cout << "x=" << v.x() << ", y=" << v.y() << std::endl;
 * std::cout << "perpendicular: " << v.perpendicular() << std::endl;
 * @endcode

**Public Methods:**

- `Vec2(T, T)`: Constructs a 2D vector from x and y components
- `perpendicular()`: Returns a perpendicular vector (rotated 90° counter-clockwise)
- `cross(const Vec2)`: Computes the 2D cross product (z-component of 3D cross)
- `angle()`: Computes the angle of this vector from the positive x-axis
- `from_angle(T)`: Creates a unit vector from an angle

---

### `spatial::Vec3`

```cpp
class spatial::Vec3 {
public:
    void Vec3(T x, T y, T z);
    void Vec3(const Vec2<T> v2, T z);
    void xy() const;
    Vec3 cross(const Vec3 other) const;
    static Vec3 unit_x();
    static Vec3 unit_y();
    static Vec3 unit_z();
};
```

3D vector with named x, y, z accessors

@tparam T The scalar type
 * 
 * Extends the base Vector class with convenient x/y/z accessors
 * and 3D-specific operations like cross product.
 * 
 * @code
 * Vec3<f64> v1{1.0, 0.0, 0.0};
 * Vec3<f64> v2{0.0, 1.0, 0.0};
 * auto cross = v1.cross(v2);  // {0, 0, 1}
 * @endcode

**See also:** `Vec2, Vector`

**Public Methods:**

- `Vec3(T, T, T)`: Constructs a 3D vector from x, y, z components
- `Vec3(const Vec2&lt;T&gt;, T)`: Constructs a 3D vector from a 2D vector and z component
- `xy()`: Returns the xy components as a 2D vector
- `cross(const Vec3)`: Computes the cross product with another vector
- `unit_x()`: Unit vector along the positive x-axis
- `unit_y()`: Unit vector along the positive y-axis
- `unit_z()`: Unit vector along the positive z-axis

---

