#pragma once
#include "tensor.h"
#include "layers.h"
#include <map>
#include <string>

class LiteCNNPro {
public:
    LiteCNNPro();
    
    bool load_weights(const std::string& weights_path);
    
    Tensor forward(const Tensor& input);
    
private:
    // Weights storage
    std::map<std::string, Tensor> weights_;
    
    // Helper methods
    Tensor depthwise_separable_conv(const Tensor& x, const std::string& prefix, 
                                    int stride, bool use_se);
    
    Tensor se_block(const Tensor& x, const std::string& prefix);
    
    Tensor get_weight(const std::string& name) const;
    bool has_weight(const std::string& name) const;
};
