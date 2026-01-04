# FindStig.cmake
# ---------------
# Finds the Stig documentation generator
#
# This module defines:
#   STIG_FOUND          - True if stig is found
#   STIG_EXECUTABLE     - Path to the stig executable
#   STIG_VERSION        - Version of stig
#   stig_add_docs()     - Function to add documentation targets
#
# Usage:
#   find_package(Stig REQUIRED)
#   stig_add_docs(my_docs
#       SOURCES include/*.hpp src/*.hpp
#       OUTPUT ${CMAKE_BINARY_DIR}/docs
#       FORMAT mdbook
#       TITLE "My Library API"
#       CONFIG ${CMAKE_SOURCE_DIR}/stig.toml
#   )

# Find the stig executable
find_program(STIG_EXECUTABLE
    NAMES stig
    HINTS
        ${STIG_ROOT}
        $ENV{STIG_ROOT}
        ${CMAKE_INSTALL_PREFIX}
    PATH_SUFFIXES bin
    DOC "Path to the stig documentation generator"
)

# Get version if executable is found
if(STIG_EXECUTABLE)
    execute_process(
        COMMAND ${STIG_EXECUTABLE} --version
        OUTPUT_VARIABLE STIG_VERSION_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    
    # Extract version number (format: "stig 0.1.0")
    if(STIG_VERSION_OUTPUT MATCHES "stig ([0-9]+\\.[0-9]+\\.[0-9]+)")
        set(STIG_VERSION ${CMAKE_MATCH_1})
    else()
        set(STIG_VERSION "unknown")
    endif()
endif()

# Handle standard find_package arguments
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Stig
    REQUIRED_VARS STIG_EXECUTABLE
    VERSION_VAR STIG_VERSION
)

# Function to add documentation generation target
function(stig_add_docs TARGET_NAME)
    if(NOT STIG_FOUND)
        message(FATAL_ERROR "stig_add_docs: Stig not found. Please install stig or set STIG_ROOT.")
    endif()
    
    # Parse arguments
    cmake_parse_arguments(STIG
        "FORCE;WATCH"                           # Options
        "OUTPUT;FORMAT;TITLE;CONFIG"            # Single-value keywords
        "SOURCES;DEPENDS"                       # Multi-value keywords
        ${ARGN}
    )
    
    # Validate required arguments
    if(NOT STIG_SOURCES)
        message(FATAL_ERROR "stig_add_docs: SOURCES argument is required")
    endif()
    
    # Set defaults
    if(NOT STIG_OUTPUT)
        set(STIG_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/docs")
    endif()
    
    if(NOT STIG_FORMAT)
        set(STIG_FORMAT "mdbook")
    endif()
    
    if(NOT STIG_TITLE)
        set(STIG_TITLE "API Documentation")
    endif()
    
    # Expand glob patterns in SOURCES
    set(STIG_SOURCE_FILES "")
    foreach(pattern ${STIG_SOURCES})
        # Check if pattern contains wildcards
        if(pattern MATCHES "[*?]")
            file(GLOB_RECURSE matched_files ${pattern})
            list(APPEND STIG_SOURCE_FILES ${matched_files})
        else()
            list(APPEND STIG_SOURCE_FILES ${pattern})
        endif()
    endforeach()
    
    # Remove duplicates
    list(REMOVE_DUPLICATES STIG_SOURCE_FILES)
    
    # Build command arguments
    set(STIG_ARGS "")
    list(APPEND STIG_ARGS ${STIG_SOURCE_FILES})
    list(APPEND STIG_ARGS -f ${STIG_FORMAT})
    list(APPEND STIG_ARGS -o ${STIG_OUTPUT})
    list(APPEND STIG_ARGS --title "${STIG_TITLE}")
    
    if(STIG_CONFIG)
        list(APPEND STIG_ARGS -c ${STIG_CONFIG})
    endif()
    
    if(STIG_FORCE)
        list(APPEND STIG_ARGS --force)
    endif()
    
    # Create custom target
    add_custom_target(${TARGET_NAME}
        COMMAND ${STIG_EXECUTABLE} ${STIG_ARGS}
        DEPENDS ${STIG_SOURCE_FILES} ${STIG_DEPENDS}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "Generating ${STIG_FORMAT} documentation with stig"
        VERBATIM
    )
    
    # Set target properties
    set_target_properties(${TARGET_NAME} PROPERTIES
        STIG_OUTPUT_DIR ${STIG_OUTPUT}
        STIG_FORMAT ${STIG_FORMAT}
    )
    
    # Add watch target if requested
    if(STIG_WATCH)
        add_custom_target(${TARGET_NAME}_watch
            COMMAND ${STIG_EXECUTABLE} ${STIG_ARGS} --watch
            DEPENDS ${STIG_SOURCE_FILES} ${STIG_DEPENDS}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            COMMENT "Watching for changes and regenerating documentation"
            VERBATIM
        )
    endif()
    
    # Print configuration
    message(STATUS "Stig documentation target '${TARGET_NAME}' configured:")
    message(STATUS "  Sources: ${STIG_SOURCE_FILES}")
    message(STATUS "  Output: ${STIG_OUTPUT}")
    message(STATUS "  Format: ${STIG_FORMAT}")
    message(STATUS "  Title: ${STIG_TITLE}")
endfunction()

# Function to add stig test target
# This creates a test executable using stig's test framework
function(stig_add_tests TARGET_NAME)
    if(NOT STIG_FOUND)
        message(FATAL_ERROR "stig_add_tests: Stig not found. Please install stig or set STIG_ROOT.")
    endif()
    
    # Parse arguments
    cmake_parse_arguments(STIG_TEST
        ""                                          # Options
        "WORKING_DIRECTORY"                         # Single-value keywords
        "SOURCES;INCLUDE_DIRS;LIBRARIES;DEPENDS"    # Multi-value keywords
        ${ARGN}
    )
    
    # Validate required arguments
    if(NOT STIG_TEST_SOURCES)
        message(FATAL_ERROR "stig_add_tests: SOURCES argument is required")
    endif()
    
    # Set defaults
    if(NOT STIG_TEST_WORKING_DIRECTORY)
        set(STIG_TEST_WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
    endif()
    
    # Check if stig_test.h exists, if not generate it
    set(STIG_TEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    set(STIG_TEST_HEADER "${STIG_TEST_DIR}/stig_test.h")
    set(STIG_TEST_MAIN "${STIG_TEST_DIR}/stig_main.cpp")
    
    if(NOT EXISTS ${STIG_TEST_HEADER})
        message(STATUS "Generating stig_test.h...")
        execute_process(
            COMMAND ${STIG_EXECUTABLE} init --force
            WORKING_DIRECTORY ${STIG_TEST_DIR}
            RESULT_VARIABLE STIG_INIT_RESULT
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(NOT STIG_INIT_RESULT EQUAL 0)
            message(WARNING "Failed to generate stig test infrastructure. Run 'stig init' manually.")
        endif()
    endif()
    
    # Expand glob patterns in SOURCES
    set(STIG_TEST_SOURCE_FILES "")
    foreach(pattern ${STIG_TEST_SOURCES})
        if(pattern MATCHES "[*?]")
            file(GLOB_RECURSE matched_files ${pattern})
            list(APPEND STIG_TEST_SOURCE_FILES ${matched_files})
        else()
            list(APPEND STIG_TEST_SOURCE_FILES ${pattern})
        endif()
    endforeach()
    
    # Remove duplicates
    list(REMOVE_DUPLICATES STIG_TEST_SOURCE_FILES)
    
    # Each test file is standalone (includes main via stig_test.h)
    # Create a test executable for each source file
    set(ALL_TEST_TARGETS "")
    message(STATUS "Stig test target '${TARGET_NAME}' configured:")
    
    foreach(test_source ${STIG_TEST_SOURCE_FILES})
        get_filename_component(test_name ${test_source} NAME_WE)
        set(test_target "${TARGET_NAME}_${test_name}")
        
        add_executable(${test_target} ${test_source})
        
        # Add include directories
        target_include_directories(${test_target} PRIVATE ${STIG_TEST_DIR})
        if(STIG_TEST_INCLUDE_DIRS)
            target_include_directories(${test_target} PRIVATE ${STIG_TEST_INCLUDE_DIRS})
        endif()
        
        # Link libraries
        if(STIG_TEST_LIBRARIES)
            target_link_libraries(${test_target} PRIVATE ${STIG_TEST_LIBRARIES})
        endif()
        
        # Add dependencies
        if(STIG_TEST_DEPENDS)
            add_dependencies(${test_target} ${STIG_TEST_DEPENDS})
        endif()
        
        # Register with CTest
        add_test(
            NAME ${test_target}
            COMMAND ${test_target}
            WORKING_DIRECTORY ${STIG_TEST_WORKING_DIRECTORY}
        )
        
        list(APPEND ALL_TEST_TARGETS ${test_target})
        message(STATUS "  Test: ${test_target}")
    endforeach()
    
    # Create a meta-target that builds all test executables
    add_custom_target(${TARGET_NAME}
        DEPENDS ${ALL_TEST_TARGETS}
        COMMENT "Building all stig tests for ${TARGET_NAME}"
    )
endfunction()

# Function to run stig test command (compile and run via stig)
# This uses stig's built-in test runner instead of CMake's compilation
function(stig_run_tests TARGET_NAME)
    if(NOT STIG_FOUND)
        message(FATAL_ERROR "stig_run_tests: Stig not found. Please install stig or set STIG_ROOT.")
    endif()
    
    # Parse arguments
    cmake_parse_arguments(STIG_RUN
        ""                              # Options
        "CONFIG;WORKING_DIRECTORY"      # Single-value keywords
        "SOURCES"                       # Multi-value keywords
        ${ARGN}
    )
    
    # Set defaults
    if(NOT STIG_RUN_WORKING_DIRECTORY)
        set(STIG_RUN_WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
    endif()
    
    # Build command arguments
    set(STIG_ARGS "test")
    
    if(STIG_RUN_CONFIG)
        list(APPEND STIG_ARGS -c ${STIG_RUN_CONFIG})
    endif()
    
    if(STIG_RUN_SOURCES)
        list(APPEND STIG_ARGS ${STIG_RUN_SOURCES})
    endif()
    
    # Create custom target to run tests via stig
    add_custom_target(${TARGET_NAME}
        COMMAND ${STIG_EXECUTABLE} ${STIG_ARGS}
        WORKING_DIRECTORY ${STIG_RUN_WORKING_DIRECTORY}
        COMMENT "Running tests with stig"
        VERBATIM
    )
    
    # Also register as CTest test
    add_test(
        NAME ${TARGET_NAME}
        COMMAND ${STIG_EXECUTABLE} ${STIG_ARGS}
        WORKING_DIRECTORY ${STIG_RUN_WORKING_DIRECTORY}
    )
    
    message(STATUS "Stig run-tests target '${TARGET_NAME}' configured")
endfunction()

# Mark variables as advanced
mark_as_advanced(STIG_EXECUTABLE)
