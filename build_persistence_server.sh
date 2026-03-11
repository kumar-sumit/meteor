#!/bin/bash
# **METEOR REDIS-COMPATIBLE SERVER WITH PERSISTENCE - BUILD SCRIPT**
# Compiles meteor_redis_client_compatible_with_persistence.cpp with full optimizations

set -e  # Exit on error

echo "🚀 Building Meteor Redis-Compatible Server with Persistence..."
echo "=================================================="

# Check for required libraries
echo "📦 Checking dependencies..."
MISSING_DEPS=()

# Check for liburing
if ! ldconfig -p | grep -q liburing; then
    MISSING_DEPS+=("liburing")
fi

# Check for liblz4
if ! ldconfig -p | grep -q liblz4; then
    MISSING_DEPS+=("liblz4")
fi

# Check for Boost.Fibers
if [ ! -d "/usr/include/boost/fiber" ] && [ ! -d "/usr/local/include/boost/fiber" ]; then
    MISSING_DEPS+=("libboost-fiber-dev")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install with:"
    echo "sudo apt-get update"
    echo "sudo apt-get install -y liburing-dev liblz4-dev libboost-fiber-dev libboost-context-dev"
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Build configuration
CXX=g++
SOURCE_FILE="cpp/meteor_redis_client_compatible_with_persistence.cpp"
OUTPUT_FILE="meteor_redis_persistent"
HEADER_FILE="cpp/meteor_persistence_module.hpp"

# Check if source files exist
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Source file not found: $SOURCE_FILE"
    exit 1
fi

if [ ! -f "$HEADER_FILE" ]; then
    echo "❌ Header file not found: $HEADER_FILE"
    exit 1
fi

echo "📝 Source: $SOURCE_FILE"
echo "📝 Header: $HEADER_FILE"
echo "📝 Output: $OUTPUT_FILE"
echo ""

# Compilation flags
CXXFLAGS=(
    -std=c++20
    -O3
    -march=native
    -mtune=native
    -flto
    -fno-omit-frame-pointer
    -pthread
)

# AVX/AVX2/FMA flags (AVX-512 removed for broader compatibility)
SIMD_FLAGS=(
    -mavx
    -mavx2
    -mfma
)

# Warning flags
WARNING_FLAGS=(
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-sign-compare
)

# Library flags
LIB_FLAGS=(
    -luring
    -llz4
    -lboost_fiber
    -lboost_context
    -lpthread
)

# Include paths
INCLUDE_FLAGS=(
    -I.
    -Icpp
)

# Full compilation command
echo "🔨 Compiling..."
echo ""

COMPILE_CMD=(
    $CXX
    "${CXXFLAGS[@]}"
    "${SIMD_FLAGS[@]}"
    "${WARNING_FLAGS[@]}"
    "${INCLUDE_FLAGS[@]}"
    "$SOURCE_FILE"
    -o "$OUTPUT_FILE"
    "${LIB_FLAGS[@]}"
)

echo "${COMPILE_CMD[*]}"
echo ""

"${COMPILE_CMD[@]}"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo "=================================================="
    echo ""
    echo "📊 Binary Information:"
    ls -lh "$OUTPUT_FILE"
    echo ""
    echo "🚀 Run with persistence enabled:"
    echo ""
    echo "  # Basic usage (persistence enabled):"
    echo "  ./$OUTPUT_FILE -p 6379 -c 4 -s 4 -P 1"
    echo ""
    echo "  # Custom RDB/AOF paths:"
    echo "  ./$OUTPUT_FILE -p 6379 -c 4 -s 4 -P 1 -R ./snapshots -A ./aof"
    echo ""
    echo "  # Tune snapshot interval and operations:"
    echo "  ./$OUTPUT_FILE -p 6379 -c 4 -s 4 -P 1 -I 60 -O 50000"
    echo ""
    echo "  # Set AOF fsync policy (0=never, 1=always, 2=everysec):"
    echo "  ./$OUTPUT_FILE -p 6379 -c 4 -s 4 -P 1 -F 2"
    echo ""
    echo "  # Without persistence (default):"
    echo "  ./$OUTPUT_FILE -p 6379 -c 4 -s 4"
    echo ""
    echo "📝 For more options, see:"
    echo "  ./$OUTPUT_FILE --help"
    echo "  or check PERSISTENCE_IMPLEMENTATION_GUIDE.md"
    echo ""
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi



