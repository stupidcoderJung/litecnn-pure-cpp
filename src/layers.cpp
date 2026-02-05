#include "layers.h"
#include <cmath>
#include <iostream>

// Optimized conv2d implementation
Tensor conv2d(const Tensor& input, const Tensor& weight, 
              int stride, int padding, int groups) {
    // Input: [N, C_in, H, W]
    // Weight: [C_out, C_in/groups, kH, kW]
    
    int N = input.shape[0];
    int C_in = input.shape[1];
    int H_in = input.shape[2];
    int W_in = input.shape[3];
    
    int C_out = weight.shape[0];
    int kH = weight.shape[2];
    int kW = weight.shape[3];
    
    int H_out = (H_in + 2 * padding - kH) / stride + 1;
    int W_out = (W_in + 2 * padding - kW) / stride + 1;
    
    Tensor output({N, C_out, H_out, W_out});
    std::fill(output.data.begin(), output.data.end(), 0.0f);
    
    int C_per_group = C_in / groups;
    int C_out_per_group = C_out / groups;
    
    for (int n = 0; n < N; ++n) {
        for (int g = 0; g < groups; ++g) {
            for (int oc = 0; oc < C_out_per_group; ++oc) {
                int out_ch = g * C_out_per_group + oc;
                
                for (int oh = 0; oh < H_out; ++oh) {
                    for (int ow = 0; ow < W_out; ++ow) {
                        float sum = 0.0f;
                        
                        for (int ic = 0; ic < C_per_group; ++ic) {
                            int in_ch = g * C_per_group + ic;
                            
                            for (int kh = 0; kh < kH; ++kh) {
                                for (int kw = 0; kw < kW; ++kw) {
                                    int ih = oh * stride - padding + kh;
                                    int iw = ow * stride - padding + kw;
                                    
                                    if (ih >= 0 && ih < H_in && iw >= 0 && iw < W_in) {
                                        int input_idx = ((n * C_in + in_ch) * H_in + ih) * W_in + iw;
                                        int weight_idx = ((out_ch * C_per_group + ic) * kH + kh) * kW + kw;
                                        sum += input.data[input_idx] * weight.data[weight_idx];
                                    }
                                }
                            }
                        }
                        
                        int output_idx = ((n * C_out + out_ch) * H_out + oh) * W_out + ow;
                        output.data[output_idx] = sum;
                    }
                }
            }
        }
    }
    
    return output;
}

// BatchNorm2D
Tensor batchnorm2d(const Tensor& input, const Tensor& weight, 
                   const Tensor& bias, const Tensor& running_mean, 
                   const Tensor& running_var, float eps) {
    int N = input.shape[0];
    int C = input.shape[1];
    int H = input.shape[2];
    int W = input.shape[3];
    
    Tensor output(input.shape);
    
    for (int n = 0; n < N; ++n) {
        for (int c = 0; c < C; ++c) {
            float mean = running_mean.data[c];
            float var = running_var.data[c];
            float gamma = weight.data[c];
            float beta = bias.data[c];
            
            float scale = gamma / std::sqrt(var + eps);
            
            for (int h = 0; h < H; ++h) {
                for (int w = 0; w < W; ++w) {
                    int idx = ((n * C + c) * H + h) * W + w;
                    output.data[idx] = scale * (input.data[idx] - mean) + beta;
                }
            }
        }
    }
    
    return output;
}

// AdaptiveAvgPool2d
Tensor adaptive_avg_pool2d(const Tensor& input, int output_h, int output_w) {
    int N = input.shape[0];
    int C = input.shape[1];
    int H = input.shape[2];
    int W = input.shape[3];
    
    Tensor output({N, C, output_h, output_w});
    
    for (int n = 0; n < N; ++n) {
        for (int c = 0; c < C; ++c) {
            for (int oh = 0; oh < output_h; ++oh) {
                for (int ow = 0; ow < output_w; ++ow) {
                    int h_start = (oh * H) / output_h;
                    int h_end = ((oh + 1) * H) / output_h;
                    int w_start = (ow * W) / output_w;
                    int w_end = ((ow + 1) * W) / output_w;
                    
                    float sum = 0.0f;
                    int count = 0;
                    
                    for (int h = h_start; h < h_end; ++h) {
                        for (int w = w_start; w < w_end; ++w) {
                            sum += input.at(n, c, h, w);
                            count++;
                        }
                    }
                    
                    int idx = ((n * C + c) * output_h + oh) * output_w + ow;
                    output.data[idx] = sum / count;
                }
            }
        }
    }
    
    return output;
}

// Linear (fully connected)
Tensor linear(const Tensor& input, const Tensor& weight, const Tensor* bias) {
    // Input: [N, in_features]
    // Weight: [out_features, in_features]
    // Output: [N, out_features]
    
    int N = input.shape[0];
    int in_features = input.shape[1];
    int out_features = weight.shape[0];
    
    Tensor output({N, out_features});
    
    for (int n = 0; n < N; ++n) {
        for (int o = 0; o < out_features; ++o) {
            float sum = 0.0f;
            
            for (int i = 0; i < in_features; ++i) {
                sum += input.data[n * in_features + i] * weight.data[o * in_features + i];
            }
            
            if (bias) {
                sum += bias->data[o];
            }
            
            output.data[n * out_features + o] = sum;
        }
    }
    
    return output;
}
