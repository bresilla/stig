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

# Mark variables as advanced
mark_as_advanced(STIG_EXECUTABLE)
