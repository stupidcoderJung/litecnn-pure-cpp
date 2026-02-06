#!/usr/bin/env bash
# AS-IS 모델 롤백 스크립트
# 사용법: ./rollback.sh [backup_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WEIGHTS_DIR="$PROJECT_DIR/weights"
BACKUP_DIR="$PROJECT_DIR/backups"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 백업 목록 표시
list_backups() {
    log "💾 사용 가능한 백업 목록:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.bin 2>/dev/null)" ]; then
        warn "백업 파일이 없습니다."
        exit 1
    fi
    
    local count=1
    for backup in "$BACKUP_DIR"/model_8891_backup_*.bin; do
        local filename=$(basename "$backup")
        local timestamp=$(echo "$filename" | sed 's/model_8891_backup_//' | sed 's/.bin//')
        local size=$(du -h "$backup" | cut -f1)
        
        echo "  [$count] $filename"
        echo "      시간: $timestamp"
        echo "      크기: $size"
        echo ""
        
        ((count++))
    done
}

# 롤백 수행
perform_rollback() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        error "백업 파일을 찾을 수 없습니다: $backup_file"
        exit 1
    fi
    
    log "🔄 롤백 수행 중..."
    echo "  백업: $(basename "$backup_file")"
    echo ""
    
    # 현재 모델 임시 백업
    if [ -f "$WEIGHTS_DIR/model_8891.bin" ]; then
        local temp_backup="$BACKUP_DIR/model_8891_before_rollback_$(date +%Y%m%d_%H%M%S).bin"
        cp "$WEIGHTS_DIR/model_8891.bin" "$temp_backup"
        info "현재 모델 임시 백업: $(basename "$temp_backup")"
    fi
    
    # 백업 파일로 복원
    cp "$backup_file" "$WEIGHTS_DIR/model_8891.bin"
    log "✅ 모델 파일 복원 완료"
    
    # AS-IS 서버 재시작
    log "🔄 AS-IS 서버 재시작 중..."
    "$SCRIPT_DIR/server_manager.sh" restart 8891
    
    log "✅ 롤백 완료!"
}

# 메인
main() {
    log "⏮️  AS-IS 모델 롤백 시작"
    echo ""
    
    if [ -z "$1" ]; then
        # 백업 파일이 지정되지 않으면 목록 표시
        list_backups
        echo ""
        echo "사용법: $0 <backup_filename>"
        echo "예시: $0 model_8891_backup_20260206_092530.bin"
        exit 0
    fi
    
    # 백업 파일 경로 결정
    BACKUP_FILE="$1"
    
    # 파일명만 주어진 경우 전체 경로 생성
    if [[ "$BACKUP_FILE" != /* ]]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    fi
    
    # 확인 메시지
    warn "⚠️  다음 백업으로 롤백합니다:"
    echo "  파일: $(basename "$BACKUP_FILE")"
    echo ""
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "롤백 취소됨"
        exit 0
    fi
    
    # 롤백 수행
    perform_rollback "$BACKUP_FILE"
    echo ""
    
    # 알림
    "$SCRIPT_DIR/notify.sh" "⏮️  **모델 롤백 완료**

AS-IS(8891) 모델이 백업으로 복원되었습니다.

📦 **복원된 백업**:
- 파일: \`$(basename "$BACKUP_FILE")\`

시간: $(date '+%Y-%m-%d %H:%M:%S')"
    
    log "🎉 롤백 완료!"
}

main "$@"
