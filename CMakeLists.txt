cmake_minimum_required(VERSION 3.16)
project(GarudaDB VERSION 1.0.0 LANGUAGES CXX)

# Set C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Compiler flags
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=native")
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")

# Find required packages
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)

# Check for liburing
pkg_check_modules(LIBURING liburing)

# Check for mimalloc
find_path(MIMALLOC_INCLUDE_DIR mimalloc.h)
find_library(MIMALLOC_LIBRARY mimalloc)

# Include directories
include_directories(src)

# Source files
set(GARUDA_CORE_SOURCES
    src/core/dragonfly_core.cpp
    src/core/dashtable.cpp
    src/core/vll_algorithm.cpp
    src/core/fiber_scheduler.cpp
    src/core/shard_manager.cpp
    src/network/dragonfly_connection.cpp
    src/network/connection_manager.cpp
    src/protocol/resp_parser.cpp
    src/commands/command_processor.cpp
    src/commands/redis_commands.cpp
    src/memory/memory_manager.cpp
    src/memory/lfru_cache.cpp
    src/utils/string_utils.cpp
    src/utils/hash_utils.cpp
)

# Create core library
add_library(garuda_core STATIC ${GARUDA_CORE_SOURCES})

# Link libraries
target_link_libraries(garuda_core Threads::Threads)

# Link liburing if available
if(LIBURING_FOUND)
    target_include_directories(garuda_core PRIVATE ${LIBURING_INCLUDE_DIRS})
    target_link_libraries(garuda_core ${LIBURING_LIBRARIES})
    target_compile_definitions(garuda_core PRIVATE HAVE_LIBURING=1)
    message(STATUS "Building with io_uring support")
else()
    message(WARNING "liburing not found - building without io_uring support")
endif()

# Link mimalloc if available
if(MIMALLOC_INCLUDE_DIR AND MIMALLOC_LIBRARY)
    target_include_directories(garuda_core PRIVATE ${MIMALLOC_INCLUDE_DIR})
    target_link_libraries(garuda_core ${MIMALLOC_LIBRARY})
    target_compile_definitions(garuda_core PRIVATE HAVE_MIMALLOC=1)
    message(STATUS "Building with mimalloc support")
else()
    message(WARNING "mimalloc not found - using system allocator")
endif()

# Main Dragonfly server executable (NEW - with proper network layer)
add_executable(dragonfly-server src/dragonfly_server.cpp)
target_link_libraries(dragonfly-server garuda_core)

# Legacy server executable (for comparison)
add_executable(garuda-server src/main.cpp)
target_link_libraries(garuda-server garuda_core)

# Benchmark executable
add_executable(garuda-benchmark src/benchmark/benchmark_main.cpp)
target_link_libraries(garuda-benchmark garuda_core)

# Test executable
add_executable(garuda-test src/test/test_main.cpp)
target_link_libraries(garuda-test garuda_core)

# Simple test executable
add_executable(garuda-simple-test simple_garuda_test.cpp)
target_link_libraries(garuda-simple-test garuda_core)

# Install targets
install(TARGETS dragonfly-server garuda-server garuda-benchmark garuda-test DESTINATION bin)

message(STATUS "GarudaDB - Authentic Dragonfly Architecture Implementation")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")

if(LIBURING_FOUND)
    message(STATUS "io_uring: ${LIBURING_VERSION}")
endif()

if(MIMALLOC_INCLUDE_DIR AND MIMALLOC_LIBRARY)
    message(STATUS "mimalloc: enabled")
endif()