# Meteor High-Performance Cache Server
# Optimized Makefile with aggressive compiler optimizations

# Compiler detection
CXX := $(shell which clang++ 2>/dev/null || which g++ 2>/dev/null)
ifeq ($(CXX),)
    $(error No suitable C++ compiler found)
endif

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Base configuration
TARGET := meteor-server-cpp
BENCHMARK_TARGET := meteor-benchmark-cpp
TEST_TARGET := meteor-test-cpp
BUILD_DIR := build
SRC_DIR := src
INCLUDE_DIR := include
OBJ_DIR := $(BUILD_DIR)/obj

# C++ standard and base flags
CXXSTD := -std=c++20
CXXFLAGS := $(CXXSTD) -I$(INCLUDE_DIR) -I$(SRC_DIR) -I/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk/usr/include/c++/v1 -I/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk/usr/include -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk

# Base optimization flags
OPT_FLAGS := -O3 -DNDEBUG -march=native -mtune=native -flto -ffast-math
OPT_FLAGS += -funroll-loops -fomit-frame-pointer -fno-stack-protector
OPT_FLAGS +=  -fno-rtti -fvisibility=hidden -fvisibility-inlines-hidden

# Compiler-specific optimizations
ifeq ($(shell $(CXX) --version | grep -i clang),)
    # GCC-specific optimizations
    OPT_FLAGS += -finline-functions -finline-small-functions -findirect-inlining
    OPT_FLAGS += -fdevirtualize -fdevirtualize-speculatively
    OPT_FLAGS += -fstrict-aliasing -fdevirtualize-at-ltrans -fipa-pta
    OPT_FLAGS += -floop-nest-optimize -fgraphite-identity -floop-parallelize-all
    OPT_FLAGS += -ftree-loop-distribution -ftree-loop-im -ftree-loop-ivcanon
    OPT_FLAGS += -fivopts -fvariable-expansion-in-unroller
else
    # Clang-specific optimizations (more conservative)
    OPT_FLAGS += -finline-functions
    OPT_FLAGS += -fstrict-aliasing -fstrict-enums -fstrict-return
    OPT_FLAGS += -fslp-vectorize -fvectorize
endif

# Platform-specific flags
ifeq ($(UNAME_S),Linux)
    PLATFORM_FLAGS := -DMETEOR_PLATFORM_LINUX -pthread
    LDFLAGS := -pthread -lrt -ldl
    
    # Check for io_uring support
    ifneq ($(shell pkg-config --exists liburing 2>/dev/null; echo $$?),0)
        ifneq ($(shell ldconfig -p | grep liburing),)
            PLATFORM_FLAGS += -DHAVE_IO_URING
            LDFLAGS += -luring
        endif
    else
        PLATFORM_FLAGS += -DHAVE_IO_URING
        LDFLAGS += $(shell pkg-config --libs liburing)
    endif
    
    # Additional Linux optimizations
    ifneq ($(shell $(CXX) --version | grep -i clang),)
        OPT_FLAGS += -fno-plt -fno-semantic-interposition
    endif
    
else ifeq ($(UNAME_S),Darwin)
    PLATFORM_FLAGS := -DMETEOR_PLATFORM_MACOS -pthread
    LDFLAGS := -pthread -framework CoreFoundation -framework Security
    
    # macOS-specific optimizations
    OPT_FLAGS += -mmacosx-version-min=10.15
    
else ifeq ($(UNAME_S),MINGW32_NT-* MINGW64_NT-* MSYS_NT-*)
    PLATFORM_FLAGS := -DMETEOR_PLATFORM_WINDOWS -DWIN32_LEAN_AND_MEAN -DNOMINMAX
    LDFLAGS := -lws2_32 -lmswsock -lkernel32 -luser32 -ladvapi32
    TARGET := $(TARGET).exe
    BENCHMARK_TARGET := $(BENCHMARK_TARGET).exe
    TEST_TARGET := $(TEST_TARGET).exe
endif

# Architecture-specific optimizations
ifeq ($(UNAME_M),x86_64)
    OPT_FLAGS += -msse4.2 -mavx -mavx2 -mfma
else ifeq ($(UNAME_M),arm64)
    OPT_FLAGS += -mcpu=apple-m1
else ifeq ($(UNAME_M),aarch64)
    OPT_FLAGS += -mcpu=native
endif

# Debug flags
DEBUG_FLAGS := -O0 -g -DDEBUG -fno-omit-frame-pointer -fstack-protector-strong

# Profile flags
PROFILE_FLAGS := -O2 -g -DNDEBUG -fno-omit-frame-pointer -pg

# Warning flags
WARNING_FLAGS := -Wall -Wextra -Wpedantic -Wno-unused-parameter -Wno-unused-variable
WARNING_FLAGS += -Wno-missing-field-initializers -Wno-sign-compare

# Final flags
CXXFLAGS += $(PLATFORM_FLAGS) $(WARNING_FLAGS)
LDFLAGS += -flto

# Build mode selection
ifeq ($(BUILD),debug)
    CXXFLAGS += $(DEBUG_FLAGS)
    BUILD_MODE := debug
else ifeq ($(BUILD),profile)
    CXXFLAGS += $(PROFILE_FLAGS)
    BUILD_MODE := profile
else
    CXXFLAGS += $(OPT_FLAGS)
    BUILD_MODE := release
endif

# Source files
SOURCES := $(shell find $(SRC_DIR) -name "*.cpp" -not -path "*/cmd/*")
MAIN_SOURCE := $(SRC_DIR)/cmd/server/main.cpp
BENCHMARK_SOURCE := $(SRC_DIR)/cmd/benchmark/main.cpp
TEST_SOURCE := $(SRC_DIR)/cmd/test/main.cpp

# Object files
OBJECTS := $(SOURCES:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)
MAIN_OBJECT := $(OBJ_DIR)/cmd/server/main.o
BENCHMARK_OBJECT := $(OBJ_DIR)/cmd/benchmark/main.o
TEST_OBJECT := $(OBJ_DIR)/cmd/test/main.o

# Default target
.PHONY: all clean install benchmark test help debug profile release
.DEFAULT_GOAL := all

all: $(TARGET)

# Main executable
$(TARGET): $(OBJECTS) $(MAIN_OBJECT) | $(BUILD_DIR)
	@echo "🔗 Linking $(TARGET) ($(BUILD_MODE) mode)"
	@$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "✅ Built $(TARGET) successfully"

# Benchmark executable
$(BENCHMARK_TARGET): $(OBJECTS) $(BENCHMARK_OBJECT) | $(BUILD_DIR)
	@echo "🔗 Linking $(BENCHMARK_TARGET)"
	@$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "✅ Built $(BENCHMARK_TARGET) successfully"

# Test executable
$(TEST_TARGET): $(OBJECTS) $(TEST_OBJECT) | $(BUILD_DIR)
	@echo "🔗 Linking $(TEST_TARGET)"
	@$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "✅ Built $(TEST_TARGET) successfully"

# Object file compilation
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp | $(OBJ_DIR)
	@echo "🔨 Compiling $<"
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -c $< -o $@

# Directory creation
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(OBJ_DIR):
	@mkdir -p $(OBJ_DIR)

# Build modes
debug:
	@$(MAKE) BUILD=debug

profile:
	@$(MAKE) BUILD=profile

release:
	@$(MAKE) BUILD=release

# Benchmarking
benchmark: $(BENCHMARK_TARGET)
	@echo "🚀 Running benchmarks..."
	@./$(BENCHMARK_TARGET)

# Testing
test: $(TEST_TARGET)
	@echo "🧪 Running tests..."
	@./$(TEST_TARGET)

# Installation
install: $(TARGET)
	@echo "📦 Installing $(TARGET)..."
	@cp $(TARGET) /usr/local/bin/
	@echo "✅ Installed $(TARGET) to /usr/local/bin/"

# Cleanup
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(TARGET) $(BENCHMARK_TARGET) $(TEST_TARGET)
	@echo "✅ Cleaned successfully"

# Performance analysis
perf: $(TARGET)
	@echo "📊 Running performance analysis..."
	@perf record -g ./$(TARGET) --port 6380 &
	@sleep 5
	@pkill -f $(TARGET)
	@perf report

# Memory check
memcheck: $(TARGET)
	@echo "🔍 Running memory check..."
	@valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes ./$(TARGET) --port 6380

# Static analysis
analyze:
	@echo "🔍 Running static analysis..."
	@clang-tidy $(SOURCES) $(MAIN_SOURCE) -- $(CXXFLAGS)

# Code formatting
format:
	@echo "🎨 Formatting code..."
	@find $(SRC_DIR) $(INCLUDE_DIR) -name "*.cpp" -o -name "*.hpp" | xargs clang-format -i

# Help
help:
	@echo "Meteor High-Performance Cache Server Build System"
	@echo "================================================="
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build main executable (default)"
	@echo "  debug       - Build with debug flags"
	@echo "  profile     - Build with profiling flags"
	@echo "  release     - Build with maximum optimizations"
	@echo "  benchmark   - Build and run benchmarks"
	@echo "  test        - Build and run tests"
	@echo "  install     - Install to /usr/local/bin"
	@echo "  clean       - Remove build artifacts"
	@echo "  perf        - Run performance analysis"
	@echo "  memcheck    - Run memory check with Valgrind"
	@echo "  analyze     - Run static analysis"
	@echo "  format      - Format code with clang-format"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Configuration:"
	@echo "  Platform: $(UNAME_S) $(UNAME_M)"
	@echo "  Compiler: $(CXX)"
	@echo "  Build mode: $(BUILD_MODE)"
	@echo "  Optimization: $(OPT_FLAGS)"

# Print configuration
config:
	@echo "=== Build Configuration ==="
	@echo "Platform: $(UNAME_S) $(UNAME_M)"
	@echo "Compiler: $(CXX)"
	@echo "Build mode: $(BUILD_MODE)"
	@echo "C++ Standard: $(CXXSTD)"
	@echo "Include dirs: $(INCLUDE_DIR)"
	@echo "Source dirs: $(SRC_DIR)"
	@echo "Object dir: $(OBJ_DIR)"
	@echo "CXXFLAGS: $(CXXFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@echo "=========================="

# Dependencies
-include $(OBJECTS:.o=.d)
-include $(MAIN_OBJECT:.o=.d)
-include $(BENCHMARK_OBJECT:.o=.d)
-include $(TEST_OBJECT:.o=.d)

# Generate dependency files
$(OBJ_DIR)/%.d: $(SRC_DIR)/%.cpp
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -MM -MT $(@:.d=.o) $< > $@ 