#pragma once
#include "model.h"
#include <string>
#include <memory>
#include <map>

struct BreedInfo {
    std::string en;
    std::string ko;
};

class InferenceServer {
public:
    InferenceServer(int port, const std::string& weights_path, const std::string& breeds_path);
    
    void run();
    
private:
    int port_;
    std::unique_ptr<LiteCNNPro> model_;
    std::map<int, BreedInfo> breeds_;
    
    // Load breed classes
    void load_breeds(const std::string& breeds_path);
    
    // Image preprocessing
    Tensor preprocess_image(const std::vector<uint8_t>& image_data);
    
    // Response generation
    std::string create_response(const std::vector<float>& logits);
};
