#!/usr/bin/env bash
# 듀얼 서버 관리 스크립트
# 사용법: ./scripts/server_manager.sh [start|stop|restart|status] [8891|8892|all]

set -e

PROJECT_DIR="$HOME/projects/litecnn-pure-cpp"
BUILD_DIR="$PROJECT_DIR/build"
WEIGHTS_DIR="$PROJECT_DIR/weights"
BREEDS_FILE="$PROJECT_DIR/breed_classes.json"

# 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 가중치 파일 매핑 함수
get_weights_file() {
    case "$1" in
        8891) echo "model_8891.bin" ;;  # AS-IS (프로덕션)
        8892) echo "model_8892.bin" ;;  # TO-BE (자동 배포)
        *) echo "" ;;
    esac
}

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 서버 상태 확인
check_server() {
    local port=$1
    if pgrep -f "litecnn_server.*--port $port" > /dev/null; then
        return 0  # 실행 중
    else
        return 1  # 중지
    fi
}

# 서버 시작
start_server() {
    local port=$1
    local weights_file=$(get_weights_file $port)
    
    if [ -z "$weights_file" ]; then
        error "알 수 없는 포트: $port"
    fi
    
    if check_server $port; then
        warn "포트 $port 서버가 이미 실행 중입니다."
        return
    fi
    
    if [ ! -f "$WEIGHTS_DIR/$weights_file" ]; then
        error "가중치 파일 없음: $WEIGHTS_DIR/$weights_file"
    fi
    
    log "포트 $port 서버 시작 중... (가중치: $weights_file)"
    
    nohup "$BUILD_DIR/litecnn_server" \
        --port "$port" \
        --breeds "$BREEDS_FILE" \
        --weights "$WEIGHTS_DIR/$weights_file" \
        > "/tmp/litecnn_server_$port.log" 2>&1 &
    
    sleep 2
    
    if curl -s "http://localhost:$port/health" | grep -q '"status":"ok"'; then
        local mem=$(ps aux | grep "[l]itecnn_server.*--port $port" | awk '{print $6/1024}' | head -1)
        log "✅ 포트 $port 시작 완료 (메모리: ${mem}MB)"
    else
        error "포트 $port Health Check 실패"
    fi
}

# 서버 중지
stop_server() {
    local port=$1
    
    if ! check_server $port; then
        warn "포트 $port 서버가 실행 중이 아닙니다."
        return
    fi
    
    log "포트 $port 서버 중지 중..."
    pkill -f "litecnn_server.*--port $port"
    sleep 1
    
    if ! check_server $port; then
        log "✅ 포트 $port 중지 완료"
    else
        error "포트 $port 중지 실패"
    fi
}

# 서버 상태 출력
status_server() {
    local port=$1
    local weights_file=$(get_weights_file $port)
    
    if check_server $port; then
        local pid=$(pgrep -f "litecnn_server.*--port $port" | head -1)
        local mem=$(ps aux | grep "[l]itecnn_server.*--port $port" | awk '{print $6/1024}' | head -1)
        local uptime=$(ps -p $pid -o etime= | xargs)
        
        echo -e "${GREEN}✓${NC} 포트 $port: ${GREEN}실행 중${NC}"
        echo "  PID: $pid"
        echo "  메모리: ${mem}MB"
        echo "  가동시간: $uptime"
        echo "  가중치: $weights_file"
        echo "  API: http://localhost:$port/predict"
        echo "  로그: /tmp/litecnn_server_$port.log"
    else
        echo -e "${RED}✗${NC} 포트 $port: ${RED}중지됨${NC}"
        echo "  가중치: $weights_file"
    fi
    echo ""
}

# 메인 로직
ACTION=${1:-status}
TARGET=${2:-all}

case "$ACTION" in
    start)
        if [ "$TARGET" == "all" ]; then
            start_server 8891
            start_server 8892
        else
            start_server $TARGET
        fi
        ;;
    
    stop)
        if [ "$TARGET" == "all" ]; then
            stop_server 8891
            stop_server 8892
        else
            stop_server $TARGET
        fi
        ;;
    
    restart)
        if [ "$TARGET" == "all" ]; then
            stop_server 8891
            stop_server 8892
            sleep 1
            start_server 8891
            start_server 8892
        else
            stop_server $TARGET
            sleep 1
            start_server $TARGET
        fi
        ;;
    
    status)
        info "=== LiteCNN 서버 상태 ==="
        echo ""
        
        if [ "$TARGET" == "all" ]; then
            echo -e "${BLUE}📊 AS-IS (프로덕션)${NC}"
            status_server 8891
            
            echo -e "${BLUE}🔬 TO-BE (실험)${NC}"
            status_server 8892
        else
            status_server $TARGET
        fi
        ;;
    
    *)
        echo "사용법: $0 [start|stop|restart|status] [8891|8892|all]"
        echo ""
        echo "예시:"
        echo "  $0 start all          # 모든 서버 시작"
        echo "  $0 stop 8892          # TO-BE 서버만 중지"
        echo "  $0 restart 8891       # AS-IS 서버 재시작"
        echo "  $0 status             # 모든 서버 상태 확인"
        exit 1
        ;;
esac
