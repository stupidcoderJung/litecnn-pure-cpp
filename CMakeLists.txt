cmake_minimum_required(VERSION 3.15)
project(LiteCNN-Pure-CPP VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization flags
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -DNDEBUG")

# Include directories
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/third_party
)

# Source files
set(SOURCES
    src/tensor.cpp
    src/layers.cpp
    src/model.cpp
    src/server.cpp
    src/main.cpp
)

# Executable
add_executable(litecnn_server ${SOURCES})

# Threading support
find_package(Threads REQUIRED)
target_link_libraries(litecnn_server PRIVATE Threads::Threads)

# Memory optimization flags
target_compile_options(litecnn_server PRIVATE
    -ffunction-sections
    -fdata-sections
)

# Link options (platform-specific)
if(APPLE)
    target_link_options(litecnn_server PRIVATE
        -Wl,-dead_strip
    )
else()
    target_link_options(litecnn_server PRIVATE
        -Wl,--gc-sections
    )
endif()

# Print build info
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
