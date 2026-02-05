#include "tensor.h"
#include <fstream>
#include <iostream>

bool WeightLoader::load(const std::string& path, 
                        std::vector<std::pair<std::string, Tensor>>& weights) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open weights file: " << path << std::endl;
        return false;
    }
    
    // Read magic number
    char magic[4];
    file.read(magic, 4);
    if (std::strncmp(magic, "LCNN", 4) != 0) {
        std::cerr << "Invalid magic number" << std::endl;
        return false;
    }
    
    // Read version
    uint32_t version;
    file.read(reinterpret_cast<char*>(&version), sizeof(uint32_t));
    
    // Read number of parameters
    uint32_t num_params;
    file.read(reinterpret_cast<char*>(&num_params), sizeof(uint32_t));
    
    std::cout << "Loading " << num_params << " parameters..." << std::endl;
    
    for (uint32_t i = 0; i < num_params; ++i) {
        // Read name
        uint32_t name_len;
        file.read(reinterpret_cast<char*>(&name_len), sizeof(uint32_t));
        
        std::vector<char> name_buf(name_len + 1);
        file.read(name_buf.data(), name_len);
        name_buf[name_len] = '\0';
        std::string name(name_buf.data());
        
        // Read shape
        uint32_t ndim;
        file.read(reinterpret_cast<char*>(&ndim), sizeof(uint32_t));
        
        std::vector<int> shape(ndim);
        for (uint32_t j = 0; j < ndim; ++j) {
            uint32_t dim;
            file.read(reinterpret_cast<char*>(&dim), sizeof(uint32_t));
            shape[j] = static_cast<int>(dim);
        }
        
        // Read data
        size_t total_size = 1;
        for (int s : shape) total_size *= s;
        
        std::vector<float> data(total_size);
        file.read(reinterpret_cast<char*>(data.data()), total_size * sizeof(float));
        
        Tensor tensor(shape, data);
        weights.emplace_back(name, std::move(tensor));
        
        if (i < 5 || i >= num_params - 5) {
            std::cout << "  " << name << ": [";
            for (size_t j = 0; j < shape.size(); ++j) {
                std::cout << shape[j];
                if (j < shape.size() - 1) std::cout << ", ";
            }
            std::cout << "]" << std::endl;
        } else if (i == 5) {
            std::cout << "  ..." << std::endl;
        }
    }
    
    return true;
}
