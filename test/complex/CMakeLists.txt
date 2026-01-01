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

# Documentation with Stig
option(SPATIAL_BUILD_DOCS "Build documentation with stig" ON)
if(SPATIAL_BUILD_DOCS)
    # Add the stig cmake module path
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
    
    # Find stig (optional - only warn if not found)
    find_package(Stig QUIET)
    
    if(STIG_FOUND)
        # Add documentation target
        stig_add_docs(spatial_docs
            SOURCES
                ${CMAKE_CURRENT_SOURCE_DIR}/include/spatial/*.hpp
            OUTPUT ${CMAKE_BINARY_DIR}/docs
            FORMAT mdbook
            TITLE "Spatial Geometry Library"
            CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/stig.toml
            FORCE  # Always rebuild documentation
        )
        
        message(STATUS "Stig documentation target 'spatial_docs' configured")
        message(STATUS "  Build with: cmake --build . --target spatial_docs")
    else()
        message(STATUS "Stig not found - documentation target disabled")
        message(STATUS "  Install stig from: https://github.com/yourusername/stig")
    endif()
endif()

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
