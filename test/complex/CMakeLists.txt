cmake_minimum_required(VERSION 3.16)
project(spatial VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Header-only library
add_library(spatial INTERFACE)
target_include_directories(spatial INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Examples
option(SPATIAL_BUILD_EXAMPLES "Build examples" ON)
if(SPATIAL_BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()

# Tests
option(SPATIAL_BUILD_TESTS "Build tests" ON)
if(SPATIAL_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()
