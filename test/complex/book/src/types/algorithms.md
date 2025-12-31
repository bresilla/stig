# include/spatial/algorithms.hpp

## Structures

### `spatial::LineIntersection`

```c
struct spatial::LineIntersection {
    bool intersects;
    unknown point;
    T t;
    T u;
};
```

Result of a line-line intersection test

**Fields:**
- `intersects` (bool): Whether the lines intersect
- `point` (unknown): The intersection point (if intersects)
- `t` (T): Parameter along first line [0,1] if segment
- `u` (T): Parameter along second line [0,1] if segment

---

