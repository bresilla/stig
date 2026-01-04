# Option 1: Use stig_add_tests() - CMake compiles the tests
# Each test file is standalone (stig_test.h includes main())
if(STIG_FOUND)
    stig_add_tests(spatial_tests
        SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/test_stig_shapes.cpp
        INCLUDE_DIRS
            ${CMAKE_SOURCE_DIR}/include
        LIBRARIES
            spatial
    )
else()
    # Fallback: compile tests manually without stig integration
    add_executable(spatial_tests_test_stig_shapes test_stig_shapes.cpp)
    target_include_directories(spatial_tests_test_stig_shapes PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(spatial_tests_test_stig_shapes PRIVATE spatial)
    add_test(NAME spatial_tests_test_stig_shapes COMMAND spatial_tests_test_stig_shapes)
endif()

# Option 2: Use stig_run_tests() - stig compiles and runs tests
# Uncomment to use stig's built-in test runner instead
# if(STIG_FOUND)
#     stig_run_tests(stig_spatial_tests
#         CONFIG ${CMAKE_SOURCE_DIR}/stig.toml
#         WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
#     )
# endif()
