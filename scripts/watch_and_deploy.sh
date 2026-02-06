#!/bin/bash
# GPU 서버 모니터링 & 자동 배포 스크립트
# OpenClaw Sub-Agent가 주기적으로 실행
# 사용법: ./scripts/watch_and_deploy.sh

set -e

GPU_SERVER="love-lee@192.168.0.40"
GPU_PASSWORD="1"
STATE_FILE="$HOME/.litecnn_last_deploy.txt"
CHECKPOINT_DIR="~/mycnn/checkpoints_combined"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Discord 알림 함수
notify_discord() {
    "$SCRIPT_DIR/notify_discord.sh" "$1" 2>/dev/null || true
}

# 최신 체크포인트 해시 확인
LATEST_HASH=$(sshpass -p "$GPU_PASSWORD" ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    "md5sum $CHECKPOINT_DIR/LiteCNNPro_best.pth 2>/dev/null | cut -d' ' -f1" || echo "")

if [ -z "$LATEST_HASH" ]; then
    echo "⚠️  GPU 서버에서 체크포인트를 찾을 수 없습니다."
    exit 0
fi

# 이전 배포 해시와 비교
LAST_HASH=""
if [ -f "$STATE_FILE" ]; then
    LAST_HASH=$(cat "$STATE_FILE")
fi

if [ "$LATEST_HASH" == "$LAST_HASH" ]; then
    echo "✅ 최신 모델이 이미 배포되어 있습니다. (해시: $LATEST_HASH)"
    exit 0
fi

# 새 모델 감지!
echo "🔥 새로운 모델 감지! 배포를 시작합니다..."
echo "   이전 해시: $LAST_HASH"
echo "   새 해시: $LATEST_HASH"

# Discord 알림: 새 모델 감지
notify_discord "🔥 **새 모델 감지!**
GPU 서버에서 새로운 모델이 학습되었습니다.
TO-BE 서버(8892) 자동 배포를 시작합니다...

이전 해시: \`${LAST_HASH:0:8}...\`
새 해시: \`${LATEST_HASH:0:8}...\`"

# 배포 스크립트 실행
"$SCRIPT_DIR/deploy_from_gpu.sh" "$CHECKPOINT_DIR/LiteCNNPro_best.pth"

# 성공 시 해시 저장
if [ $? -eq 0 ]; then
    echo "$LATEST_HASH" > "$STATE_FILE"
    echo "🎉 새 모델 배포 완료! 해시가 업데이트되었습니다."
    
    # Discord 알림: 배포 성공
    notify_discord "✅ **배포 완료!**
TO-BE 서버(8892)에 새 모델이 배포되었습니다.

해시: \`${LATEST_HASH:0:8}...\`
포트: \`http://localhost:8892/predict\`
시간: $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo "❌ 배포 실패. 다음 주기에 재시도합니다."
    
    # Discord 알림: 배포 실패
    notify_discord "❌ **배포 실패**
TO-BE 서버(8892) 배포 중 오류가 발생했습니다.
다음 주기(30분 후)에 재시도합니다.

해시: \`${LATEST_HASH:0:8}...\`
로그: \`/tmp/litecnn-deploy.log\`"
    
    exit 1
fi
