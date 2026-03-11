#!/bin/bash

echo "🧹 CLEANING UP METEOR DIRECTORY"
echo "==============================="
echo "Keeping only Phase 5 Step 4A and Phase 6 Step 1 files"
echo "Removing all other builds, dragonfly folders, and unnecessary files"
echo

cd ~/meteor

echo "📊 Disk usage before cleanup:"
du -sh . 2>/dev/null || echo "Could not check disk usage"
ls -la | wc -l | awk '{print "Total files/dirs: " $1}'

echo
echo "🔍 Files to KEEP (Phase 5 Step 4A and Phase 6 Step 1):"
echo "======================================================"

# List files we want to keep
KEEP_FILES=(
    "meteor_phase5_step4a_simd_lockfree_monitoring"
    "meteor_phase5_step4a_simd_lockfree_monitoring.cpp"
    "sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp"
    "meteor_phase6_step1_avx512_numa"
    "meteor_phase6_step1_optimized"
    "sharded_server_phase6_step1_avx512_numa.cpp"
    "build_phase5_step4a.sh"
    "build_phase6_step1_avx512_numa.sh"
    "build_phase6_step1_optimized.sh"
    "fix_vm_performance_issues.sh"
    "test_phase6_optimized_vs_phase5.sh"
    "phase5_vs_phase6_different_ports.sh"
)

echo "Essential files to preserve:"
for file in "${KEEP_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (not found)"
    fi
done

echo
echo "🗑️  REMOVING UNNECESSARY FILES:"
echo "==============================="

# Remove all dragonfly and garnet related folders
echo "Removing dragonfly and garnet repositories..."
rm -rf dragonfly_repo garnet_repo dragonfly garnet 2>/dev/null || true

# Remove all other meteor binaries (keep only phase5_step4a and phase6_step1)
echo "Removing old meteor binaries..."
find . -name "meteor_*" -type f -executable ! -name "meteor_phase5_step4a_simd_lockfree_monitoring" ! -name "meteor_phase6_step1_*" -delete 2>/dev/null || true

# Remove all other sharded_server source files (keep only phase5_step4a and phase6_step1)
echo "Removing old source files..."
find . -name "sharded_server_*.cpp" ! -name "sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp" ! -name "sharded_server_phase6_step1_avx512_numa.cpp" -delete 2>/dev/null || true

# Remove all other build scripts except the ones we need
echo "Removing old build scripts..."
find . -name "build_*.sh" ! -name "build_phase5_step4a.sh" ! -name "build_phase6_step1_*.sh" -delete 2>/dev/null || true

# Remove deployment scripts (we can recreate if needed)
echo "Removing deployment scripts..."
rm -f deploy_*.sh 2>/dev/null || true

# Remove benchmark scripts except the ones we're using
echo "Removing old benchmark scripts..."
find . -name "benchmark_*.sh" -delete 2>/dev/null || true
find . -name "comprehensive_*.sh" -delete 2>/dev/null || true
find . -name "quick_*.sh" -delete 2>/dev/null || true

# Remove all log files and temporary files
echo "Removing log files and temporary files..."
rm -f *.log *.txt 2>/dev/null || true
rm -rf /tmp/phase* /tmp/meteor* /tmp/optimized* /tmp/fixed* /tmp/system* 2>/dev/null || true

# Remove performance analysis and documentation files (keep essential ones)
echo "Removing old analysis and documentation files..."
rm -f *ANALYSIS*.md *REPORT*.md *SUMMARY*.md *BENCHMARK*.md 2>/dev/null || true
rm -f dash_hash_*.txt phase*_results.txt 2>/dev/null || true

# Remove old cleanup and diagnostic scripts
echo "Removing old utility scripts..."
rm -f cleanup_*.sh diagnose_*.sh direct_*.sh sequential_*.sh 2>/dev/null || true

# Remove any remaining phase-specific files from older phases
echo "Removing old phase files..."
find . -name "*phase1*" -delete 2>/dev/null || true
find . -name "*phase2*" -delete 2>/dev/null || true
find . -name "*phase3*" -delete 2>/dev/null || true
find . -name "*phase4*" -delete 2>/dev/null || true
find . -name "*step1*" ! -name "*phase6_step1*" -delete 2>/dev/null || true
find . -name "*step2*" -delete 2>/dev/null || true
find . -name "*step3*" -delete 2>/dev/null || true

# Remove VLL, dash hash, and other experimental files
echo "Removing experimental files..."
rm -f *vll* *dash* *conservative* *hybrid* *enhanced* *fiber* *lockfree* *minimal* 2>/dev/null || true

# Remove any object files, core dumps, or other build artifacts
echo "Removing build artifacts..."
rm -f *.o *.so *.a core.* 2>/dev/null || true

# Clean up any hidden files that might be taking space
echo "Removing hidden temporary files..."
rm -f .*.tmp .*.log 2>/dev/null || true

echo
echo "✅ CLEANUP COMPLETED"
echo "==================="

echo "📊 Disk usage after cleanup:"
du -sh . 2>/dev/null || echo "Could not check disk usage"
ls -la | wc -l | awk '{print "Total files/dirs remaining: " $1}'

echo
echo "📁 Remaining files:"
echo "=================="
ls -la

echo
echo "🎯 ESSENTIAL FILES PRESERVED:"
echo "============================"
echo "Phase 5 Step 4A files:"
for file in meteor_phase5_step4a_simd_lockfree_monitoring sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp build_phase5_step4a.sh; do
    if [ -f "$file" ]; then
        echo "  ✅ $file ($(du -sh "$file" 2>/dev/null | cut -f1))"
    else
        echo "  ❌ $file (missing)"
    fi
done

echo
echo "Phase 6 Step 1 files:"
for file in meteor_phase6_step1_avx512_numa meteor_phase6_step1_optimized sharded_server_phase6_step1_avx512_numa.cpp build_phase6_step1_avx512_numa.sh build_phase6_step1_optimized.sh; do
    if [ -f "$file" ]; then
        echo "  ✅ $file ($(du -sh "$file" 2>/dev/null | cut -f1))"
    else
        echo "  ❌ $file (missing)"
    fi
done

echo
echo "Utility scripts:"
for file in fix_vm_performance_issues.sh test_phase6_optimized_vs_phase5.sh phase5_vs_phase6_different_ports.sh; do
    if [ -f "$file" ]; then
        echo "  ✅ $file ($(du -sh "$file" 2>/dev/null | cut -f1))"
    else
        echo "  ❌ $file (missing)"
    fi
done

echo
echo "🚀 Directory cleaned up successfully!"
echo "Ready for high-performance testing with optimized disk space"