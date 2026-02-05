#!/bin/bash
# 메모리 사용량 측정 스크립트

set -e

BINARY="../build/litecnn_server"
WEIGHTS="../weights/model_weights.bin"

if [ ! -f "$BINARY" ]; then
    echo "❌ 바이너리가 없습니다: $BINARY"
    echo "먼저 빌드를 완료하세요: cd build && make"
    exit 1
fi

if [ ! -f "$WEIGHTS" ]; then
    echo "❌ 가중치 파일이 없습니다: $WEIGHTS"
    echo "먼저 가중치를 추출하세요: bash scripts/extract_weights_remote.sh"
    exit 1
fi

echo "=== LiteCNN 메모리 사용량 테스트 ==="
echo ""

# 바이너리 크기
echo "📦 바이너리 크기:"
ls -lh $BINARY

# 가중치 파일 크기
echo ""
echo "🔢 가중치 파일 크기:"
ls -lh $WEIGHTS

# 총 디스크 사용량
BINARY_SIZE=$(stat -f%z $BINARY 2>/dev/null || stat -c%s $BINARY)
WEIGHTS_SIZE=$(stat -f%z $WEIGHTS 2>/dev/null || stat -c%s $WEIGHTS)
TOTAL_MB=$(echo "scale=2; ($BINARY_SIZE + $WEIGHTS_SIZE) / 1024 / 1024" | bc)

echo ""
echo "💾 총 디스크 사용량: ${TOTAL_MB} MB"

# 서버 시작 후 메모리 측정 (백그라운드)
echo ""
echo "🚀 서버 시작 중 (백그라운드)..."
$BINARY --weights $WEIGHTS --port 8888 > /tmp/litecnn_server.log 2>&1 &
SERVER_PID=$!

# 서버가 시작될 때까지 대기
echo "⏳ 서버 시작 대기 (5초)..."
sleep 5

# 프로세스 메모리 측정 (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    MEMORY_KB=$(ps -o rss= -p $SERVER_PID)
    MEMORY_MB=$(echo "scale=2; $MEMORY_KB / 1024" | bc)
    echo ""
    echo "🧠 런타임 메모리 사용량: ${MEMORY_MB} MB (RSS)"
fi

# 프로세스 종료
echo ""
echo "🛑 서버 종료 중..."
kill $SERVER_PID 2>/dev/null || true
sleep 1

# 최종 보고
echo ""
echo "=========================================="
echo "📊 최종 메모리 보고서"
echo "=========================================="
echo "바이너리:        $(echo "scale=2; $BINARY_SIZE / 1024 / 1024" | bc) MB"
echo "가중치:          $(echo "scale=2; $WEIGHTS_SIZE / 1024 / 1024" | bc) MB"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "런타임 메모리:   ${MEMORY_MB} MB"
    TOTAL_WITH_RUNTIME=$(echo "scale=2; $TOTAL_MB + $MEMORY_MB - ($BINARY_SIZE / 1024 / 1024)" | bc)
    echo "=========================================="
    echo "총 메모리:       ${TOTAL_WITH_RUNTIME} MB"
    
    if (( $(echo "$TOTAL_WITH_RUNTIME < 50" | bc -l) )); then
        echo "✅ 목표 달성! (50MB 이하)"
    else
        echo "⚠️  목표 초과 (50MB)"
    fi
fi
echo "=========================================="
