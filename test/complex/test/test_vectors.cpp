/**
 * @file test_vectors.cpp
 * @brief Unit tests for Vector classes
 */

#include <spatial/vector.hpp>
#include <cassert>
#include <cmath>
#include <iostream>

using namespace spatial;

void test_vec2_construction() {
    Vec2d v1;
    assert(v1.x() == 0.0 && v1.y() == 0.0);
    
    Vec2d v2{3.0, 4.0};
    assert(v2.x() == 3.0 && v2.y() == 4.0);
    
    std::cout << "  vec2_construction: PASS\n";
}

void test_vec2_operations() {
    Vec2d a{3.0, 4.0};
    Vec2d b{1.0, 2.0};
    
    auto sum = a + b;
    assert(sum[0] == 4.0 && sum[1] == 6.0);
    
    auto diff = a - b;
    assert(diff[0] == 2.0 && diff[1] == 2.0);
    
    auto scaled = a * 2.0;
    assert(scaled[0] == 6.0 && scaled[1] == 8.0);
    
    std::cout << "  vec2_operations: PASS\n";
}

void test_vec2_magnitude() {
    Vec2d v{3.0, 4.0};
    assert(v.magnitude() == 5.0);
    assert(v.magnitude_squared() == 25.0);
    
    auto normalized = v.normalized();
    assert(std::abs(normalized.magnitude() - 1.0) < constants::EPSILON);
    
    std::cout << "  vec2_magnitude: PASS\n";
}

void test_vec2_dot_cross() {
    Vec2d a{1.0, 0.0};
    Vec2d b{0.0, 1.0};
    
    assert(a.dot(b) == 0.0);  // Perpendicular
    assert(a.cross(b) == 1.0);  // CCW
    
    Vec2d c{1.0, 1.0};
    assert(a.dot(c) == 1.0);
    
    std::cout << "  vec2_dot_cross: PASS\n";
}

void test_vec3_cross() {
    Vec3d x = Vec3d::unit_x();
    Vec3d y = Vec3d::unit_y();
    Vec3d z = x.cross(y);
    
    assert(z.x() == 0.0 && z.y() == 0.0 && z.z() == 1.0);
    
    std::cout << "  vec3_cross: PASS\n";
}

int main() {
    std::cout << "Running vector tests...\n";
    
    test_vec2_construction();
    test_vec2_operations();
    test_vec2_magnitude();
    test_vec2_dot_cross();
    test_vec3_cross();
    
    std::cout << "All vector tests passed!\n";
    return 0;
}
