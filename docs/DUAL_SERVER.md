# 듀얼 서버 아키텍처 🔬

AS-IS (프로덕션)와 TO-BE (실험) 모델을 동시에 운영하는 듀얼 서버 구조입니다.

## 아키텍처

```
┌────────────────────────────────────────────────────────────┐
│  M1 MacBook Air (로컬)                                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  포트 8891 (AS-IS - 프로덕션) 📊                      │  │
│  │  ├─ weights/model_8891.bin                           │  │
│  │  ├─ 수동 배포 (안정 버전)                            │  │
│  │  ├─ 실제 서비스용                                    │  │
│  │  └─ 메모리: ~7MB                                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  포트 8892 (TO-BE - 실험) 🔬                         │  │
│  │  ├─ weights/model_8892.bin                           │  │
│  │  ├─ 자동 배포 (GPU 서버 학습 완료 시)               │  │
│  │  ├─ 테스트 & 비교용                                  │  │
│  │  ├─ head/input/하이퍼파라미터 변경 가능             │  │
│  │  └─ 메모리: ~7MB                                     │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## 서버 관리

### 전체 서버 제어

```bash
# 모든 서버 시작
./scripts/server_manager.sh start all

# 모든 서버 중지
./scripts/server_manager.sh stop all

# 모든 서버 재시작
./scripts/server_manager.sh restart all

# 상태 확인
./scripts/server_manager.sh status
```

### 개별 서버 제어

```bash
# AS-IS 서버만 재시작
./scripts/server_manager.sh restart 8891

# TO-BE 서버만 중지
./scripts/server_manager.sh stop 8892

# TO-BE 서버만 시작
./scripts/server_manager.sh start 8892
```

## 자동 배포 (TO-BE 전용)

GPU 서버에서 학습 완료 시 **TO-BE (8892) 서버만** 자동으로 업데이트됩니다.

### 수동 배포

```bash
cd ~/projects/litecnn-pure-cpp
./scripts/deploy_from_gpu.sh
```

이 스크립트는:
1. GPU 서버에서 최신 체크포인트 다운로드
2. `weights/model_8892.bin`으로 변환
3. 8892 포트 서버 재시작
4. **8891 포트는 건드리지 않음**

### 자동 배포 (Cron)

30분마다 GPU 서버 체크 후 변경 감지 시 자동 배포:

```bash
# macOS launchd 등록
cat > ~/Library/LaunchAgents/com.litecnn.autodeploy.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.litecnn.autodeploy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/young/projects/litecnn-pure-cpp/scripts/watch_and_deploy.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/litecnn-autodeploy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/litecnn-autodeploy-error.log</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
launchctl start com.litecnn.autodeploy
```

## A/B 비교

두 모델의 성능을 쉽게 비교할 수 있습니다.

### 간단한 비교

```bash
# AS-IS
curl -X POST http://localhost:8891/predict \
  -F "image=@test.jpg" | jq '.predictions[0]'

# TO-BE
curl -X POST http://localhost:8892/predict \
  -F "image=@test.jpg" | jq '.predictions[0]'
```

### 배치 비교 스크립트

```bash
#!/bin/bash
# 여러 이미지로 A/B 테스트

for img in test_images/*.jpg; do
    echo "Testing: $img"
    
    echo "  AS-IS (8891):"
    curl -s -X POST http://localhost:8891/predict \
      -F "image=@$img" | jq -r '.predictions[0] | "\(.breed_ko) (\(.score))"'
    
    echo "  TO-BE (8892):"
    curl -s -X POST http://localhost:8892/predict \
      -F "image=@$img" | jq -r '.predictions[0] | "\(.breed_ko) (\(.score))"'
    
    echo ""
done
```

## 가중치 파일 관리

### AS-IS (8891) 업데이트

수동으로만 업데이트합니다 (프로덕션 안정성 보장):

```bash
# 1. 새 가중치 준비
cp new_stable_model.bin ~/projects/litecnn-pure-cpp/weights/model_8891.bin

# 2. AS-IS 서버 재시작
cd ~/projects/litecnn-pure-cpp
./scripts/server_manager.sh restart 8891
```

### TO-BE (8892) 업데이트

자동 배포 또는 수동:

```bash
# 자동: watch_and_deploy.sh가 주기적으로 실행
# 수동: deploy_from_gpu.sh 실행
./scripts/deploy_from_gpu.sh
```

## 모니터링

### 실시간 로그

```bash
# AS-IS 로그
tail -f /tmp/litecnn_server_8891.log

# TO-BE 로그
tail -f /tmp/litecnn_server_8892.log

# 자동 배포 로그
tail -f /tmp/litecnn-autodeploy.log
```

### 메모리 사용량

```bash
ps aux | grep litecnn_server | grep -v grep
```

### 성능 비교

```bash
# 응답시간 측정
echo "AS-IS (8891):"
time curl -s -X POST http://localhost:8891/predict \
  -F "image=@test.jpg" > /dev/null

echo "TO-BE (8892):"
time curl -s -X POST http://localhost:8892/predict \
  -F "image=@test.jpg" > /dev/null
```

## 배포 프로세스

### AS-IS → TO-BE 승격

TO-BE 모델이 충분히 검증되면 AS-IS로 승격:

```bash
# 1. TO-BE 가중치를 AS-IS로 복사
cp weights/model_8892.bin weights/model_8891.bin

# 2. AS-IS 서버 재시작
./scripts/server_manager.sh restart 8891

# 3. 버전 태깅 (선택사항)
git tag -a v1.0.0 -m "Promote TO-BE to AS-IS"
git push origin v1.0.0
```

### TO-BE 롤백

문제 발생 시 이전 버전으로 롤백:

```bash
# 1. 백업에서 복구
cp weights/model_8892.backup.bin weights/model_8892.bin

# 2. TO-BE 서버 재시작
./scripts/server_manager.sh restart 8892
```

## 상태 파일

### 배포 이력

```bash
# 마지막 배포된 TO-BE 모델 해시
cat ~/.litecnn_last_deploy.txt
```

### 버전 관리

```bash
# 현재 실행 중인 모델 정보
./scripts/server_manager.sh status
```

## 문제 해결

### 포트 충돌

```bash
# 포트 사용 확인
lsof -i :8891
lsof -i :8892

# 강제 종료
pkill -9 -f "litecnn_server.*8891"
pkill -9 -f "litecnn_server.*8892"
```

### 메모리 부족

```bash
# 한 서버만 실행
./scripts/server_manager.sh stop 8892  # TO-BE 중지
```

### 가중치 파일 손상

```bash
# 파일 크기 확인
ls -lh weights/*.bin

# 재다운로드
./scripts/deploy_from_gpu.sh
```

## 보안

⚠️ **현재 구성은 내부 네트워크 전용입니다**

프로덕션 배포 시 추가 필요:
- HTTPS/TLS 인증서
- API 토큰 인증
- Rate limiting
- 방화벽 규칙

---

**마지막 업데이트**: 2026-02-06  
**작성자**: 텔리크로 🖤
