#include "server.h"
#include <iostream>
#include <cstdlib>

int main(int argc, char* argv[]) {
    std::string weights_path = "weights/model_weights.bin";
    std::string breeds_path = "breed_classes.json";
    int port = 8080;
    
    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--weights" && i + 1 < argc) {
            weights_path = argv[++i];
        } else if (arg == "--breeds" && i + 1 < argc) {
            breeds_path = argv[++i];
        } else if (arg == "--port" && i + 1 < argc) {
            port = std::atoi(argv[++i]);
        } else if (arg == "--help") {
            std::cout << "Usage: " << argv[0] << " [options]\n"
                      << "Options:\n"
                      << "  --weights PATH   Path to weights file (default: weights/model_weights.bin)\n"
                      << "  --breeds PATH    Path to breed classes JSON (default: breed_classes.json)\n"
                      << "  --port PORT      Server port (default: 8080)\n"
                      << "  --help           Show this help\n";
            return 0;
        }
    }
    
    try {
        InferenceServer server(port, weights_path, breeds_path);
        server.run();
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}
