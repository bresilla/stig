/**
 * @file test_group.hpp
 * @brief Test file for @group command
 */

#pragma once

namespace group_test {

/// @group getters Getter Functions
/// @brief Gets the X coordinate
/// @return The X value
int get_x();

/// @group getters
/// @brief Gets the Y coordinate
/// @return The Y value
int get_y();

/// @group getters
/// @brief Gets the Z coordinate
/// @return The Z value
int get_z();

/// @group setters Setter Functions
/// @brief Sets the X coordinate
/// @param x The new X value
void set_x(int x);

/// @group setters
/// @brief Sets the Y coordinate
/// @param y The new Y value
void set_y(int y);

/// @brief A standalone function not in any group
/// @param value The input value
/// @return The processed value
int standalone_function(int value);

/// @group utilities Utility Functions
/// @brief Resets all coordinates to zero
void reset();

/// @brief Another standalone function
void another_standalone();

} // namespace group_test
