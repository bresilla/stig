/**
 * @file transforms.cpp
 * @brief Example demonstrating 2D transformations
 * 
 * Shows how to use Transform2 to rotate and translate points and shapes.
 */

#include <spatial/geometry.hpp>
#include <spatial/shapes.hpp>
#include <iostream>
#include <iomanip>

using namespace spatial;

int main() {
    std::cout << std::fixed << std::setprecision(3);
    std::cout << "=== Spatial Library: Transformations ===\n\n";

    // Create a point
    Point2d p{1.0, 0.0};
    std::cout << "Original point: (" << p.x() << ", " << p.y() << ")\n\n";

    // Rotate 90 degrees (π/2 radians)
    Transform2d rot90 = Transform2d::from_rotation(constants::HALF_PI);
    Point2d p_rotated = rot90.apply(p);
    std::cout << "After 90° rotation: (" << p_rotated.x() << ", " << p_rotated.y() << ")\n";

    // Translate by (5, 3)
    Transform2d translate = Transform2d::from_translation(Vec2d{5.0, 3.0});
    Point2d p_translated = translate.apply(p);
    std::cout << "After translation (5,3): (" << p_translated.x() << ", " << p_translated.y() << ")\n";

    // Combine: rotate then translate
    Transform2d combined{constants::HALF_PI, Vec2d{5.0, 3.0}};
    Point2d p_combined = combined.apply(p);
    std::cout << "After rotate + translate: (" << p_combined.x() << ", " << p_combined.y() << ")\n\n";

    // Transform a triangle
    Triangle<f64> tri{
        Point2d{0.0, 0.0},
        Point2d{2.0, 0.0},
        Point2d{1.0, 1.0}
    };
    
    std::cout << "Original triangle vertices:\n";
    std::cout << "  A: (" << tri.a().x() << ", " << tri.a().y() << ")\n";
    std::cout << "  B: (" << tri.b().x() << ", " << tri.b().y() << ")\n";
    std::cout << "  C: (" << tri.c().x() << ", " << tri.c().y() << ")\n";

    // Rotate triangle 45 degrees
    Transform2d rot45 = Transform2d::from_rotation(constants::PI / 4.0);
    auto tri_rotated = tri.transformed(rot45);
    
    // Cast to Triangle to access vertices
    auto* tri_ptr = dynamic_cast<Triangle<f64>*>(tri_rotated.get());
    if (tri_ptr) {
        std::cout << "\nAfter 45° rotation:\n";
        std::cout << "  A: (" << tri_ptr->a().x() << ", " << tri_ptr->a().y() << ")\n";
        std::cout << "  B: (" << tri_ptr->b().x() << ", " << tri_ptr->b().y() << ")\n";
        std::cout << "  C: (" << tri_ptr->c().x() << ", " << tri_ptr->c().y() << ")\n";
    }

    // Inverse transform
    std::cout << "\n--- Inverse Transform ---\n";
    Transform2d t{constants::HALF_PI, Vec2d{10.0, 5.0}};
    Point2d original{3.0, 4.0};
    Point2d transformed = t.apply(original);
    Point2d back = t.inverse().apply(transformed);
    
    std::cout << "Original: (" << original.x() << ", " << original.y() << ")\n";
    std::cout << "Transformed: (" << transformed.x() << ", " << transformed.y() << ")\n";
    std::cout << "Back (inverse): (" << back.x() << ", " << back.y() << ")\n";

    return 0;
}
