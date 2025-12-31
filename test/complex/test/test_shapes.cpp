/**
 * @file test_shapes.cpp
 * @brief Unit tests for Shape classes
 */

#include <spatial/shapes.hpp>
#include <cassert>
#include <cmath>
#include <iostream>

using namespace spatial;

void test_circle() {
    Circle<f64> c{Point2d{0.0, 0.0}, 5.0};
    
    // Area = π * r²
    f64 expected_area = constants::PI * 25.0;
    assert(std::abs(c.area() - expected_area) < constants::EPSILON);
    
    // Perimeter = 2 * π * r
    f64 expected_perim = constants::TWO_PI * 5.0;
    assert(std::abs(c.perimeter() - expected_perim) < constants::EPSILON);
    
    // Contains
    assert(c.contains(Point2d{0.0, 0.0}));  // Center
    assert(c.contains(Point2d{3.0, 4.0}));  // On boundary (3² + 4² = 25)
    assert(!c.contains(Point2d{4.0, 4.0})); // Outside
    
    std::cout << "  circle: PASS\n";
}

void test_rectangle() {
    Rectangle<f64> r{Point2d{5.0, 5.0}, 10.0, 6.0};
    
    assert(r.area() == 60.0);
    assert(r.perimeter() == 32.0);
    
    assert(r.contains(Point2d{5.0, 5.0}));   // Center
    assert(r.contains(Point2d{0.0, 2.0}));   // Corner
    assert(!r.contains(Point2d{-1.0, 5.0})); // Outside
    
    auto corners = r.corners();
    assert(corners.size() == 4);
    
    std::cout << "  rectangle: PASS\n";
}

void test_triangle() {
    Triangle<f64> t{
        Point2d{0.0, 0.0},
        Point2d{4.0, 0.0},
        Point2d{0.0, 3.0}
    };
    
    // Area = 0.5 * base * height = 0.5 * 4 * 3 = 6
    assert(std::abs(t.area() - 6.0) < constants::EPSILON);
    
    // Contains
    assert(t.contains(Point2d{1.0, 1.0}));   // Inside
    assert(!t.contains(Point2d{3.0, 3.0})); // Outside
    
    // Centroid
    auto c = t.centroid();
    assert(std::abs(c.x() - 4.0/3.0) < constants::EPSILON);
    assert(std::abs(c.y() - 1.0) < constants::EPSILON);
    
    std::cout << "  triangle: PASS\n";
}

void test_polygon() {
    // Square as polygon
    Polygon<f64> square{{
        Point2d{0.0, 0.0},
        Point2d{2.0, 0.0},
        Point2d{2.0, 2.0},
        Point2d{0.0, 2.0}
    }};
    
    assert(std::abs(square.area() - 4.0) < constants::EPSILON);
    assert(square.is_convex());
    assert(square.contains(Point2d{1.0, 1.0}));
    
    std::cout << "  polygon: PASS\n";
}

void test_aabb() {
    AABB<f64> box{Point2d{0.0, 0.0}, Point2d{10.0, 10.0}};
    
    assert(box.width() == 10.0);
    assert(box.height() == 10.0);
    assert(box.area() == 100.0);
    
    assert(box.contains(Point2d{5.0, 5.0}));
    assert(!box.contains(Point2d{15.0, 5.0}));
    
    AABB<f64> other{Point2d{5.0, 5.0}, Point2d{15.0, 15.0}};
    assert(box.overlaps(other));
    
    std::cout << "  aabb: PASS\n";
}

int main() {
    std::cout << "Running shape tests...\n";
    
    test_circle();
    test_rectangle();
    test_triangle();
    test_polygon();
    test_aabb();
    
    std::cout << "All shape tests passed!\n";
    return 0;
}
