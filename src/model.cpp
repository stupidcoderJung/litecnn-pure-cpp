#include "model.h"
#include <iostream>

LiteCNNPro::LiteCNNPro() {}

bool LiteCNNPro::load_weights(const std::string& weights_path) {
    std::vector<std::pair<std::string, Tensor>> weight_list;
    
    if (!WeightLoader::load(weights_path, weight_list)) {
        return false;
    }
    
    for (auto& [name, tensor] : weight_list) {
        // Remove _orig_mod. prefix if present
        std::string clean_name = name;
        const std::string prefix = "_orig_mod.";
        if (clean_name.substr(0, prefix.length()) == prefix) {
            clean_name = clean_name.substr(prefix.length());
        }
        weights_[clean_name] = std::move(tensor);
    }
    
    std::cout << "Loaded " << weights_.size() << " weight tensors" << std::endl;
    return true;
}

Tensor LiteCNNPro::get_weight(const std::string& name) const {
    auto it = weights_.find(name);
    if (it == weights_.end()) {
        throw std::runtime_error("Weight not found: " + name);
    }
    return it->second;
}

bool LiteCNNPro::has_weight(const std::string& name) const {
    return weights_.find(name) != weights_.end();
}

Tensor LiteCNNPro::se_block(const Tensor& x, const std::string& prefix) {
    int N = x.shape[0];
    int C = x.shape[1];
    
    // Squeeze: AdaptiveAvgPool2d(1, 1)
    Tensor squeezed = adaptive_avg_pool2d(x, 1, 1);
    
    // Flatten to [N, C]
    Tensor flat = reshape(squeezed, {N, C});
    
    // Excitation: FC -> ReLU -> FC -> Sigmoid
    std::string fc1_weight = prefix + ".excitation.0.weight";
    std::string fc2_weight = prefix + ".excitation.2.weight";
    
    Tensor y = linear(flat, get_weight(fc1_weight));
    relu6_inplace(y);
    
    y = linear(y, get_weight(fc2_weight));
    sigmoid_inplace(y);
    
    // Reshape back to [N, C, 1, 1]
    Tensor y_reshaped = reshape(y, {N, C, 1, 1});
    
    // Broadcast multiply
    Tensor output = x;
    for (int n = 0; n < N; ++n) {
        for (int c = 0; c < C; ++c) {
            float scale = y_reshaped.data[n * C + c];
            for (int h = 0; h < x.shape[2]; ++h) {
                for (int w = 0; w < x.shape[3]; ++w) {
                    output.at(n, c, h, w) *= scale;
                }
            }
        }
    }
    
    return output;
}

Tensor LiteCNNPro::depthwise_separable_conv(const Tensor& x, const std::string& prefix, 
                                             int stride, bool use_se) {
    // Depthwise conv
    Tensor dw_out = conv2d(x, get_weight(prefix + ".depthwise.weight"), 
                           stride, 1, x.shape[1]);
    
    // BatchNorm + ReLU6
    dw_out = batchnorm2d(dw_out, 
                         get_weight(prefix + ".bn1.weight"),
                         get_weight(prefix + ".bn1.bias"),
                         get_weight(prefix + ".bn1.running_mean"),
                         get_weight(prefix + ".bn1.running_var"));
    relu6_inplace(dw_out);
    
    // Pointwise conv (1x1)
    Tensor pw_out = conv2d(dw_out, get_weight(prefix + ".pointwise.weight"), 
                           1, 0, 1);
    
    // BatchNorm + ReLU6
    pw_out = batchnorm2d(pw_out,
                         get_weight(prefix + ".bn2.weight"),
                         get_weight(prefix + ".bn2.bias"),
                         get_weight(prefix + ".bn2.running_mean"),
                         get_weight(prefix + ".bn2.running_var"));
    relu6_inplace(pw_out);
    
    // SE block
    if (use_se) {
        pw_out = se_block(pw_out, prefix + ".se");
    }
    
    return pw_out;
}

Tensor LiteCNNPro::forward(const Tensor& input) {
    // Stem
    Tensor x = conv2d(input, get_weight("stem.0.weight"), 2, 1, 1);
    x = batchnorm2d(x,
                    get_weight("stem.1.weight"),
                    get_weight("stem.1.bias"),
                    get_weight("stem.1.running_mean"),
                    get_weight("stem.1.running_var"));
    relu6_inplace(x);
    
    // Features
    x = depthwise_separable_conv(x, "features.0", 2, true);
    x = depthwise_separable_conv(x, "features.1", 1, true);
    x = depthwise_separable_conv(x, "features.2", 2, true);
    x = depthwise_separable_conv(x, "features.3", 1, true);
    x = depthwise_separable_conv(x, "features.4", 2, true);
    x = depthwise_separable_conv(x, "features.5", 1, true);
    x = depthwise_separable_conv(x, "features.6", 2, true);
    
    // Global average pooling
    x = adaptive_avg_pool2d(x, 1, 1);
    
    // Flatten
    int N = x.shape[0];
    int C = x.shape[1];
    x = reshape(x, {N, C});
    
    // Classifier (no dropout in inference)
    Tensor fc1_bias = get_weight("classifier.2.bias");
    x = linear(x, get_weight("classifier.2.weight"), &fc1_bias);
    relu6_inplace(x);
    
    Tensor fc2_bias = get_weight("classifier.5.bias");
    x = linear(x, get_weight("classifier.5.weight"), &fc2_bias);
    
    return x;
}
