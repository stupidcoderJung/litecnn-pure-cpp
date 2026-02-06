#!/usr/bin/env bash
# TO-BE → AS-IS 자동 승격 스크립트
# 사용법: ./promote.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WEIGHTS_DIR="$PROJECT_DIR/weights"
BACKUP_DIR="$PROJECT_DIR/backups"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 승격 조건 확인
check_promotion_criteria() {
    log "🔍 승격 조건 확인 중..."
    
    # A/B 테스트 실행
    local test_result=$("$SCRIPT_DIR/ab_test_v2.sh" 2>&1)
    
    # 정확도 추출
    local as_is_acc=$(echo "$test_result" | grep "AS-IS (8891):" -A 1 | grep "정확도:" | awk '{print $2}' | tr -d '%')
    local to_be_acc=$(echo "$test_result" | grep "TO-BE (8892):" -A 1 | grep "정확도:" | awk '{print $2}' | tr -d '%')
    
    echo "  AS-IS 정확도: $as_is_acc%"
    echo "  TO-BE 정확도: $to_be_acc%"
    echo ""
    
    # 승격 조건: TO-BE 정확도가 AS-IS보다 높거나 같음
    if (( $(echo "$to_be_acc >= $as_is_acc" | bc -l) )); then
        log "✅ 승격 조건 충족 (TO-BE >= AS-IS)"
        return 0
    else
        warn "❌ 승격 조건 미달 (TO-BE < AS-IS)"
        return 1
    fi
}

# 백업 생성
create_backup() {
    log "💾 AS-IS 모델 백업 중..."
    
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/model_8891_backup_$timestamp.bin"
    
    if [ -f "$WEIGHTS_DIR/model_8891.bin" ]; then
        cp "$WEIGHTS_DIR/model_8891.bin" "$backup_file"
        log "✅ 백업 완료: $backup_file"
        
        # 배포 정보도 백업
        if [ -f "$HOME/.litecnn_last_deploy_info.json" ]; then
            cp "$HOME/.litecnn_last_deploy_info.json" "$BACKUP_DIR/deploy_info_$timestamp.json"
        fi
        
        echo "$backup_file"
    else
        error "AS-IS 모델 파일이 없습니다."
        exit 1
    fi
}

# 승격 수행
perform_promotion() {
    log "🚀 TO-BE → AS-IS 승격 수행 중..."
    
    # TO-BE 모델을 AS-IS로 복사
    if [ -f "$WEIGHTS_DIR/model_8892.bin" ]; then
        cp "$WEIGHTS_DIR/model_8892.bin" "$WEIGHTS_DIR/model_8891.bin"
        log "✅ 모델 파일 승격 완료"
    else
        error "TO-BE 모델 파일이 없습니다."
        return 1
    fi
    
    # AS-IS 서버 재시작
    log "🔄 AS-IS 서버 재시작 중..."
    "$SCRIPT_DIR/server_manager.sh" restart 8891
    
    log "✅ 승격 완료!"
}

# 메인
main() {
    log "🎯 TO-BE → AS-IS 승격 프로세스 시작"
    echo ""
    
    # --force 옵션 확인
    if [ "$1" != "--force" ]; then
        # 승격 조건 확인
        if ! check_promotion_criteria; then
            error "승격 조건을 만족하지 않습니다."
            echo ""
            echo "강제 승격하려면: $0 --force"
            exit 1
        fi
    else
        warn "⚠️  강제 승격 모드 (조건 확인 스킵)"
        echo ""
    fi
    
    # 백업 생성
    BACKUP_FILE=$(create_backup)
    echo ""
    
    # 승격 수행
    perform_promotion
    echo ""
    
    # 알림
    "$SCRIPT_DIR/notify.sh" "✅ **모델 승격 완료**

TO-BE(8892) → AS-IS(8891) 승격이 완료되었습니다.

📦 **백업**:
- 파일: \`$(basename "$BACKUP_FILE")\`
- 경로: \`$BACKUP_DIR\`

🔄 **롤백**:
\`\`\`
./scripts/rollback.sh $(basename "$BACKUP_FILE")
\`\`\`

시간: $(date '+%Y-%m-%d %H:%M:%S')"
    
    log "🎉 모든 작업 완료!"
}

main "$@"
