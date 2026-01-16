/**
 * @file test_stig_shapes.cpp
 * @brief Unit tests for Shape classes using stig test framework
 */

#include "stig_test.h"
#include <spatial/shapes.hpp>
#include <cmath>

using namespace spatial;

STIG_TEST(test_circle_area) {
    Circle<f64> c{Point2d{0.0, 0.0}, 5.0};
    
    // Area = pi * r^2
    f64 expected_area = constants::PI * 25.0;
    STIG_CHECK(std::abs(c.area() - expected_area) < constants::EPSILON);
}

STIG_TEST(test_circle_perimeter) {
    Circle<f64> c{Point2d{0.0, 0.0}, 5.0};
    
    // Perimeter = 2 * pi * r
    f64 expected_perim = constants::TWO_PI * 5.0;
    STIG_CHECK(std::abs(c.perimeter() - expected_perim) < constants::EPSILON);
}

STIG_TEST(test_circle_contains) {
    Circle<f64> c{Point2d{0.0, 0.0}, 5.0};
    
    STIG_CHECK(c.contains(Point2d{0.0, 0.0}));   // Center
    STIG_CHECK(c.contains(Point2d{3.0, 4.0}));   // On boundary (3^2 + 4^2 = 25)
    STIG_CHECK(!c.contains(Point2d{4.0, 4.0}));  // Outside
}

STIG_TEST(test_rectangle_area_perimeter) {
    Rectangle<f64> r{Point2d{5.0, 5.0}, 10.0, 6.0};
    
    STIG_CHECK_EQ(r.area(), 60.0);
    STIG_CHECK_EQ(r.perimeter(), 32.0);
}

STIG_TEST(test_rectangle_contains) {
    Rectangle<f64> r{Point2d{5.0, 5.0}, 10.0, 6.0};
    
    STIG_CHECK(r.contains(Point2d{5.0, 5.0}));    // Center
    STIG_CHECK(r.contains(Point2d{0.0, 2.0}));    // Corner
    STIG_CHECK(!r.contains(Point2d{-1.0, 5.0}));  // Outside
}

STIG_TEST(test_rectangle_corners) {
    Rectangle<f64> r{Point2d{5.0, 5.0}, 10.0, 6.0};
    auto corners = r.corners();
    STIG_CHECK_EQ(corners.size(), 4u);
}

STIG_TEST(test_triangle_area) {
    Triangle<f64> t{
        Point2d{0.0, 0.0},
        Point2d{4.0, 0.0},
        Point2d{0.0, 3.0}
    };
    
    // Area = 0.5 * base * height = 0.5 * 4 * 3 = 6
    STIG_CHECK(std::abs(t.area() - 6.0) < constants::EPSILON);
}

STIG_TEST(test_triangle_contains) {
    Triangle<f64> t{
        Point2d{0.0, 0.0},
        Point2d{4.0, 0.0},
        Point2d{0.0, 3.0}
    };
    
    STIG_CHECK(t.contains(Point2d{1.0, 1.0}));    // Inside
    STIG_CHECK(!t.contains(Point2d{3.0, 3.0}));   // Outside
}

STIG_TEST(test_triangle_centroid) {
    Triangle<f64> t{
        Point2d{0.0, 0.0},
        Point2d{4.0, 0.0},
        Point2d{0.0, 3.0}
    };
    
    auto c = t.centroid();
    STIG_CHECK(std::abs(c.x() - 4.0/3.0) < constants::EPSILON);
    STIG_CHECK(std::abs(c.y() - 1.0) < constants::EPSILON);
}

STIG_TEST(test_polygon_square) {
    // Square as polygon
    Polygon<f64> square{{
        Point2d{0.0, 0.0},
        Point2d{2.0, 0.0},
        Point2d{2.0, 2.0},
        Point2d{0.0, 2.0}
    }};
    
    STIG_CHECK(std::abs(square.area() - 4.0) < constants::EPSILON);
    STIG_CHECK(square.is_convex());
    STIG_CHECK(square.contains(Point2d{1.0, 1.0}));
}

STIG_TEST(test_aabb_dimensions) {
    AABB<f64> box{Point2d{0.0, 0.0}, Point2d{10.0, 10.0}};
    
    STIG_CHECK_EQ(box.width(), 10.0);
    STIG_CHECK_EQ(box.height(), 10.0);
    STIG_CHECK_EQ(box.area(), 100.0);
}

STIG_TEST(test_aabb_contains) {
    AABB<f64> box{Point2d{0.0, 0.0}, Point2d{10.0, 10.0}};
    
    STIG_CHECK(box.contains(Point2d{5.0, 5.0}));
    STIG_CHECK(!box.contains(Point2d{15.0, 5.0}));
}

STIG_TEST(test_aabb_overlaps) {
    AABB<f64> box{Point2d{0.0, 0.0}, Point2d{10.0, 10.0}};
    AABB<f64> other{Point2d{5.0, 5.0}, Point2d{15.0, 15.0}};
    
    STIG_CHECK(box.overlaps(other));
}
