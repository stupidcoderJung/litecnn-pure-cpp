// MPS Server with configurable port and model
#include <torch/script.h>
#include <torch/torch.h>
#include "httplib.h"
#include "json.hpp"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include <iostream>
#include <fstream>
#include <vector>
#include <chrono>
#include <iomanip>
#include <cstring>

using json = nlohmann::json;
using namespace std;
using namespace std::chrono;

torch::jit::script::Module model;
torch::Device device = torch::kCPU;
json breed_classes;

const vector<float> MEAN = {0.485f, 0.456f, 0.406f};
const vector<float> STD  = {0.229f, 0.224f, 0.225f};

void load_breed_classes(const string& path) {
    ifstream file(path);
    if (!file.is_open()) {
        cerr << "Warning: Could not load breed classes from " << path << endl;
        breed_classes = json::object();
        for (int i = 0; i < 130; i++) {
            breed_classes[to_string(i)] = {
                {"en", "class_" + to_string(i)},
                {"ko", "클래스_" + to_string(i)}
            };
        }
        return;
    }
    file >> breed_classes;
    cout << "✅ Loaded " << breed_classes.size() << " breed classes (KO/EN)" << endl;
}

torch::Tensor preprocess_image_from_memory(const unsigned char* data, size_t size, double& preprocess_ms) {
    auto start = high_resolution_clock::now();
    
    int width, height, channels;
    unsigned char* img_data = stbi_load_from_memory(data, size, &width, &height, &channels, 3);
    
    if (!img_data) {
        throw runtime_error("Failed to decode image from memory");
    }
    
    torch::Tensor tensor = torch::from_blob(img_data, {height, width, 3}, torch::kUInt8).clone();
    stbi_image_free(img_data);
    
    tensor = tensor.to(torch::kFloat32).div(255.0);
    tensor = tensor.permute({2, 0, 1}).unsqueeze(0);
    tensor = torch::nn::functional::interpolate(
        tensor,
        torch::nn::functional::InterpolateFuncOptions()
            .size(vector<int64_t>{224, 224})
            .mode(torch::kBilinear)
            .align_corners(false)
    );
    
    for (int c = 0; c < 3; c++) {
        tensor[0][c] = tensor[0][c].sub(MEAN[c]).div(STD[c]);
    }
    
    auto end = high_resolution_clock::now();
    preprocess_ms = duration_cast<microseconds>(end - start).count() / 1000.0;
    
    return tensor;
}

json predict_top_k_from_tensor(torch::Tensor input_tensor, double preprocess_ms, int k = 3) {
    auto total_start = high_resolution_clock::now();
    
    auto transfer_start = high_resolution_clock::now();
    input_tensor = input_tensor.to(device);
    auto transfer_end = high_resolution_clock::now();
    double transfer_ms = duration_cast<microseconds>(transfer_end - transfer_start).count() / 1000.0;
    
    auto inference_start = high_resolution_clock::now();
    torch::NoGradGuard no_grad;
    auto output = model.forward({input_tensor}).toTensor();
    
    if (device.is_mps()) {
        output = output.to(torch::kCPU);
    }
    
    auto inference_end = high_resolution_clock::now();
    double inference_ms = duration_cast<microseconds>(inference_end - inference_start).count() / 1000.0;
    
    auto probabilities = torch::softmax(output, 1);
    auto [values, indices] = torch::topk(probabilities, k);
    
    json result;
    result["predictions"] = json::array();
    
    for (int i = 0; i < k; i++) {
        int class_id = indices[0][i].item<int>();
        float confidence = values[0][i].item<float>() * 100.0f;
        
        string class_key = to_string(class_id);
        
        json pred;
        pred["rank"] = i + 1;
        pred["class_id"] = class_id;
        
        if (breed_classes.contains(class_key)) {
            pred["breed_en"] = breed_classes[class_key]["en"];
            pred["breed_ko"] = breed_classes[class_key]["ko"];
        } else {
            pred["breed_en"] = "unknown";
            pred["breed_ko"] = "알 수 없음";
        }
        
        pred["confidence"] = round(confidence * 100) / 100.0;
        result["predictions"].push_back(pred);
    }
    
    auto total_end = high_resolution_clock::now();
    double total_ms = duration_cast<microseconds>(total_end - total_start).count() / 1000.0;
    
    result["timing"] = {
        {"total_ms", round(total_ms * 1000) / 1000.0},
        {"preprocess_ms", round(preprocess_ms * 1000) / 1000.0},
        {"inference_ms", round(inference_ms * 1000) / 1000.0},
        {"transfer_ms", round(transfer_ms * 1000) / 1000.0}
    };
    
    return result;
}

int main(int argc, char** argv) {
    // Parse arguments
    int port = 8893;
    string model_path = "weights/cycle13_mps_traced.pt";
    string model_name = "Unknown";
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--model") == 0 && i + 1 < argc) {
            model_path = argv[++i];
        } else if (strcmp(argv[i], "--name") == 0 && i + 1 < argc) {
            model_name = argv[++i];
        }
    }
    
    cout << "============================================================\n";
    cout << "LiteCNN MPS Server\n";
    cout << "Port: " << port << " | Model: " << model_name << "\n";
    cout << "============================================================\n\n";
    
    if (torch::hasMPS()) {
        device = torch::kMPS;
        cout << "✅ MPS (Metal Performance Shaders) available\n";
    } else {
        cout << "⚠️  MPS not available, using CPU\n";
    }
    
    cout << "📦 Loading model: " << model_path << "\n";
    try {
        model = torch::jit::load(model_path, device);
        model.eval();
        cout << "✅ Model loaded on " << (device.is_mps() ? "MPS" : "CPU") << "\n";
    } catch (const c10::Error& e) {
        cerr << "❌ Error loading model: " << e.what() << endl;
        return 1;
    }
    
    load_breed_classes("breed_classes.json");
    
    cout << "\n🔥 Warming up (10 iterations)...\n";
    try {
        auto warmup_tensor = torch::randn({1, 3, 224, 224}).to(device);
        for (int i = 0; i < 10; i++) {
            model.forward({warmup_tensor});
        }
        cout << "✅ Warmup complete\n";
    } catch (const exception& e) {
        cerr << "Warning: Warmup failed: " << e.what() << endl;
    }
    
    httplib::Server svr;
    
    svr.Post("/predict", [](const httplib::Request& req, httplib::Response& res) {
        try {
            torch::Tensor input_tensor;
            double preprocess_ms;
            int top_k = 3;
            
            if (req.form.has_file("image")) {
                auto file = req.form.get_file("image");
                const unsigned char* data = reinterpret_cast<const unsigned char*>(file.content.data());
                size_t size = file.content.size();
                
                input_tensor = preprocess_image_from_memory(data, size, preprocess_ms);
                
                if (req.has_param("top_k")) {
                    top_k = stoi(req.get_param_value("top_k"));
                }
            } else {
                throw runtime_error("No image provided (use multipart 'image')");
            }
            
            auto result = predict_top_k_from_tensor(input_tensor, preprocess_ms, top_k);
            res.set_content(result.dump(2), "application/json");
            
            auto& predictions = result["predictions"];
            if (!predictions.empty()) {
                auto top1 = predictions[0];
                cout << "🐕 " << top1["breed_ko"] << " (" << top1["breed_en"] << ") "
                     << fixed << setprecision(1) << top1["confidence"].get<double>() << "% | "
                     << "⏱️  " << setprecision(3) << result["timing"]["inference_ms"].get<double>() << "ms\n";
            }
            
        } catch (const exception& e) {
            json error_response;
            error_response["error"] = e.what();
            res.status = 500;
            res.set_content(error_response.dump(2), "application/json");
        }
    });
    
    svr.Get("/health", [model_name](const httplib::Request&, httplib::Response& res) {
        json health;
        health["status"] = "ok";
        health["model"] = model_name;
        health["device"] = device.is_mps() ? "MPS" : "CPU";
        health["classes"] = 130;
        health["features"] = json::array({"Korean/English names", "Multipart upload", "MPS acceleration"});
        res.set_content(health.dump(2), "application/json");
    });
    
    cout << "\n🚀 Server starting on http://0.0.0.0:" << port << "\n";
    cout << "============================================================\n";
    
    svr.listen("0.0.0.0", port);
    
    return 0;
}
