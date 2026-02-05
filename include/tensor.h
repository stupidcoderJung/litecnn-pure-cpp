#pragma once
#include <vector>
#include <string>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <cstring>

// Lightweight tensor class using raw memory
class Tensor {
public:
    std::vector<int> shape;
    std::vector<float> data;
    
    Tensor() = default;
    
    Tensor(const std::vector<int>& shape_) : shape(shape_) {
        size_t total = 1;
        for (int s : shape) total *= s;
        data.resize(total);
    }
    
    Tensor(const std::vector<int>& shape_, const std::vector<float>& data_) 
        : shape(shape_), data(data_) {}
    
    size_t size() const {
        size_t total = 1;
        for (int s : shape) total *= s;
        return total;
    }
    
    float* ptr() { return data.data(); }
    const float* ptr() const { return data.data(); }
    
    // Access helpers
    float& at(int n, int c, int h, int w) {
        int idx = ((n * shape[1] + c) * shape[2] + h) * shape[3] + w;
        return data[idx];
    }
    
    const float& at(int n, int c, int h, int w) const {
        int idx = ((n * shape[1] + c) * shape[2] + h) * shape[3] + w;
        return data[idx];
    }
};

// Weight loader
class WeightLoader {
public:
    static bool load(const std::string& path, 
                    std::vector<std::pair<std::string, Tensor>>& weights);
};
