/**
 * @file basic_shapes.cpp
 * @brief Example demonstrating basic shape usage
 * 
 * Shows how to create and manipulate circles, rectangles,
 * triangles, and polygons.
 */

#include <spatial/shapes.hpp>
#include <iostream>
#include <iomanip>

using namespace spatial;

int main() {
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "=== Spatial Library: Basic Shapes ===\n\n";

    // Create a circle
    Circle<f64> circle{Point2d{0.0, 0.0}, 5.0};
    std::cout << "Circle (center: origin, radius: 5)\n";
    std::cout << "  Area: " << circle.area() << "\n";
    std::cout << "  Perimeter: " << circle.perimeter() << "\n";
    std::cout << "  Contains (3, 4): " << (circle.contains(Point2d{3.0, 4.0}) ? "yes" : "no") << "\n";
    std::cout << "  Contains (4, 4): " << (circle.contains(Point2d{4.0, 4.0}) ? "yes" : "no") << "\n\n";

    // Create a rectangle
    Rectangle<f64> rect{Point2d{5.0, 5.0}, 10.0, 6.0};
    std::cout << "Rectangle (center: (5,5), width: 10, height: 6)\n";
    std::cout << "  Area: " << rect.area() << "\n";
    std::cout << "  Perimeter: " << rect.perimeter() << "\n";
    auto corners = rect.corners();
    std::cout << "  Corners: ";
    for (const auto& c : corners) {
        std::cout << "(" << c.x() << "," << c.y() << ") ";
    }
    std::cout << "\n\n";

    // Create a triangle
    Triangle<f64> tri{
        Point2d{0.0, 0.0},
        Point2d{4.0, 0.0},
        Point2d{2.0, 3.0}
    };
    std::cout << "Triangle (vertices: (0,0), (4,0), (2,3))\n";
    std::cout << "  Area: " << tri.area() << "\n";
    std::cout << "  Perimeter: " << tri.perimeter() << "\n";
    auto centroid = tri.centroid();
    std::cout << "  Centroid: (" << centroid.x() << ", " << centroid.y() << ")\n\n";

    // Create a polygon (pentagon)
    Polygon<f64> pentagon{{
        Point2d{0.0, 0.0},
        Point2d{2.0, 0.0},
        Point2d{3.0, 1.5},
        Point2d{1.0, 3.0},
        Point2d{-1.0, 1.5}
    }};
    std::cout << "Pentagon (5 vertices)\n";
    std::cout << "  Area: " << pentagon.area() << "\n";
    std::cout << "  Perimeter: " << pentagon.perimeter() << "\n";
    std::cout << "  Is convex: " << (pentagon.is_convex() ? "yes" : "no") << "\n\n";

    // Bounding boxes
    std::cout << "Bounding Boxes:\n";
    auto circle_bb = circle.bounding_box();
    std::cout << "  Circle: [(" << circle_bb.min.x() << "," << circle_bb.min.y() 
              << ") to (" << circle_bb.max.x() << "," << circle_bb.max.y() << ")]\n";
    
    auto tri_bb = tri.bounding_box();
    std::cout << "  Triangle: [(" << tri_bb.min.x() << "," << tri_bb.min.y() 
              << ") to (" << tri_bb.max.x() << "," << tri_bb.max.y() << ")]\n";

    return 0;
}
