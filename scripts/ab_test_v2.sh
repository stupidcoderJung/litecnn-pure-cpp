#!/usr/bin/env bash
# A/B 테스트 스크립트 v2
# Ground Truth 자동 매핑 + 상세 리포트

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_IMAGES_DIR="$PROJECT_DIR/test_images"
BREED_CLASSES_FILE="$PROJECT_DIR/breed_classes.json"
RESULTS_FILE="/tmp/ab_test_results_$(date +%Y%m%d_%H%M%S).json"
REPORT_FILE="/tmp/ab_test_report_$(date +%Y%m%d_%H%M%S).md"

AS_IS_PORT=8891
TO_BE_PORT=8892

# 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 견종명으로 클래스 ID 찾기
find_class_id() {
    local breed_name=$1
    # breed_classes.json에서 breed_ko 또는 breed_en이 매칭되는 클래스 ID 찾기
    jq -r "to_entries[] | select(.value.en | ascii_downcase | contains(\"$(echo "$breed_name" | tr '_' ' ' | tr '-' ' ' | tr 'A-Z' 'a-z')\")) | .key" \
        "$BREED_CLASSES_FILE" | head -1
}

# 서버 Health Check
check_server() {
    local port=$1
    curl -s "http://localhost:$port/health" | grep -q '"status":"ok"'
}

# 단일 이미지 추론
predict_image() {
    local port=$1
    local image_path=$2
    local start_time=$(date +%s%N)
    
    local response=$(curl -s -X POST "http://localhost:$port/predict" -F "image=@$image_path")
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    echo "$response" | jq -c ". + {\"time_ms\": $duration_ms}"
}

# 메인
main() {
    log "🧪 A/B 테스트 v2 시작"
    echo ""
    
    # Health Check
    info "서버 상태 확인 중..."
    check_server $AS_IS_PORT || { error "AS-IS 서버 응답 없음"; exit 1; }
    check_server $TO_BE_PORT || { error "TO-BE 서버 응답 없음"; exit 1; }
    log "✅ 양쪽 서버 정상"
    echo ""
    
    # 테스트 이미지 확인
    if [ ! -d "$TEST_IMAGES_DIR" ] || [ -z "$(ls -A "$TEST_IMAGES_DIR" 2>/dev/null)" ]; then
        error "테스트 이미지 없음: $TEST_IMAGES_DIR"
        exit 1
    fi
    
    # 통계 변수
    local total=0
    local as_is_correct=0
    local to_be_correct=0
    local as_is_time_sum=0
    local to_be_time_sum=0
    local both_correct=0
    local both_wrong=0
    
    # 리포트 초기화
    cat > "$REPORT_FILE" << 'EOF'
# A/B 테스트 리포트

## 테스트 정보
- 날짜: DATE_PLACEHOLDER
- AS-IS 포트: 8891
- TO-BE 포트: 8892

## 상세 결과

| 이미지 | Ground Truth | AS-IS | TO-BE | AS-IS 정확도 | TO-BE 정확도 | 응답시간 (AS-IS/TO-BE) |
|--------|--------------|-------|-------|-------------|-------------|----------------------|
EOF
    
    sed -i '' "s/DATE_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/" "$REPORT_FILE"
    
    # 각 클래스 처리
    for CLASS_DIR in "$TEST_IMAGES_DIR"/*; do
        [ ! -d "$CLASS_DIR" ] && continue
        
        CLASS_NAME=$(basename "$CLASS_DIR")
        
        # 클래스 ID 찾기
        GROUND_TRUTH=$(find_class_id "$CLASS_NAME")
        
        if [ -z "$GROUND_TRUTH" ]; then
            info "⚠️  $CLASS_NAME: 클래스 ID를 찾을 수 없음 (스킵)"
            continue
        fi
        
        info "📂 $CLASS_NAME (클래스 $GROUND_TRUTH) 테스트 중..."
        
        for IMG in "$CLASS_DIR"/*.jpg; do
            [ ! -f "$IMG" ] && continue
            
            ((total++))
            
            # 양쪽 서버 추론
            AS_IS_RESULT=$(predict_image $AS_IS_PORT "$IMG")
            TO_BE_RESULT=$(predict_image $TO_BE_PORT "$IMG")
            
            # 결과 파싱
            AS_IS_CLASS=$(echo "$AS_IS_RESULT" | jq -r '.predictions[0].class_id')
            AS_IS_SCORE=$(echo "$AS_IS_RESULT" | jq -r '.predictions[0].score')
            AS_IS_BREED=$(echo "$AS_IS_RESULT" | jq -r '.predictions[0].breed_ko')
            AS_IS_TIME=$(echo "$AS_IS_RESULT" | jq -r '.time_ms')
            
            TO_BE_CLASS=$(echo "$TO_BE_RESULT" | jq -r '.predictions[0].class_id')
            TO_BE_SCORE=$(echo "$TO_BE_RESULT" | jq -r '.predictions[0].score')
            TO_BE_BREED=$(echo "$TO_BE_RESULT" | jq -r '.predictions[0].breed_ko')
            TO_BE_TIME=$(echo "$TO_BE_RESULT" | jq -r '.time_ms')
            
            # 정확도 판정
            AS_IS_CORRECT="❌"
            TO_BE_CORRECT="❌"
            
            if [ "$AS_IS_CLASS" == "$GROUND_TRUTH" ]; then
                AS_IS_CORRECT="✅"
                ((as_is_correct++))
            fi
            
            if [ "$TO_BE_CLASS" == "$GROUND_TRUTH" ]; then
                TO_BE_CORRECT="✅"
                ((to_be_correct++))
            fi
            
            if [ "$AS_IS_CORRECT" == "✅" ] && [ "$TO_BE_CORRECT" == "✅" ]; then
                ((both_correct++))
            elif [ "$AS_IS_CORRECT" == "❌" ] && [ "$TO_BE_CORRECT" == "❌" ]; then
                ((both_wrong++))
            fi
            
            # 응답시간 합산
            as_is_time_sum=$((as_is_time_sum + AS_IS_TIME))
            to_be_time_sum=$((to_be_time_sum + TO_BE_TIME))
            
            # 리포트에 추가
            echo "| $(basename "$IMG") | $GROUND_TRUTH | $AS_IS_BREED ($AS_IS_CLASS) | $TO_BE_BREED ($TO_BE_CLASS) | $AS_IS_CORRECT | $TO_BE_CORRECT | ${AS_IS_TIME}ms / ${TO_BE_TIME}ms |" >> "$REPORT_FILE"
            
            echo -n "."
        done
        
        echo ""
    done
    
    echo ""
    log "✅ 테스트 완료"
    echo ""
    
    # 통계 계산
    if [ $total -eq 0 ]; then
        error "테스트된 이미지가 없습니다."
        exit 1
    fi
    
    AS_IS_ACC=$(awk "BEGIN {printf \"%.2f\", ($as_is_correct/$total)*100}")
    TO_BE_ACC=$(awk "BEGIN {printf \"%.2f\", ($to_be_correct/$total)*100}")
    AS_IS_AVG=$(awk "BEGIN {printf \"%.1f\", $as_is_time_sum/$total}")
    TO_BE_AVG=$(awk "BEGIN {printf \"%.1f\", $to_be_time_sum/$total}")
    
    # 통계 출력
    info "=== 📊 A/B 테스트 결과 ==="
    echo ""
    echo "총 이미지: $total 개"
    echo ""
    echo "AS-IS (8891):"
    echo "  정확도: $AS_IS_ACC% ($as_is_correct/$total)"
    echo "  평균 응답시간: ${AS_IS_AVG}ms"
    echo ""
    echo "TO-BE (8892):"
    echo "  정확도: $TO_BE_ACC% ($to_be_correct/$total)"
    echo "  평균 응답시간: ${TO_BE_AVG}ms"
    echo ""
    echo "양쪽 모두 정답: $both_correct"
    echo "양쪽 모두 오답: $both_wrong"
    echo ""
    
    # 승자 판정
    WINNER="무승부"
    if (( $(echo "$TO_BE_ACC > $AS_IS_ACC + 1.0" | bc -l) )); then
        WINNER="TO-BE 🏆 (정확도 ${TO_BE_ACC}% > ${AS_IS_ACC}%)"
    elif (( $(echo "$AS_IS_ACC > $TO_BE_ACC + 1.0" | bc -l) )); then
        WINNER="AS-IS 🏆 (정확도 ${AS_IS_ACC}% > ${TO_BE_ACC}%)"
    fi
    
    echo "🏆 승자: $WINNER"
    echo ""
    
    # 리포트에 요약 추가
    cat >> "$REPORT_FILE" << EOF

## 요약

- **총 이미지**: $total 개
- **AS-IS 정확도**: $AS_IS_ACC% ($as_is_correct/$total)
- **TO-BE 정확도**: $TO_BE_ACC% ($to_be_correct/$total)
- **AS-IS 평균 응답시간**: ${AS_IS_AVG}ms
- **TO-BE 평균 응답시간**: ${TO_BE_AVG}ms
- **양쪽 모두 정답**: $both_correct 개
- **양쪽 모두 오답**: $both_wrong 개

## 승자

$WINNER

---
생성: $(date '+%Y-%m-%d %H:%M:%S')
EOF
    
    echo "📄 리포트 저장: $REPORT_FILE"
    
    # Discord 알림 (옵션)
    if [ "$1" == "--notify" ]; then
        "$SCRIPT_DIR/notify.sh" "📊 **A/B 테스트 완료**

총 이미지: $total 개

**AS-IS (8891)**:
- 정확도: $AS_IS_ACC% ($as_is_correct/$total)
- 평균 응답시간: ${AS_IS_AVG}ms

**TO-BE (8892)**:
- 정확도: $TO_BE_ACC% ($to_be_correct/$total)
- 평균 응답시간: ${TO_BE_AVG}ms

🏆 승자: $WINNER

리포트: \`$REPORT_FILE\`"
    fi
}

main "$@"
