#define STB_IMAGE_IMPLEMENTATION
#include "third_party/stb_image.h"
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <image_file>" << std::endl;
        return 1;
    }
    
    // Read file to memory
    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) {
        std::cerr << "Failed to open file: " << argv[1] << std::endl;
        return 1;
    }
    
    size_t size = file.tellg();
    file.seekg(0);
    
    std::vector<uint8_t> data(size);
    file.read(reinterpret_cast<char*>(data.data()), size);
    file.close();
    
    std::cout << "File size: " << size << " bytes" << std::endl;
    
    // Try to decode
    int width, height, channels;
    unsigned char* img = stbi_load_from_memory(data.data(), data.size(), &width, &height, &channels, 3);
    
    if (!img) {
        std::cerr << "Failed to decode image: " << stbi_failure_reason() << std::endl;
        return 1;
    }
    
    std::cout << "✓ Image decoded successfully!" << std::endl;
    std::cout << "  Size: " << width << "x" << height << std::endl;
    std::cout << "  Channels: " << channels << std::endl;
    
    stbi_image_free(img);
    return 0;
}
