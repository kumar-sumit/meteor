#!/bin/bash

# Meteor C++ Build Script
# High-performance Redis-compatible cache server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE=${BUILD_TYPE:-Release}
NUM_JOBS=${NUM_JOBS:-$(nproc)}
INSTALL_PREFIX=${INSTALL_PREFIX:-/usr/local}
ENABLE_TESTS=${ENABLE_TESTS:-ON}
ENABLE_BENCHMARKS=${ENABLE_BENCHMARKS:-ON}

echo -e "${BLUE}🚀 Meteor C++ Build Script${NC}"
echo -e "${BLUE}============================${NC}"
echo "Build type: $BUILD_TYPE"
echo "Jobs: $NUM_JOBS"
echo "Install prefix: $INSTALL_PREFIX"
echo "Tests: $ENABLE_TESTS"
echo "Benchmarks: $ENABLE_BENCHMARKS"
echo ""

# Check dependencies
echo -e "${YELLOW}📦 Checking dependencies...${NC}"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✅ $1 found${NC}"
        return 0
    fi
}

# Required tools
check_command cmake || exit 1
check_command g++ || check_command clang++ || exit 1
check_command make || exit 1

# Optional tools
check_command ninja && USE_NINJA=ON || USE_NINJA=OFF
check_command ccache && USE_CCACHE=ON || USE_CCACHE=OFF

# Platform-specific dependencies
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -e "${YELLOW}🐧 Linux detected - checking for io_uring and libaio...${NC}"
    
    # Check for io_uring
    if pkg-config --exists liburing; then
        echo -e "${GREEN}✅ liburing found${NC}"
    else
        echo -e "${YELLOW}⚠️  liburing not found - will build without io_uring support${NC}"
    fi
    
    # Check for libaio
    if ldconfig -p | grep -q libaio; then
        echo -e "${GREEN}✅ libaio found${NC}"
    else
        echo -e "${YELLOW}⚠️  libaio not found - will build without libaio support${NC}"
    fi
    
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${YELLOW}🍎 macOS detected - using kqueue for async I/O${NC}"
fi

# Create build directory
BUILD_DIR="build"
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}🧹 Cleaning existing build directory...${NC}"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure build
echo -e "${YELLOW}⚙️  Configuring build...${NC}"

CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX
    -DENABLE_TESTS=$ENABLE_TESTS
    -DENABLE_BENCHMARKS=$ENABLE_BENCHMARKS
)

if [ "$USE_NINJA" = "ON" ]; then
    CMAKE_ARGS+=(-GNinja)
    echo -e "${GREEN}🥷 Using Ninja build system${NC}"
fi

if [ "$USE_CCACHE" = "ON" ]; then
    CMAKE_ARGS+=(-DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
    echo -e "${GREEN}⚡ Using ccache for faster builds${NC}"
fi

# Set compiler-specific optimizations
if [ "$BUILD_TYPE" = "Release" ]; then
    CMAKE_ARGS+=(-DCMAKE_CXX_FLAGS_RELEASE="-O3 -march=native -mtune=native -flto -DNDEBUG")
    echo -e "${GREEN}🚀 Release mode with aggressive optimizations${NC}"
elif [ "$BUILD_TYPE" = "Debug" ]; then
    CMAKE_ARGS+=(-DCMAKE_CXX_FLAGS_DEBUG="-O0 -g -fsanitize=address -fsanitize=undefined")
    echo -e "${YELLOW}🐛 Debug mode with sanitizers${NC}"
fi

cmake "${CMAKE_ARGS[@]}" ..

# Build
echo -e "${YELLOW}🔨 Building...${NC}"

if [ "$USE_NINJA" = "ON" ]; then
    ninja -j$NUM_JOBS
else
    make -j$NUM_JOBS
fi

echo -e "${GREEN}✅ Build completed successfully!${NC}"

# Run tests if enabled
if [ "$ENABLE_TESTS" = "ON" ]; then
    echo -e "${YELLOW}🧪 Running tests...${NC}"
    
    if [ "$USE_NINJA" = "ON" ]; then
        ninja test
    else
        make test
    fi
    
    echo -e "${GREEN}✅ All tests passed!${NC}"
fi

# Display build artifacts
echo -e "${BLUE}📁 Build artifacts:${NC}"
ls -la meteor_server meteor_benchmark 2>/dev/null || echo "No executables found"

# Performance recommendations
echo -e "${BLUE}🚀 Performance Recommendations:${NC}"
echo -e "${YELLOW}For maximum performance:${NC}"
echo "1. Run with --enable-ssd for hybrid caching"
echo "2. Use --max-memory to set appropriate memory limits"
echo "3. Tune --worker-threads and --io-threads based on your hardware"
echo "4. Enable huge pages: echo 'vm.nr_hugepages=1024' >> /etc/sysctl.conf"
echo "5. Set CPU governor to performance: cpupower frequency-set -g performance"
echo "6. Disable swap: swapoff -a"

echo -e "${GREEN}🎉 Build completed successfully!${NC}"
echo -e "${BLUE}Usage examples:${NC}"
echo "  ./meteor_server --port 6380 --enable-ssd --max-memory 1GB"
echo "  ./meteor_benchmark --host localhost --port 6380 --test SET" 