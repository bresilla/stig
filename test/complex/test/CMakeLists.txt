add_executable(test_vectors test_vectors.cpp)
target_link_libraries(test_vectors PRIVATE spatial)
add_test(NAME test_vectors COMMAND test_vectors)

add_executable(test_shapes test_shapes.cpp)
target_link_libraries(test_shapes PRIVATE spatial)
add_test(NAME test_shapes COMMAND test_shapes)
