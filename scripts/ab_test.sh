#!/usr/bin/env bash
# A/B 테스트 스크립트
# AS-IS (8891) vs TO-BE (8892) 성능 비교

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_IMAGES_DIR="$PROJECT_DIR/test_images"
RESULTS_FILE="/tmp/ab_test_results_$(date +%Y%m%d_%H%M%S).json"

AS_IS_PORT=8891
TO_BE_PORT=8892
AS_IS_URL="http://localhost:$AS_IS_PORT/predict"
TO_BE_URL="http://localhost:$TO_BE_PORT/predict"

# 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 서버 Health Check
check_server() {
    local port=$1
    local name=$2
    
    if curl -s "http://localhost:$port/health" | grep -q '"status":"ok"'; then
        return 0
    else
        error "$name 서버(포트 $port)가 응답하지 않습니다."
        return 1
    fi
}

# 단일 이미지 추론
predict_image() {
    local url=$1
    local image_path=$2
    local start_time=$(date +%s%N)
    
    local response=$(curl -s -X POST "$url" -F "image=@$image_path")
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # JSON 파싱
    local top1_class=$(echo "$response" | jq -r '.predictions[0].class_id' 2>/dev/null || echo "-1")
    local top1_score=$(echo "$response" | jq -r '.predictions[0].score' 2>/dev/null || echo "0")
    local top1_breed=$(echo "$response" | jq -r '.predictions[0].breed_ko' 2>/dev/null || echo "unknown")
    
    echo "{\"class_id\":$top1_class,\"score\":$top1_score,\"breed\":\"$top1_breed\",\"time_ms\":$duration_ms}"
}

# A/B 비교
compare_servers() {
    local image_path=$1
    local ground_truth_class=$2
    
    # AS-IS 추론
    local as_is_result=$(predict_image "$AS_IS_URL" "$image_path")
    local as_is_class=$(echo "$as_is_result" | jq -r '.class_id')
    local as_is_score=$(echo "$as_is_result" | jq -r '.score')
    local as_is_breed=$(echo "$as_is_result" | jq -r '.breed')
    local as_is_time=$(echo "$as_is_result" | jq -r '.time_ms')
    
    # TO-BE 추론
    local to_be_result=$(predict_image "$TO_BE_URL" "$image_path")
    local to_be_class=$(echo "$to_be_result" | jq -r '.class_id')
    local to_be_score=$(echo "$to_be_result" | jq -r '.score')
    local to_be_breed=$(echo "$to_be_result" | jq -r '.breed')
    local to_be_time=$(echo "$to_be_result" | jq -r '.time_ms')
    
    # 정확도 판정
    local as_is_correct="false"
    local to_be_correct="false"
    
    if [ "$as_is_class" == "$ground_truth_class" ]; then
        as_is_correct="true"
    fi
    
    if [ "$to_be_class" == "$ground_truth_class" ]; then
        to_be_correct="true"
    fi
    
    # 결과 JSON
    cat << EOF
{
  "image": "$(basename "$image_path")",
  "ground_truth": $ground_truth_class,
  "as_is": {
    "class_id": $as_is_class,
    "breed": "$as_is_breed",
    "score": $as_is_score,
    "time_ms": $as_is_time,
    "correct": $as_is_correct
  },
  "to_be": {
    "class_id": $to_be_class,
    "breed": "$to_be_breed",
    "score": $to_be_score,
    "time_ms": $to_be_time,
    "correct": $to_be_correct
  }
}
EOF
}

# 메인
main() {
    log "🧪 A/B 테스트 시작"
    echo ""
    
    # Health Check
    info "서버 상태 확인 중..."
    check_server $AS_IS_PORT "AS-IS" || exit 1
    check_server $TO_BE_PORT "TO-BE" || exit 1
    log "✅ 양쪽 서버 정상"
    echo ""
    
    # 테스트 이미지 확인
    if [ ! -d "$TEST_IMAGES_DIR" ] || [ -z "$(ls -A "$TEST_IMAGES_DIR" 2>/dev/null)" ]; then
        error "테스트 이미지가 없습니다: $TEST_IMAGES_DIR"
        info "먼저 ./scripts/prepare_testset.sh를 실행하세요."
        exit 1
    fi
    
    # 결과 초기화
    echo "{\"results\":[" > "$RESULTS_FILE"
    
    local total=0
    local as_is_correct=0
    local to_be_correct=0
    local as_is_time_sum=0
    local to_be_time_sum=0
    
    # 각 클래스 순회
    for CLASS_DIR in "$TEST_IMAGES_DIR"/*; do
        if [ ! -d "$CLASS_DIR" ]; then
            continue
        fi
        
        CLASS_NAME=$(basename "$CLASS_DIR")
        
        # 클래스 ID 매핑 (간단히 breed_classes.json에서 찾기)
        # 일단 Border_collie → 12번으로 하드코딩 (나중에 개선)
        # TODO: 동적 매핑
        
        info "📂 $CLASS_NAME 테스트 중..."
        
        # 해당 클래스의 이미지 처리
        for IMG in "$CLASS_DIR"/*.jpg; do
            if [ ! -f "$IMG" ]; then
                continue
            fi
            
            ((total++))
            
            # Ground truth는 일단 -1 (알 수 없음)
            local result=$(compare_servers "$IMG" "-1")
            
            # 결과 저장
            if [ $total -gt 1 ]; then
                echo "," >> "$RESULTS_FILE"
            fi
            echo "$result" >> "$RESULTS_FILE"
            
            # 통계 업데이트
            local as_is_correct_now=$(echo "$result" | jq -r '.as_is.correct')
            local to_be_correct_now=$(echo "$result" | jq -r '.to_be.correct')
            
            if [ "$as_is_correct_now" == "true" ]; then
                ((as_is_correct++))
            fi
            
            if [ "$to_be_correct_now" == "true" ]; then
                ((to_be_correct++))
            fi
            
            # 응답시간 합산
            as_is_time_sum=$((as_is_time_sum + $(echo "$result" | jq -r '.as_is.time_ms')))
            to_be_time_sum=$((to_be_time_sum + $(echo "$result" | jq -r '.to_be.time_ms')))
            
            echo -n "."
        done
        
        echo ""
    done
    
    # 결과 마무리
    echo "]}" >> "$RESULTS_FILE"
    
    echo ""
    log "✅ 테스트 완료"
    echo ""
    
    # 통계 출력
    info "=== 📊 A/B 테스트 결과 ==="
    echo ""
    echo "총 이미지: $total 개"
    echo ""
    
    if [ $total -gt 0 ]; then
        local as_is_acc=$(awk "BEGIN {printf \"%.2f\", ($as_is_correct/$total)*100}")
        local to_be_acc=$(awk "BEGIN {printf \"%.2f\", ($to_be_correct/$total)*100}")
        local as_is_avg=$(awk "BEGIN {printf \"%.1f\", $as_is_time_sum/$total}")
        local to_be_avg=$(awk "BEGIN {printf \"%.1f\", $to_be_time_sum/$total}")
        
        echo "AS-IS (8891):"
        echo "  정확도: $as_is_acc% ($as_is_correct/$total)"
        echo "  평균 응답시간: ${as_is_avg}ms"
        echo ""
        
        echo "TO-BE (8892):"
        echo "  정확도: $to_be_acc% ($to_be_correct/$total)"
        echo "  평균 응답시간: ${to_be_avg}ms"
        echo ""
        
        # 승자 판정
        local winner="무승부"
        if (( $(echo "$to_be_acc > $as_is_acc" | bc -l) )); then
            winner="TO-BE 🏆"
        elif (( $(echo "$as_is_acc > $to_be_acc" | bc -l) )); then
            winner="AS-IS 🏆"
        fi
        
        echo "🏆 승자: $winner"
        echo ""
    fi
    
    echo "결과 저장: $RESULTS_FILE"
}

main "$@"
