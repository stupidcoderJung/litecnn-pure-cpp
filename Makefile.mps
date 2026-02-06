# Makefile for Cycle 13 LibTorch MPS Server v3 (Port 8893)

CXX = clang++
CXXFLAGS = -std=c++17 -O3 -Wall -Wextra

# LibTorch paths
LIBTORCH_PATH = $(PWD)/libtorch
LIBTORCH_INCLUDE = $(LIBTORCH_PATH)/include
LIBTORCH_LIB = $(LIBTORCH_PATH)/lib

# Include paths
INCLUDES = -I$(LIBTORCH_INCLUDE) \
           -I$(LIBTORCH_INCLUDE)/torch/csrc/api/include \
           -Iinclude \
           -Ithird_party

# Library paths and libs
LDFLAGS = -L$(LIBTORCH_LIB) \
          -Wl,-rpath,$(LIBTORCH_LIB) \
          -ltorch \
          -ltorch_cpu \
          -lc10 \
          -framework Accelerate \
          -framework Metal \
          -framework Foundation

# Source and output
SRC = src/server_mps.cpp
OUT = build/litecnn_server_mps

.PHONY: all clean run

all: $(OUT)

$(OUT): $(SRC)
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(SRC) -o $(OUT) $(LDFLAGS)
	@echo "✅ Build complete: $(OUT)"

clean:
	rm -rf build/litecnn_server_cycle13_v3

run: $(OUT)
	./$(OUT)
