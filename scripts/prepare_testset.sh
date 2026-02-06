#!/usr/bin/env bash
# ThuDogs 테스트셋 샘플 다운로드
# 각 클래스에서 N개씩 샘플링하여 로컬로 가져옴

set -e

GPU_SERVER="love-lee@192.168.0.40"
GPU_PASSWORD="1"
REMOTE_DATA_DIR="~/mycnn/data/thudogs/low-resolution"
LOCAL_TEST_DIR="$HOME/projects/litecnn-pure-cpp/test_images"
SAMPLES_PER_CLASS=5  # 각 클래스당 5개 샘플

echo "📦 ThuDogs 테스트셋 준비 중..."
echo "   샘플 수: 클래스당 $SAMPLES_PER_CLASS 개"

# 로컬 디렉토리 생성
mkdir -p "$LOCAL_TEST_DIR"

# 클래스 목록 가져오기
echo "🔍 클래스 목록 조회 중..."
CLASSES=$(sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    "ls -d $REMOTE_DATA_DIR/*/ 2>/dev/null" | head -20)  # 테스트용 20개 클래스

CLASS_COUNT=0
IMAGE_COUNT=0

for CLASS_DIR in $CLASSES; do
    CLASS_NAME=$(basename "$CLASS_DIR")
    
    # 클래스 ID 추출 (예: 2594-n000109-Border_collie → 클래스 ID 확인 필요)
    # 일단 폴더명으로 저장
    
    echo "📂 $CLASS_NAME 처리 중..."
    
    # 해당 클래스에서 N개 이미지 랜덤 샘플링
    IMAGES=$(sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
        "ls $CLASS_DIR*.jpg 2>/dev/null | shuf | head -$SAMPLES_PER_CLASS")
    
    # 로컬 디렉토리 생성
    mkdir -p "$LOCAL_TEST_DIR/$CLASS_NAME"
    
    # 이미지 다운로드
    for IMG in $IMAGES; do
        IMG_NAME=$(basename "$IMG")
        sshpass -p "$GPU_PASSWORD" scp -o StrictHostKeyChecking=no \
            "$GPU_SERVER:$IMG" "$LOCAL_TEST_DIR/$CLASS_NAME/$IMG_NAME" 2>/dev/null && \
            ((IMAGE_COUNT++))
    done
    
    ((CLASS_COUNT++))
done

echo ""
echo "✅ 테스트셋 준비 완료!"
echo "   클래스: $CLASS_COUNT 개"
echo "   이미지: $IMAGE_COUNT 개"
echo "   경로: $LOCAL_TEST_DIR"
