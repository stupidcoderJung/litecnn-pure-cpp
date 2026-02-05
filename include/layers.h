#pragma once
#include "tensor.h"
#include <cmath>
#include <algorithm>

// Conv2D operation
Tensor conv2d(const Tensor& input, const Tensor& weight, 
              int stride = 1, int padding = 0, int groups = 1);

// BatchNorm2D
Tensor batchnorm2d(const Tensor& input, const Tensor& weight, 
                   const Tensor& bias, const Tensor& running_mean, 
                   const Tensor& running_var, float eps = 1e-5);

// ReLU6
inline void relu6_inplace(Tensor& x) {
    for (auto& v : x.data) {
        v = std::min(std::max(v, 0.0f), 6.0f);
    }
}

// AdaptiveAvgPool2d
Tensor adaptive_avg_pool2d(const Tensor& input, int output_h, int output_w);

// Linear (fully connected)
Tensor linear(const Tensor& input, const Tensor& weight, const Tensor* bias = nullptr);

// Sigmoid
inline void sigmoid_inplace(Tensor& x) {
    for (auto& v : x.data) {
        v = 1.0f / (1.0f + std::exp(-v));
    }
}

// Element-wise multiply
inline Tensor multiply(const Tensor& a, const Tensor& b) {
    Tensor result = a;
    for (size_t i = 0; i < result.data.size(); ++i) {
        result.data[i] *= b.data[i];
    }
    return result;
}

// Reshape
inline Tensor reshape(const Tensor& input, const std::vector<int>& new_shape) {
    Tensor result;
    result.shape = new_shape;
    result.data = input.data;
    return result;
}
