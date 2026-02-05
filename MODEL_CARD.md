# LiteCNNPro Model - Pure C++ Inference

**Ultra-lightweight CNN model for dog breed classification**

## Model Details

- **Model**: LiteCNNPro (Pure C++ implementation)
- **Parameters**: 600K
- **Classes**: 120 (Stanford Dogs dataset)
- **Input**: 224×224 RGB images
- **Framework**: PyTorch (training) → Pure C++ (inference)
- **Memory**: 26MB total (4MB weights + 22MB runtime)

## Architecture

```
Stem: Conv2D(3→32) + BatchNorm + ReLU6
Features: 7× Depthwise Separable Conv blocks
  - Block 0: 32→64 (stride 2)
  - Block 1: 64→128 (stride 2)
  - Block 2-3: 128→256 (stride 2)
  - Block 4-6: 256→512
  - SE (Squeeze-Excitation) attention in each block
Classifier: AdaptiveAvgPool → FC(512→256) → FC(256→120)
```

## Usage

### Download Model

```bash
wget https://huggingface.co/2c6829/litecnn-pure-cpp/resolve/main/model_weights.bin
wget https://huggingface.co/2c6829/litecnn-pure-cpp/resolve/main/breed_classes.json
```

### Build and Run

```bash
# Clone the inference server
git clone https://github.com/stupidcoderJung/litecnn-pure-cpp
cd litecnn-pure-cpp

# Place model files
mv model_weights.bin weights/
mv breed_classes.json .

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# Run server
./litecnn_server --port 8080
```

### API Example

```bash
# Health check
curl http://localhost:8080/health

# Predict
curl -X POST http://localhost:8080/predict \
  -F "image=@dog.jpg"
```

**Response**:
```json
{
  "predictions": [
    {
      "class_id": 81,
      "score": 0.95,
      "breed_en": "Border collie",
      "breed_ko": "보더 콜리"
    }
  ]
}
```

## Performance

| Metric | Value |
|--------|-------|
| Memory (RSS) | 26 MB |
| Binary Size | 803 KB |
| Weights Size | 4.0 MB |
| Inference Time | <100ms (CPU) |

**Comparison**:
- PyTorch: 322 MB → **92% reduction** ✅
- LibTorch: 130 MB → **80% reduction** ✅
- ONNX Runtime: 102 MB → **75% reduction** ✅

## Files

- `model_weights.bin` (4.0 MB) - Model weights in binary format
- `breed_classes.json` (7.4 KB) - 120 dog breeds (English + Korean)
- `extract_weights.py` - PyTorch checkpoint → binary converter

## Training

The model was trained on the Stanford Dogs dataset with:
- Optimizer: AdamW
- Learning rate: 1e-3
- Augmentation: Random flip, rotation, color jitter
- Epochs: 50
- Best validation accuracy: ~85%

## License

MIT License

## Citation

```bibtex
@software{litecnn_pure_cpp_2026,
  author = {LiteCNN Team},
  title = {LiteCNN Pure C++ Inference Server},
  year = {2026},
  url = {https://github.com/stupidcoderJung/litecnn-pure-cpp}
}
```

## Contact

- Repository: https://github.com/stupidcoderJung/litecnn-pure-cpp
- Issues: https://github.com/stupidcoderJung/litecnn-pure-cpp/issues
