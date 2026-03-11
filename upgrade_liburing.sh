#!/bin/bash

# **UPGRADE liburing to latest version for advanced io_uring features**
echo "=== 🚀 UPGRADING liburing to LATEST VERSION 🚀 ==="
echo "Current kernel: $(uname -r)"
echo "Current liburing: $(pkg-config --modversion liburing 2>/dev/null || echo 'not found')"
echo ""

# Remove old liburing
echo "📦 Removing old liburing..."
sudo apt remove -y liburing-dev liburing2 2>/dev/null || true

# Update package list
echo "🔄 Updating package lists..."
sudo apt update

# Install dependencies for building from source
echo "🔧 Installing build dependencies..."
sudo apt install -y build-essential git cmake pkg-config

# Clone latest liburing from source
echo "📥 Downloading latest liburing source..."
cd /tmp
rm -rf liburing
git clone https://github.com/axboe/liburing.git
cd liburing

# Check available tags/versions
echo "📋 Available liburing versions:"
git tag --sort=-version:refname | head -10

# Use latest stable release
LATEST_TAG=$(git tag --sort=-version:refname | grep -E '^liburing-[0-9]+\.[0-9]+$' | head -1)
echo "🎯 Using latest stable: $LATEST_TAG"
git checkout $LATEST_TAG

# Configure and build
echo "🏗️  Configuring liburing..."
./configure --prefix=/usr/local

echo "🔨 Building liburing..."
make -j$(nproc)

echo "📦 Installing liburing..."
sudo make install

# Update library cache
sudo ldconfig

# Verify installation
echo ""
echo "✅ Installation complete!"
echo "New liburing version: $(pkg-config --modversion liburing 2>/dev/null || echo 'check /usr/local')"
echo "Library path: $(pkg-config --libs liburing 2>/dev/null || echo '-L/usr/local/lib -luring')"
echo "Include path: $(pkg-config --cflags liburing 2>/dev/null || echo '-I/usr/local/include')"

# Check if we have advanced features
echo ""
echo "🔍 Checking for advanced io_uring features..."
if grep -q "io_uring_prep_multishot_accept" /usr/local/include/liburing.h 2>/dev/null; then
    echo "✅ Multi-shot accept: AVAILABLE"
else
    echo "❌ Multi-shot accept: NOT AVAILABLE"
fi

if grep -q "io_uring_prep_read_fixed" /usr/local/include/liburing.h 2>/dev/null; then
    echo "✅ Fixed buffer operations: AVAILABLE"
else
    echo "❌ Fixed buffer operations: NOT AVAILABLE"
fi

if grep -q "IORING_SETUP_SQPOLL" /usr/local/include/liburing.h 2>/dev/null; then
    echo "✅ SQPOLL mode: AVAILABLE"
else
    echo "❌ SQPOLL mode: NOT AVAILABLE"
fi

echo ""
echo "🎉 liburing upgrade completed!"
echo "💡 You may need to update PKG_CONFIG_PATH or use manual linking"