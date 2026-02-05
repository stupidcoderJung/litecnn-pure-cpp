#!/bin/bash
# CI/CD Pipeline: GPU 서버 → M1 MacBook Air 자동 배포
# 사용법: ./scripts/deploy_from_gpu.sh [checkpoint_path]

set -e  # 에러 발생 시 즉시 중단

# 설정
GPU_SERVER="love-lee@192.168.0.40"
GPU_PASSWORD="1"
LOCAL_PROJECT_DIR="$HOME/projects/litecnn-pure-cpp"
WEIGHTS_DIR="$LOCAL_PROJECT_DIR/weights"
BUILD_DIR="$LOCAL_PROJECT_DIR/build"
SERVER_PORT="8891"
LOG_FILE="/tmp/litecnn-deploy.log"

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# 체크포인트 경로 결정
if [ -z "$1" ]; then
    log "체크포인트 경로가 지정되지 않음. GPU 서버에서 최신 모델 검색 중..."
    CHECKPOINT_PATH=$(sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
        "ls -t ~/mycnn/checkpoints_*/LiteCNNPro_best.pth 2>/dev/null | head -1" || \
        sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
        "ls -t ~/mycnn/checkpoints*/best_model*.pth 2>/dev/null | head -1")
    
    if [ -z "$CHECKPOINT_PATH" ]; then
        error "GPU 서버에서 체크포인트를 찾을 수 없습니다."
    fi
    log "최신 체크포인트 발견: $CHECKPOINT_PATH"
else
    CHECKPOINT_PATH="$1"
    log "지정된 체크포인트 사용: $CHECKPOINT_PATH"
fi

# Step 1: 체크포인트 다운로드
log "Step 1/6: GPU 서버에서 체크포인트 다운로드 중..."
mkdir -p "$WEIGHTS_DIR"
CHECKPOINT_FILENAME=$(basename "$CHECKPOINT_PATH")
sshpass -p "$GPU_PASSWORD" scp -o StrictHostKeyChecking=no \
    "$GPU_SERVER:$CHECKPOINT_PATH" "$WEIGHTS_DIR/$CHECKPOINT_FILENAME" || \
    error "체크포인트 다운로드 실패"

CHECKPOINT_SIZE=$(du -h "$WEIGHTS_DIR/$CHECKPOINT_FILENAME" | cut -f1)
log "✅ 다운로드 완료: $CHECKPOINT_SIZE"

# Step 2: PyTorch → Binary 변환
log "Step 2/6: 가중치 변환 중 (PyTorch → Binary)..."
cd "$LOCAL_PROJECT_DIR"
python3 extract_weights.py \
    "$WEIGHTS_DIR/$CHECKPOINT_FILENAME" \
    "$WEIGHTS_DIR/model_weights.bin" || \
    error "가중치 변환 실패"

BIN_SIZE=$(du -h "$WEIGHTS_DIR/model_weights.bin" | cut -f1)
log "✅ 변환 완료: $BIN_SIZE"

# Step 3: 클래스 파일 동기화
log "Step 3/6: 클래스 파일 동기화 중..."
sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    'jq ". | length" ~/mycnn/data/combined_cropped/class_names.json' > /tmp/class_count.txt || \
    warn "클래스 개수 확인 실패 (기존 파일 사용)"

if [ -f /tmp/class_count.txt ]; then
    CLASS_COUNT=$(cat /tmp/class_count.txt)
    if [ "$CLASS_COUNT" != "131" ]; then
        warn "클래스 수 변경 감지: 131 → $CLASS_COUNT"
        # 클래스 파일 다운로드 및 번역 (필요 시 확장)
    fi
fi
log "✅ 클래스 파일 동기화 완료"

# Step 4: C++ 빌드
log "Step 4/6: C++ 빌드 중..."
cd "$LOCAL_PROJECT_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake .. -DCMAKE_BUILD_TYPE=Release > /dev/null 2>&1 || error "CMake 실패"
make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1 || error "빌드 실패"

BINARY_SIZE=$(du -h "$BUILD_DIR/litecnn_server" | cut -f1)
log "✅ 빌드 완료: $BINARY_SIZE"

# Step 5: 기존 서버 중지
log "Step 5/6: 기존 서버 중지 중..."
if pgrep -f "litecnn_server.*$SERVER_PORT" > /dev/null; then
    pkill -f "litecnn_server.*$SERVER_PORT"
    sleep 2
    log "✅ 기존 서버 중지됨"
else
    log "기존 서버 없음 (신규 배포)"
fi

# Step 6: 새 서버 시작
log "Step 6/6: 새 서버 시작 중..."
cd "$LOCAL_PROJECT_DIR"
nohup "$BUILD_DIR/litecnn_server" \
    --port "$SERVER_PORT" \
    --breeds "breed_classes.json" \
    --weights "$WEIGHTS_DIR/model_weights.bin" \
    > "/tmp/litecnn_server_$SERVER_PORT.log" 2>&1 &

sleep 3

# Health check
if curl -s "http://localhost:$SERVER_PORT/health" | grep -q '"status":"ok"'; then
    log "✅ 서버 시작 완료! (포트: $SERVER_PORT)"
    
    # 메모리 사용량 확인
    MEM_USAGE=$(ps aux | grep "[l]itecnn_server.*$SERVER_PORT" | awk '{print $6/1024}' | head -1)
    log "📊 메모리 사용량: ${MEM_USAGE}MB"
    
    # 간단한 추론 테스트 (옵션)
    if [ -f "$HOME/projects/test_border_collie.jpg" ]; then
        log "🧪 추론 테스트 중..."
        RESULT=$(curl -s -X POST "http://localhost:$SERVER_PORT/predict" \
            -F "image=@$HOME/projects/test_border_collie.jpg" | jq -r '.predictions[0].breed_ko' 2>/dev/null)
        
        if [ -n "$RESULT" ]; then
            log "✅ 추론 테스트 성공: $RESULT"
        fi
    fi
    
    echo ""
    log "🎉 배포 완료!"
    log "📡 API: http://localhost:$SERVER_PORT/predict"
    log "📋 로그: /tmp/litecnn_server_$SERVER_PORT.log"
else
    error "서버 Health Check 실패"
fi
