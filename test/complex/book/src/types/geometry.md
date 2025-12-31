# include/spatial/geometry.hpp

## Classes

### `spatial::Point2`

```cpp
class spatial::Point2 {
};
```

---

### `spatial::Point3`

```cpp
class spatial::Point3 {
};
```

---

### `spatial::Transform2`

```cpp
class spatial::Transform2 {
};
```

---

### `spatial::Transform3`

```cpp
class spatial::Transform3 {
};
```

---

### `spatial::Point2`

```cpp
class spatial::Point2 {
public:
    void Point2();
    void Point2(T x, T y);
    void Point2(const Vec2<T> v);
    T x() const;
    T y() const;
    void set_x(T x);
    void set_y(T y);
    void to_vec() const;
    T distance_to(const Point2 other) const;
    T distance_squared(const Point2 other) const;
    Point2 midpoint(const Point2 other) const;
    Point2 lerp(const Point2 other, T t) const;
    bool approx_equal(const Point2 other) const;
    static Point2 origin();
private:
    T y_;
};
```

A 2D point in Cartesian coordinates

@tparam T The scalar type
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

**See also:** `Vec2, Point3`

**Public Methods:**

- `Point2()`: Default constructor, initializes to origin (0, 0)
- `Point2(T, T)`: Constructs a point from x and y coordinates
- `Point2(const Vec2&lt;T&gt;)`: Constructs a point from a vector (position vector)
- `x()`: Gets the x coordinate
- `y()`: Gets the y coordinate
- `set_x(T)`: Sets the x coordinate
- `set_y(T)`: Sets the y coordinate
- `to_vec()`: Converts to a position vector
- `distance_to(const Point2)`: Computes the Euclidean distance to another point
- `distance_squared(const Point2)`: Computes the squared distance to another point
- `midpoint(const Point2)`: Computes the midpoint between this point and another
- `lerp(const Point2, T)`: Linearly interpolates between this point and another
- `approx_equal(const Point2)`: Checks if two points are approximately equal
- `origin()`: The origin point (0, 0)

---

### `spatial::Point3`

```cpp
class spatial::Point3 {
public:
    void Point3();
    void Point3(T x, T y, T z);
    void Point3(const Vec3<T> v);
    void Point3(const Point2<T> p2);
    T x() const;
    T y() const;
    T z() const;
    void set_x(T x);
    void set_y(T y);
    void set_z(T z);
    void to_vec() const;
    void xy() const;
    T distance_to(const Point3 other) const;
    T distance_squared(const Point3 other) const;
    Point3 midpoint(const Point3 other) const;
    Point3 lerp(const Point3 other, T t) const;
    static Point3 origin();
private:
    T z_;
};
```

A 3D point in Cartesian coordinates

@tparam T The scalar type
 * 
 * Represents a position in 3D space with geometric semantics.

**See also:** `Vec3, Point2`

**Public Methods:**

- `Point3()`: Default constructor, initializes to origin (0, 0, 0)
- `Point3(T, T, T)`: Constructs a point from x, y, z coordinates
- `Point3(const Vec3&lt;T&gt;)`: Constructs a point from a vector (position vector)
- `Point3(const Point2&lt;T&gt;)`: Constructs a 3D point from a 2D point with z=0
- `x()`: Gets the x coordinate
- `y()`: Gets the y coordinate
- `z()`: Gets the z coordinate
- `set_x(T)`: Sets the x coordinate
- `set_y(T)`: Sets the y coordinate
- `set_z(T)`: Sets the z coordinate
- `to_vec()`: Converts to a position vector
- `xy()`: Projects to a 2D point (drops z coordinate)
- `distance_to(const Point3)`: Computes the Euclidean distance to another point
- `distance_squared(const Point3)`: Computes the squared distance to another point
- `midpoint(const Point3)`: Computes the midpoint between this point and another
- `lerp(const Point3, T)`: Linearly interpolates between this point and another
- `origin()`: The origin point (0, 0, 0)

---

### `spatial::Transform2`

```cpp
class spatial::Transform2 {
public:
    void Transform2();
    void Transform2(T rotation, Vec2<T> translation);
    T rotation() const;
    void apply(const Point2<T> p) const;
    void apply(const Vec2<T> v) const;
    Transform2 inverse() const;
    Transform2 compose(const Transform2 other) const;
    static Transform2 from_rotation(T radians);
    static Transform2 from_translation(const Vec2<T> v);
    Transform2 then_translate(const Vec2<T> v) const;
    Transform2 then_rotate(T radians) const;
    static Transform2 identity();
private:
    T rotation_;
    unknown translation_;
};
```

A 2D rigid transformation (rotation + translation)

@tparam T The scalar type
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

**See also:** `Transform3, Point2`

**Public Methods:**

- `Transform2()`: Default constructor, creates an identity transform
- `Transform2(T, Vec2&lt;T&gt;)`: Constructs a transform from rotation angle and translation
- `rotation()`: Gets the rotation angle in radians
- `apply(const Point2&lt;T&gt;)`: Applies this transform to a point
- `apply(const Vec2&lt;T&gt;)`: Applies this transform to a vector (rotation only)
- `inverse()`: Computes the inverse transform
- `compose(const Transform2)`: Composes this transform with another (this * other)
- `from_rotation(T)`: Creates a pure rotation transform
- `from_translation(const Vec2&lt;T&gt;)`: Creates a pure translation transform
- `then_translate(const Vec2&lt;T&gt;)`: Returns a new transform with additional translation
- `then_rotate(T)`: Returns a new transform with additional rotation
- `identity()`: The identity transform (no rotation, no translation)

---

### `spatial::Transform3`

```cpp
class spatial::Transform3 {
public:
    void Transform3();
    void Transform3(T rotation_z, Vec3<T> translation);
    T rotation_z() const;
    void apply(const Point3<T> p) const;
    static Transform3 from_translation(const Vec3<T> v);
    static Transform3 identity();
private:
    T rotation_z_;
    unknown translation_;
};
```

A simplified 3D transformation (Z-axis rotation + translation)

@tparam T The scalar type
 * 
 * For simplicity, this transform only supports rotation around the Z axis.
 * For full 3D rotations, a quaternion-based transform would be needed.

**See also:** `Transform2, Point3`

**Public Methods:**

- `Transform3()`: Default constructor, creates an identity transform
- `Transform3(T, Vec3&lt;T&gt;)`: Constructs a transform from Z rotation and translation
- `rotation_z()`: Gets the rotation angle around Z axis
- `apply(const Point3&lt;T&gt;)`: Applies this transform to a point
- `from_translation(const Vec3&lt;T&gt;)`: Creates a pure translation transform
- `identity()`: The identity transform

---

