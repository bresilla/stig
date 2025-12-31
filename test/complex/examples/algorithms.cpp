/**
 * @file algorithms.cpp
 * @brief Example demonstrating spatial algorithms
 * 
 * Shows distance calculations, intersection tests, convex hull,
 * and other geometric algorithms.
 */

#include <spatial/algorithms.hpp>
#include <iostream>
#include <iomanip>
#include <vector>

using namespace spatial;

int main() {
    std::cout << std::fixed << std::setprecision(3);
    std::cout << "=== Spatial Library: Algorithms ===\n\n";

    // Distance calculations
    std::cout << "--- Distance Calculations ---\n";
    Point2d p1{0.0, 0.0};
    Point2d p2{3.0, 4.0};
    std::cout << "Distance from (0,0) to (3,4): " << distance(p1, p2) << "\n";

    // Distance to line segment
    Point2d seg_start{0.0, 0.0};
    Point2d seg_end{10.0, 0.0};
    Point2d query{5.0, 3.0};
    std::cout << "Distance from (5,3) to segment [(0,0)-(10,0)]: " 
              << distance_to_segment(query, seg_start, seg_end) << "\n\n";

    // Line segment intersection
    std::cout << "--- Segment Intersection ---\n";
    auto result = segment_intersection(
        Point2d{0.0, 0.0}, Point2d{10.0, 10.0},  // Diagonal line
        Point2d{0.0, 10.0}, Point2d{10.0, 0.0}   // Other diagonal
    );
    if (result.intersects) {
        std::cout << "Segments intersect at: (" << result.point.x() << ", " << result.point.y() << ")\n";
    }

    // Non-intersecting segments
    auto result2 = segment_intersection(
        Point2d{0.0, 0.0}, Point2d{1.0, 1.0},
        Point2d{2.0, 2.0}, Point2d{3.0, 3.0}
    );
    std::cout << "Parallel segments intersect: " << (result2.intersects ? "yes" : "no") << "\n\n";

    // Circle intersection
    std::cout << "--- Circle Intersection ---\n";
    Circle<f64> c1{Point2d{0.0, 0.0}, 5.0};
    Circle<f64> c2{Point2d{7.0, 0.0}, 3.0};
    Circle<f64> c3{Point2d{20.0, 0.0}, 2.0};
    
    std::cout << "Circle1 (r=5) and Circle2 (r=3, at x=7): " 
              << (circles_intersect(c1, c2) ? "intersect" : "don't intersect") << "\n";
    std::cout << "Circle1 (r=5) and Circle3 (r=2, at x=20): " 
              << (circles_intersect(c1, c3) ? "intersect" : "don't intersect") << "\n\n";

    // Convex hull
    std::cout << "--- Convex Hull ---\n";
    std::vector<Point2d> points = {
        {0.0, 0.0}, {1.0, 1.0}, {2.0, 0.0}, {1.0, 2.0},
        {0.5, 0.5}, {1.5, 0.5}, {1.0, 0.3}  // Interior points
    };
    std::cout << "Input: " << points.size() << " points\n";
    
    auto hull = convex_hull(points);
    std::cout << "Convex hull has " << hull.vertex_count() << " vertices:\n";
    for (usize i = 0; i < hull.vertex_count(); ++i) {
        const auto& v = hull.vertex(i);
        std::cout << "  (" << v.x() << ", " << v.y() << ")\n";
    }
    std::cout << "\n";

    // Angle utilities
    std::cout << "--- Angle Utilities ---\n";
    Vec2d v1{1.0, 0.0};
    Vec2d v2{0.0, 1.0};
    std::cout << "Angle between (1,0) and (0,1): " 
              << rad_to_deg(angle_between(v1, v2)) << " degrees\n";
    
    Vec2d v3{1.0, 1.0};
    std::cout << "Angle between (1,0) and (1,1): " 
              << rad_to_deg(angle_between(v1, v3)) << " degrees\n\n";

    // Interpolation
    std::cout << "--- Interpolation ---\n";
    Point2d start{0.0, 0.0};
    Point2d end{10.0, 10.0};
    
    std::cout << "Lerp from (0,0) to (10,10):\n";
    for (f64 t = 0.0; t <= 1.0; t += 0.25) {
        auto p = start.lerp(end, t);
        std::cout << "  t=" << t << ": (" << p.x() << ", " << p.y() << ")\n";
    }

    // Smoothstep
    std::cout << "\nSmoothstep vs Linear:\n";
    for (f64 t = 0.0; t <= 1.0; t += 0.25) {
        f64 linear = lerp(0.0, 10.0, t);
        f64 smooth = smoothstep(0.0, 10.0, t);
        std::cout << "  t=" << t << ": linear=" << linear << ", smooth=" << smooth << "\n";
    }

    return 0;
}
