#!/usr/bin/env bash
# 서버 상태 리포트 생성 및 Discord 전송
# 사용법: ./scripts/status_report.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 서버 상태 수집
collect_status() {
    local port=$1
    local name=$2
    
    if pgrep -f "litecnn_server.*--port $port" > /dev/null; then
        local pid=$(pgrep -f "litecnn_server.*--port $port" | head -1)
        local mem=$(ps aux | grep "[l]itecnn_server.*--port $port" | awk '{print $6/1024}' | head -1)
        local uptime=$(ps -p $pid -o etime= | xargs)
        
        echo "✅ **$name (포트 $port)**"
        echo "- 상태: 실행 중"
        echo "- PID: $pid"
        echo "- 메모리: ${mem}MB"
        echo "- 가동시간: $uptime"
    else
        echo "❌ **$name (포트 $port)**"
        echo "- 상태: 중지됨"
    fi
    echo ""
}

# 배포 이력 확인
last_deploy_info() {
    if [ -f "$HOME/.litecnn_last_deploy.txt" ]; then
        local hash=$(cat "$HOME/.litecnn_last_deploy.txt")
        echo "📦 **마지막 배포**"
        echo "- TO-BE 해시: \`${hash:0:8}...\`"
        
        # 상세 정보 파일이 있으면 추가 표시
        if [ -f "$HOME/.litecnn_last_deploy_info.json" ]; then
            local cycle=$(grep -o '"cycle":"[^"]*"' "$HOME/.litecnn_last_deploy_info.json" | cut -d'"' -f4)
            local model=$(grep -o '"model":"[^"]*"' "$HOME/.litecnn_last_deploy_info.json" | cut -d'"' -f4)
            local path=$(grep -o '"path":"[^"]*"' "$HOME/.litecnn_last_deploy_info.json" | cut -d'"' -f4)
            
            echo "- Cycle: \`$cycle\`"
            echo "- 모델명: \`$model\`"
            echo "- 경로: \`$path\`"
        fi
    else
        echo "📦 **마지막 배포**: 없음"
    fi
    echo ""
}

# 자동 배포 상태
autodeploy_status() {
    if launchctl list | grep -q "com.litecnn.autodeploy"; then
        local pid=$(launchctl list | grep "com.litecnn.autodeploy" | awk '{print $1}')
        echo "🤖 **자동 배포**"
        echo "- 상태: 활성화 ✅"
        echo "- PID: $pid"
        echo "- 체크 주기: 30분"
    else
        echo "🤖 **자동 배포**"
        echo "- 상태: 비활성화 ❌"
    fi
    echo ""
}

# 리포트 생성
REPORT="📊 **LiteCNN 서버 상태 리포트**
$(date '+%Y-%m-%d %H:%M:%S')

$(collect_status 8891 "AS-IS (프로덕션)")
$(collect_status 8892 "TO-BE (실험)")
$(last_deploy_info)
$(autodeploy_status)
API 엔드포인트:
- AS-IS: \`http://localhost:8891/predict\`
- TO-BE: \`http://localhost:8892/predict\`"

# 콘솔 출력
echo "$REPORT"
echo ""

# Discord 전송 (옵션)
if [ "$1" == "--discord" ]; then
    "$SCRIPT_DIR/notify.sh" "$REPORT"
fi
