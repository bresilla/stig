add_executable(basic_shapes basic_shapes.cpp)
target_link_libraries(basic_shapes PRIVATE spatial)

add_executable(transforms transforms.cpp)
target_link_libraries(transforms PRIVATE spatial)

add_executable(algorithms algorithms.cpp)
target_link_libraries(algorithms PRIVATE spatial)
