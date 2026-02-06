# LiteCNN Pure C++ Inference Server 🖤

**초경량 딥러닝 추론 서버** - PyTorch 모델을 순수 C++로 구현한 경량 추론 엔진

[![Memory](https://img.shields.io/badge/Memory-7MB-brightgreen.svg)](https://github.com)
[![C++17](https://img.shields.io/badge/C++-17-blue.svg)](https://isocpp.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)](https://github.com)
[![Dual Server](https://img.shields.io/badge/Dual%20Server-AS--IS%20%2B%20TO--BE-orange.svg)](https://github.com)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-Auto%20Deploy-success.svg)](https://github.com)

## 🎯 특징

- ⚡ **초경량**: 7MB 메모리 사용 (PyTorch 대비 95% 절감)
- 🚫 **제로 의존성**: 헤더 온리 라이브러리만 사용, 런타임 의존성 없음
- 🌏 **한국어 지원**: 131개 견종의 영문/한글 이름 제공
- 🔌 **HTTP API**: RESTful API로 즉시 사용 가능
- 🏗️ **프로덕션 준비**: 에러 핸들링, 자동 전처리, JSON 응답
- 📦 **단일 바이너리**: 908KB 실행 파일 하나로 완결
- 🔬 **듀얼 서버**: AS-IS (프로덕션) + TO-BE (실험) 동시 운영
- 🤖 **CI/CD**: GPU 서버 학습 완료 시 자동 배포 (~15초)

## 📊 성능 비교

| 구현 방식 | 메모리 사용량 | 감소율 | 의존성 |
|-----------|---------------|--------|--------|
| FastAPI + PyTorch | 322 MB | - | Python, PyTorch, FastAPI |
| LibTorch C++ | 130 MB | 60% | LibTorch (~50-70MB) |
| ONNX Runtime | 102 MB | 68% | ONNX Runtime (~40MB) |
| **Pure C++** | **7 MB** | **98%** | **없음** ✅ |

**실측 (M1 MacBook Air):**
- 바이너리 크기: 908KB
- 메모리 사용량: 7.3MB (포트당)
- 배포 시간: ~15초 (GPU 서버 → M1)
- 추론 시간: <100ms

## 🚀 빠른 시작

### 필요 사항

- C++17 호환 컴파일러 (GCC 7+, Clang 5+, MSVC 2017+)
- CMake 3.14+
- Python 3.7+ (가중치 추출용, 선택 사항)

### 빌드

```bash
# Clone repository
git clone <repository-url>
cd litecnn-pure-cpp

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

# Binary: build/litecnn_server (803KB)
```

### 모델 다운로드

사전 학습된 가중치를 Hugging Face에서 다운로드:

```bash
# 모델 가중치 다운로드
wget https://huggingface.co/2c6829/litecnn-pure-cpp/resolve/main/model_weights.bin -P weights/

# 품종 클래스 다운로드 (한국어 지원)
wget https://huggingface.co/2c6829/litecnn-pure-cpp/resolve/main/breed_classes.json
```

또는 자신의 PyTorch 체크포인트에서 추출:

```bash
python extract_weights.py /path/to/checkpoint.pth weights/model_weights.bin
```

### 실행

#### 단일 서버

```bash
./build/litecnn_server --port 8891 --breeds breed_classes.json --weights weights/model_weights.bin
```

#### 듀얼 서버 (AS-IS + TO-BE)

```bash
# 모든 서버 시작
./scripts/server_manager.sh start all

# 상태 확인
./scripts/server_manager.sh status
```

옵션:
- `--port PORT`: 서버 포트 (기본값: 8080)
- `--weights PATH`: 가중치 파일 경로 (기본값: `weights/model_weights.bin`)
- `--breeds PATH`: 품종 JSON 경로 (기본값: `breed_classes.json`)

## 📡 API 사용법

### Health Check

```bash
curl http://localhost:8891/health
```

응답:
```json
{"status": "ok"}
```

### 이미지 추론

```bash
curl -X POST http://localhost:8891/predict \
  -F "image=@dog.jpg"
```

응답:
```json
{
  "predictions": [
    {
      "class_id": 81,
      "score": 0.9523,
      "breed_en": "Border collie",
      "breed_ko": "보더 콜리"
    },
    {
      "class_id": 106,
      "score": 0.0321,
      "breed_en": "Samoyed",
      "breed_ko": "사모예드"
    }
  ]
}
```

## 🏗️ 아키텍처

### 전체 구조

```
HTTP Request (JPEG/PNG)
    ↓
Image Decoder (stb_image)
    ↓
Resize → 224x224 (stb_image_resize)
    ↓
Normalize (ImageNet mean/std)
    ↓
LiteCNNPro Forward Pass
    ├─ Stem (Conv2D + BN + ReLU6)
    ├─ 7x DepthwiseSeparableConv blocks
    │   └─ SE (Squeeze-Excitation) attention
    └─ Classifier (512→256→120)
    ↓
Softmax + Top-5
    ↓
JSON Response (breed names + scores)
```

### 모델: LiteCNNPro

- **파라미터**: 600K
- **클래스**: 120 (Stanford Dogs)
- **입력**: 224×224 RGB
- **출력**: 120-dim logits

**레이어 구성**:
1. Stem: Conv2D(3→32) + BatchNorm + ReLU6
2. Features: 7x Depthwise Separable Conv blocks
   - Block 0: 32→64 (stride 2)
   - Block 1: 64→128 (stride 2)
   - Block 2-3: 128→256 (stride 2)
   - Block 4-6: 256→512
   - SE (Squeeze-Excitation) attention
3. Classifier: AdaptiveAvgPool → FC(512→256) → FC(256→120)

### 의존성 (헤더 온리)

```
third_party/
├── httplib.h          # HTTP 서버 (cpp-httplib)
├── stb_image.h        # 이미지 디코딩
├── stb_image_resize2.h # 이미지 리사이징
└── json.hpp           # JSON (nlohmann/json)
```

모든 라이브러리가 헤더 온리이므로 **런타임 의존성 없음**.

## 📂 프로젝트 구조

```
litecnn-pure-cpp/
├── CMakeLists.txt          # CMake 빌드 설정
├── README.md               # 이 파일
├── breed_classes.json      # 120개 견종 영문/한글 이름
├── build/                  # 빌드 결과물
│   └── litecnn_server      # 실행 파일 (803KB)
├── docs/
│   └── adr/                # Architecture Decision Records
│       └── 001-pure-cpp-implementation.md
├── include/                # 헤더 파일
│   ├── tensor.h            # Tensor 구조체
│   ├── layers.h            # CNN 레이어 구현
│   ├── model.h             # LiteCNNPro 모델
│   └── server.h            # HTTP 서버
├── src/                    # 구현 파일
│   ├── tensor.cpp          # Tensor 연산 (114줄)
│   ├── layers.cpp          # CNN 레이어 (356줄)
│   ├── model.cpp           # 모델 forward (246줄)
│   ├── server.cpp          # HTTP 서버 (162줄)
│   └── main.cpp            # Entry point (38줄)
├── third_party/            # 헤더 온리 라이브러리
├── scripts/                # 유틸리티 스크립트
│   ├── extract_weights_remote.sh
│   ├── create_dummy_weights.py
│   └── test_memory.sh
└── weights/                # 모델 가중치
    └── model_weights.bin   # 4.0MB
```

**총 코드**: 916줄 (주석 제외)

## 🔧 구현 세부사항

### Tensor 구조

```cpp
struct Tensor {
    std::vector<int> shape;      // [N, C, H, W]
    std::vector<float> data;     // NCHW 메모리 레이아웃
};
```

### 구현된 레이어

1. **Conv2D**: Standard & Depthwise convolution
2. **BatchNorm2D**: Inference mode (running mean/var)
3. **Linear**: Fully connected layer
4. **AdaptiveAvgPool2D**: Global average pooling
5. **ReLU6**: Clipped ReLU activation
6. **Sigmoid**: Logistic activation
7. **SE Block**: Squeeze-Excitation channel attention
8. **Depthwise Separable Conv**: Depthwise + Pointwise

### 가중치 포맷

Binary format (Big Endian):

```
[Magic: "LCNN"] [Version: uint32] [Num Tensors: uint32]

For each tensor:
  [Name Length: uint32] [Name: char[]]
  [Rank: uint32] [Shape: uint32[rank]]
  [Data: float[product(shape)]]
```

Example:
```
4C 43 4E 4E  00 00 00 01  00 00 00 6C  00 00 00 13  # "LCNN", v1, 108 tensors, name_len=19
73 74 65 6D 2E 30 2E 77 65 69 67 68 74           # "stem.0.weight"
00 00 00 04                                       # rank=4
00 00 00 20 00 00 00 03 00 00 00 03 00 00 00 03  # shape=[32,3,3,3]
3F 80 00 00 BF 00 00 00 ...                       # float data
```

## 🎓 학습한 교훈

### 1. 의존성이 적을수록 메모리 효율적

PyTorch/LibTorch의 메모리 사용량 대부분은 **런타임 라이브러리**가 차지합니다:
- LibTorch: ~50-70MB (추론 엔진 + CUDA 지원 등)
- ONNX Runtime: ~40MB (최적화된 추론 전용 엔진)

Pure C++는 **필요한 레이어만 구현**하므로 메모리 절약이 극대화됩니다.

### 2. 헤더 온리 라이브러리의 장점

- **배포 단순화**: 단일 바이너리, 설치 불필요
- **최적화 가능성**: 컴파일 타임에 전체 코드 최적화
- **이식성**: 플랫폼 간 이동 용이

### 3. 조기 최적화가 필요할 때

메모리 제약이 **명확하고 엄격**한 경우 (예: < 50MB), 처음부터 Pure C++ 고려하는 것이 효율적입니다.

### 4. 한국어 지원은 쉽다

JSON 매핑만으로 다국어 지원이 간단히 해결됩니다:

```json
{
  "81": {
    "en": "Border collie",
    "ko": "보더 콜리"
  }
}
```

## 🔮 향후 개선 사항

### 성능 최적화

- [ ] **SIMD 최적화**: AVX2/NEON을 활용한 벡터화
- [ ] **멀티스레딩**: 배치 추론 병렬 처리
- [ ] **Quantization**: INT8 양자화로 메모리 50% 추가 절감

### 기능 추가

- [ ] **배치 추론**: 여러 이미지 동시 처리
- [ ] **웹캠 스트리밍**: 실시간 비디오 추론
- [ ] **모델 업데이트**: 런타임 hot-reload
- [ ] **메트릭**: Prometheus 통합

### 배포

- [ ] **Docker 이미지**: Alpine Linux 기반 (~10MB)
- [ ] **시스템 서비스**: systemd/launchd 통합
- [ ] **벤치마크**: 자동화된 성능 테스트

## 🔬 듀얼 서버 아키텍처

AS-IS (프로덕션)와 TO-BE (실험) 모델을 동시에 운영하여 안전한 모델 비교 및 배포가 가능합니다.

```
포트 8891 (AS-IS)  → weights/model_8891.bin (수동 배포, 안정 버전)
포트 8892 (TO-BE)  → weights/model_8892.bin (자동 배포, 실험 버전)
```

### 서버 관리

```bash
# 모든 서버 시작/중지/재시작
./scripts/server_manager.sh [start|stop|restart] all

# 개별 서버 제어
./scripts/server_manager.sh restart 8891  # AS-IS만 재시작

# 상태 확인
./scripts/server_manager.sh status
```

### A/B 비교

```bash
# AS-IS
curl -X POST http://localhost:8891/predict -F "image=@test.jpg"

# TO-BE
curl -X POST http://localhost:8892/predict -F "image=@test.jpg"
```

상세 문서: [DUAL_SERVER.md](docs/DUAL_SERVER.md), [AB_TESTING.md](docs/AB_TESTING.md)

## 🤖 CI/CD 파이프라인

GPU 서버에서 학습 완료 시 자동으로 TO-BE 모델을 배포합니다 (~15초).

```
GPU 서버 학습 완료
    ↓ (MD5 해시 변경 감지)
체크포인트 다운로드 (SCP)
    ↓
PyTorch → Binary 변환
    ↓
C++ 빌드
    ↓
TO-BE 서버 재시작 (8892)
    ↓
✅ 배포 완료
```

### 수동 배포

```bash
./scripts/deploy_from_gpu.sh
```

### 자동 배포 (30분마다)

```bash
# macOS launchd 등록
launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
```

**알림**: Discord + Telegram 동시 전송 (Telegram 설정 필요)

상세 문서: [CICD.md](docs/CICD.md), [AUTOMATION.md](docs/AUTOMATION.md), [TELEGRAM_SETUP.md](docs/TELEGRAM_SETUP.md)

## 📝 ADR (Architecture Decision Records)

상세한 아키텍처 결정 과정은 [ADR-001](docs/adr/001-pure-cpp-implementation.md)을 참고하세요.

## 📄 라이선스

MIT License

## 🙏 감사의 말

- **cpp-httplib**: 간단하고 강력한 HTTP 서버
- **stb**: 신의 선물 같은 헤더 온리 라이브러리
- **nlohmann/json**: 최고의 C++ JSON 라이브러리

## 🔗 Links

- **GitHub**: https://github.com/stupidcoderJung/litecnn-pure-cpp
- **Hugging Face Model**: https://huggingface.co/2c6829/litecnn-pure-cpp
- **Issues**: https://github.com/stupidcoderJung/litecnn-pure-cpp/issues

---

**Date**: 2026-02-06  
**Memory Usage**: 7MB per server (95% reduction from PyTorch)  
**Dual Server**: AS-IS (8891) + TO-BE (8892)  
**Status**: Production Ready ✅

## MPS-Accelerated Server (Port 8893)

**NEW!** LibTorch + Metal Performance Shaders 최적화 서버

### 성능
- **Inference**: 6-8ms (Pure C++ 대비 35배 빠름)
- **Device**: M1 GPU (MPS)
- **Model**: Cycle 13 (62.60% accuracy)
- **Features**: 
  - 한국어/영어 견종 이름
  - Multipart 이미지 업로드
  - MPS GPU 가속

### 빌드 및 실행
```bash
# 빌드
make -f Makefile.mps

# 실행
./build/litecnn_server_mps
```

### API
```bash
# Health check
curl http://localhost:8893/health

# 이미지 업로드
curl -X POST http://localhost:8893/predict \
  -F "image=@/path/to/dog.jpg" | jq

# JSON 경로
curl -X POST http://localhost:8893/predict \
  -H "Content-Type: application/json" \
  -d '{"image_path": "/path/to/dog.jpg", "top_k": 3}' | jq
```

### 응답 예시
```json
{
  "predictions": [
    {
      "rank": 1,
      "class_id": 12,
      "breed_en": "Border collie",
      "breed_ko": "보더 콜리",
      "confidence": 57.08
    }
  ],
  "timing": {
    "total_ms": 11.103,
    "preprocess_ms": 6.997,
    "inference_ms": 7.486,
    "transfer_ms": 3.509
  }
}
```

## Dual MPS Server Architecture

### Port Configuration
- **8891**: Cycle 11 MPS (Production, 68.36% accuracy)
  - Stable, proven model
  - ~4-5ms inference
  
- **8892**: Cycle N MPS (Latest, experimental)
  - Auto-deployed from GPU server
  - Test new models before promotion to 8891

### Usage
```bash
# Production (Cycle 11)
curl -X POST http://192.168.0.59:8891/predict \
  -F "image=@dog.jpg" | jq

# Latest (Cycle N)
curl -X POST http://192.168.0.59:8892/predict \
  -F "image=@dog.jpg" | jq
```

### Deployment
```bash
# Deploy new cycle to 8892
bash scripts/mps/deploy_latest.sh 14

# If satisfied, promote to 8891:
# 1. Stop 8891
# 2. Convert and deploy new cycle to 8891
# 3. Restart
```
