# include/spatial/algorithms.hpp

## Functions

### `spatial::distance`

```c
T spatial::distance(const Point2<T> a, const Point2<T> b);
```

Computes the Euclidean distance between two 2D points

@tparam T The scalar type

**Parameters:**
- `a` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): First point
- `b` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Second point

**Returns:** (T) The distance

**See also:** `Point2::distance_to`

---

### `spatial::distance`

```c
T spatial::distance(const Point3<T> a, const Point3<T> b);
```

Computes the Euclidean distance between two 3D points

@tparam T The scalar type

**Parameters:**
- `a` (const [Point3](../types/geometry.md#spatial::point3)&lt;T&gt;): First point
- `b` (const [Point3](../types/geometry.md#spatial::point3)&lt;T&gt;): Second point

**Returns:** (T) The distance

**See also:** `Point3::distance_to`

---

### `spatial::distance_squared`

```c
T spatial::distance_squared(const Point2<T> a, const Point2<T> b);
```

Computes the squared distance between two 2D points

@tparam T The scalar type

**Parameters:**
- `a` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): First point
- `b` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Second point

**Returns:** (T) The squared distance

---

### `spatial::distance_to_segment`

```c
T spatial::distance_to_segment(const Point2<T> point, const Point2<T> seg_start, const Point2<T> seg_end);
```

Computes the minimum distance from a point to a line segment

@tparam T The scalar type

**Parameters:**
- `point` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): The query point
- `seg_start` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Start of the line segment
- `seg_end` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): End of the line segment

**Returns:** (T) The minimum distance

---

### `spatial::distance_to_circle`

```c
T spatial::distance_to_circle(const Point2<T> point, const Circle<T> circle);
```

Computes the minimum distance from a point to a circle's boundary

@tparam T The scalar type

**Parameters:**
- `point` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): The query point
- `circle` (const [Circle](../types/shapes.md#spatial::circle)&lt;T&gt;): The circle

**Returns:** (T) The distance (negative if inside)

---

### `spatial::segment_intersection`

```c
void spatial::segment_intersection(const Point2<T> a1, const Point2<T> a2, const Point2<T> b1, const Point2<T> b2);
```

Computes the intersection of two line segments

@tparam T The scalar type

**Parameters:**
- `a1` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Start of first segment
- `a2` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): End of first segment
- `b1` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Start of second segment
- `b2` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): End of second segment

**Returns:** (void) Intersection result

**See also:** [LineIntersection](../types/algorithms.md#spatial::lineintersection)

---

### `spatial::circles_intersect`

```c
bool spatial::circles_intersect(const Circle<T> c1, const Circle<T> c2);
```

Checks if two circles intersect

@tparam T The scalar type

**Parameters:**
- `c1` (const [Circle](../types/shapes.md#spatial::circle)&lt;T&gt;): First circle
- `c2` (const [Circle](../types/shapes.md#spatial::circle)&lt;T&gt;): Second circle

**Returns:** (bool) true if the circles overlap

**See also:** `Circle::intersects`

---

### `spatial::aabb_overlap`

```c
bool spatial::aabb_overlap(const AABB<T> a, const AABB<T> b);
```

Checks if two AABBs overlap

@tparam T The scalar type

**Parameters:**
- `a` (const [AABB](../types/shapes.md#spatial::aabb)&lt;T&gt;): First bounding box
- `b` (const [AABB](../types/shapes.md#spatial::aabb)&lt;T&gt;): Second bounding box

**Returns:** (bool) true if the boxes overlap

**See also:** `AABB::overlaps`

---

### `spatial::circle_aabb_overlap`

```c
bool spatial::circle_aabb_overlap(const Circle<T> circle, const AABB<T> box);
```

Checks if a circle and AABB overlap

@tparam T The scalar type

**Parameters:**
- `circle` (const [Circle](../types/shapes.md#spatial::circle)&lt;T&gt;): The circle
- `box` (const [AABB](../types/shapes.md#spatial::aabb)&lt;T&gt;): The bounding box

**Returns:** (bool) true if they overlap

---

### `spatial::point_in_convex_polygon`

```c
bool spatial::point_in_convex_polygon(const Point2<T> point, const Polygon<T> polygon);
```

Checks if a point is inside a convex polygon using cross products

@tparam T The scalar type

**Parameters:**
- `point` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): The query point
- `polygon` (const [Polygon](../types/shapes.md#spatial::polygon)&lt;T&gt;): The convex polygon

**Returns:** (bool) true if the point is inside

> **Note:** This is faster than Polygon::contains() for convex polygons

> **Warning:** Only works correctly for convex polygons

---

### `spatial::aabb_contains`

```c
bool spatial::aabb_contains(const AABB<T> outer, const AABB<T> inner);
```

Checks if one AABB completely contains another

@tparam T The scalar type

**Parameters:**
- `outer` (const [AABB](../types/shapes.md#spatial::aabb)&lt;T&gt;): The potentially containing box
- `inner` (const [AABB](../types/shapes.md#spatial::aabb)&lt;T&gt;): The potentially contained box

**Returns:** (bool) true if outer contains inner

---

### `spatial::signed_triangle_area`

```c
T spatial::signed_triangle_area(const Point2<T> a, const Point2<T> b, const Point2<T> c);
```

Computes the signed area of a triangle

@tparam T The scalar type

**Parameters:**
- `a` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): First vertex
- `b` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Second vertex
- `c` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Third vertex

**Returns:** (T) Signed area (positive if CCW, negative if CW)

---

### `spatial::orientation`

```c
int spatial::orientation(const Point2<T> a, const Point2<T> b, const Point2<T> c);
```

Determines the orientation of three points

@tparam T The scalar type

**Parameters:**
- `a` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): First point
- `b` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Second point
- `c` (const [Point2](../types/geometry.md#spatial::point2)&lt;T&gt;): Third point

**Returns:** (int) 1 if CCW, -1 if CW, 0 if collinear

---

### `spatial::convex_hull`

```c
void spatial::convex_hull(std::vector<Point2<T>> points);
```

Computes the convex hull of a set of points

@tparam T The scalar type

**Parameters:**
- `points` (std::vector&lt;Point2&lt;T&gt;&gt;): The input points

**Returns:** (void) A polygon representing the convex hull

---

### `spatial::centroid`

```c
void spatial::centroid(const std::vector<Point2<T>> points);
```

Computes the centroid of a set of points

@tparam T The scalar type

**Parameters:**
- `points` (const std::vector&lt;Point2&lt;T&gt;&gt;): The input points

**Returns:** (void) The centroid (average position)

> **Note:** Returns origin if points is empty

---

### `spatial::bounding_box`

```c
void spatial::bounding_box(const std::vector<Point2<T>> points);
```

Computes the bounding box of a set of points

@tparam T The scalar type

**Parameters:**
- `points` (const std::vector&lt;Point2&lt;T&gt;&gt;): The input points

**Returns:** (void) The smallest AABB containing all points

---

### `spatial::combined_bounding_box`

```c
void spatial::combined_bounding_box(const std::vector<std::unique_ptr<Shape<T>>> shapes);
```

Computes the bounding box of multiple shapes

@tparam T The scalar type

**Parameters:**
- `shapes` (const std::vector&lt;std::unique_ptr&lt;Shape&lt;T&gt;&gt;&gt;): The input shapes

**Returns:** (void) The smallest AABB containing all shapes

---

### `spatial::normalize_angle`

```c
T spatial::normalize_angle(T radians);
```

Normalizes an angle to the range [-π, π]

@tparam T The scalar type

**Parameters:**
- `radians` (T): The angle in radians

**Returns:** (T) The normalized angle

---

### `spatial::angle_between`

```c
T spatial::angle_between(const Vec2<T> a, const Vec2<T> b);
```

Computes the angle between two vectors

@tparam T The scalar type

**Parameters:**
- `a` (const [Vec2](../types/vector.md#spatial::vec2)&lt;T&gt;): First vector
- `b` (const [Vec2](../types/vector.md#spatial::vec2)&lt;T&gt;): Second vector

**Returns:** (T) The angle in radians [0, π]

---

### `spatial::signed_angle_between`

```c
T spatial::signed_angle_between(const Vec2<T> a, const Vec2<T> b);
```

Computes the signed angle from vector a to vector b

@tparam T The scalar type

**Parameters:**
- `a` (const [Vec2](../types/vector.md#spatial::vec2)&lt;T&gt;): First vector
- `b` (const [Vec2](../types/vector.md#spatial::vec2)&lt;T&gt;): Second vector

**Returns:** (T) The signed angle in radians [-π, π]

---

### `spatial::deg_to_rad`

```c
T spatial::deg_to_rad(T degrees);
```

Converts degrees to radians

@tparam T The scalar type

**Parameters:**
- `degrees` (T): The angle in degrees

**Returns:** (T) The angle in radians

---

### `spatial::rad_to_deg`

```c
T spatial::rad_to_deg(T radians);
```

Converts radians to degrees

@tparam T The scalar type

**Parameters:**
- `radians` (T): The angle in radians

**Returns:** (T) The angle in degrees

---

### `spatial::lerp`

```c
T spatial::lerp(T a, T b, T t);
```

Linearly interpolates between two values

@tparam T The value type

**Parameters:**
- `a` (T): Start value
- `b` (T): End value
- `t` (T): Interpolation factor [0, 1]

**Returns:** (T) The interpolated value

---

### `spatial::inverse_lerp`

```c
T spatial::inverse_lerp(T a, T b, T value);
```

Computes the inverse lerp (finds t given a, b, and value)

@tparam T The value type

**Parameters:**
- `a` (T): Start value
- `b` (T): End value
- `value` (T): The value to find t for

**Returns:** (T) The interpolation factor

---

### `spatial::remap`

```c
T spatial::remap(T value, T in_min, T in_max, T out_min, T out_max);
```

Remaps a value from one range to another

@tparam T The value type

**Parameters:**
- `value` (T): The input value
- `in_min` (T): Input range minimum
- `in_max` (T): Input range maximum
- `out_min` (T): Output range minimum
- `out_max` (T): Output range maximum

**Returns:** (T) The remapped value

---

### `spatial::smoothstep`

```c
T spatial::smoothstep(T a, T b, T t);
```

Smoothly interpolates between two values using smoothstep

@tparam T The value type

**Parameters:**
- `a` (T): Start value
- `b` (T): End value
- `t` (T): Interpolation factor [0, 1]

**Returns:** (T) The smoothly interpolated value

---

