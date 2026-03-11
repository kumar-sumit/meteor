#!/bin/bash

# **DEMO SCRIPT - Create Meteor Package from Current Binary**
# This script demonstrates how to create a distributable package
# from the current meteor_ttl_complete binary

set -euo pipefail

echo "🚀 **METEOR PACKAGE CREATION DEMO**"
echo "=================================="

# Check if the TTL complete binary exists
if [ ! -f "cpp/meteor_ttl_complete" ]; then
    echo "❌ ERROR: cpp/meteor_ttl_complete binary not found"
    echo ""
    echo "Please ensure you have:"
    echo "1. Built the meteor server: meteor_ttl_complete binary"
    echo "2. Or copy your binary to cpp/meteor_ttl_complete"
    echo ""
    echo "If you have the binary elsewhere, copy it:"
    echo "cp /path/to/your/meteor_binary cpp/meteor_ttl_complete"
    exit 1
fi

echo "✅ Found meteor_ttl_complete binary"
echo "📏 Binary size: $(du -h cpp/meteor_ttl_complete | cut -f1)"
echo ""

# Make sure it's executable
chmod +x cpp/meteor_ttl_complete

echo "🔨 Creating distributable package..."
echo ""

# Run the package creation script
./create_meteor_package.sh

echo ""
echo "🎉 **PACKAGE CREATION COMPLETE!**"
echo ""
echo "📦 **Files Created:**"
ls -la meteor-server-*.tar.gz* meteor-server-*-INFO.txt 2>/dev/null || echo "Check directory for created files"
echo ""

echo "📋 **Next Steps:**"
echo "1. Copy the .tar.gz file to your target server"
echo "2. Extract: tar -xzf meteor-server-*.tar.gz"
echo "3. Install: cd meteor-server-* && sudo ./install.sh"
echo ""

echo "✅ **Distribution package ready for enterprise deployment!**"
