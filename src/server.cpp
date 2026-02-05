#include "server.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <vector>
#include <algorithm>
#include "../third_party/json.hpp"

// Include STB image (header-only)
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_resize2.h"

// Include cpp-httplib (header-only)
#include "httplib.h"

using json = nlohmann::json;

InferenceServer::InferenceServer(int port, const std::string& weights_path, const std::string& breeds_path)
    : port_(port) {
    model_ = std::make_unique<LiteCNNPro>();
    
    std::cout << "Loading model weights..." << std::endl;
    if (!model_->load_weights(weights_path)) {
        throw std::runtime_error("Failed to load model weights");
    }
    std::cout << "Model loaded successfully!" << std::endl;
    
    std::cout << "Loading breed classes..." << std::endl;
    load_breeds(breeds_path);
    std::cout << "Loaded " << breeds_.size() << " breed classes!" << std::endl;
}

void InferenceServer::load_breeds(const std::string& breeds_path) {
    std::ifstream f(breeds_path);
    if (!f.is_open()) {
        throw std::runtime_error("Failed to open breeds file: " + breeds_path);
    }
    
    json data = json::parse(f);
    
    for (auto& [key, value] : data.items()) {
        int class_id = std::stoi(key);
        BreedInfo info;
        info.en = value["en"].get<std::string>();
        info.ko = value["ko"].get<std::string>();
        breeds_[class_id] = info;
    }
}

Tensor InferenceServer::preprocess_image(const std::vector<uint8_t>& image_data) {
    // Decode image
    int width, height, channels;
    unsigned char* img = stbi_load_from_memory(
        image_data.data(), image_data.size(), 
        &width, &height, &channels, 3
    );
    
    if (!img) {
        throw std::runtime_error("Failed to decode image");
    }
    
    // Resize to 224x224
    const int target_size = 224;
    std::vector<unsigned char> resized(target_size * target_size * 3);
    
    stbir_resize_uint8_linear(
        img, width, height, 0,
        resized.data(), target_size, target_size, 0,
        STBIR_RGB
    );
    
    stbi_image_free(img);
    
    // Convert to tensor [1, 3, 224, 224] and normalize
    Tensor tensor({1, 3, target_size, target_size});
    
    // ImageNet normalization
    float mean[3] = {0.485f, 0.456f, 0.406f};
    float std[3] = {0.229f, 0.224f, 0.225f};
    
    for (int c = 0; c < 3; ++c) {
        for (int h = 0; h < target_size; ++h) {
            for (int w = 0; w < target_size; ++w) {
                int src_idx = (h * target_size + w) * 3 + c;
                int dst_idx = ((0 * 3 + c) * target_size + h) * target_size + w;
                
                float pixel = resized[src_idx] / 255.0f;
                tensor.data[dst_idx] = (pixel - mean[c]) / std[c];
            }
        }
    }
    
    return tensor;
}

std::string InferenceServer::create_response(const std::vector<float>& logits) {
    // Find top-5 predictions
    std::vector<std::pair<float, int>> scores;
    for (size_t i = 0; i < logits.size(); ++i) {
        scores.emplace_back(logits[i], i);
    }
    
    std::partial_sort(scores.begin(), scores.begin() + 5, scores.end(),
                     [](const auto& a, const auto& b) { return a.first > b.first; });
    
    // Softmax for probabilities
    float max_logit = scores[0].first;
    float sum_exp = 0.0f;
    std::vector<float> probs;
    
    for (int i = 0; i < 5; ++i) {
        float exp_val = std::exp(scores[i].first - max_logit);
        probs.push_back(exp_val);
        sum_exp += exp_val;
    }
    
    // Create JSON response
    json response_json;
    json predictions = json::array();
    
    for (int i = 0; i < 5; ++i) {
        float prob = probs[i] / sum_exp;
        int class_id = scores[i].second;
        
        json pred;
        pred["class_id"] = class_id;
        pred["score"] = prob;
        
        // Add breed names if available
        auto it = breeds_.find(class_id);
        if (it != breeds_.end()) {
            pred["breed_en"] = it->second.en;
            pred["breed_ko"] = it->second.ko;
        }
        
        predictions.push_back(pred);
    }
    
    response_json["predictions"] = predictions;
    return response_json.dump();
}

void InferenceServer::run() {
    httplib::Server svr;
    
    // Health check
    svr.Get("/health", [](const httplib::Request&, httplib::Response& res) {
        res.set_content("{\"status\":\"ok\"}", "application/json");
    });
    
    // Inference endpoint
    svr.Post("/predict", [this](const httplib::Request& req, httplib::Response& res) {
        try {
            // Get image data from multipart form
            auto it = req.form.files.find("image");
            if (it == req.form.files.end()) {
                res.status = 400;
                res.set_content("{\"error\":\"No image file provided\"}", "application/json");
                return;
            }
            
            const auto& file = it->second;
            std::vector<uint8_t> image_data(file.content.begin(), file.content.end());
            
            // Preprocess
            auto start = std::chrono::high_resolution_clock::now();
            Tensor input = preprocess_image(image_data);
            
            // Inference
            Tensor output = model_->forward(input);
            auto end = std::chrono::high_resolution_clock::now();
            
            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
            
            // Create response
            std::vector<float> logits(output.data.begin(), output.data.end());
            std::string response = create_response(logits);
            
            std::cout << "Inference completed in " << duration.count() << "ms" << std::endl;
            
            res.set_content(response, "application/json");
        } catch (const std::exception& e) {
            res.status = 500;
            res.set_content("{\"error\":\"" + std::string(e.what()) + "\"}", 
                          "application/json");
        }
    });
    
    std::cout << "Starting server on port " << port_ << "..." << std::endl;
    svr.listen("0.0.0.0", port_);
}
