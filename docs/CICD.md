# CI/CD Pipeline 🚀

GPU 서버에서 학습된 모델을 M1 MacBook Air로 자동 배포하는 파이프라인입니다.

## 아키텍처

```
┌────────────────────────────────────────────────────────────┐
│  GPU 서버 (192.168.0.40)                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  PyTorch 학습 (ThuDogs 131종)                       │   │
│  │  → checkpoints_combined/LiteCNNPro_best.pth (12MB) │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────┬───────────────────────────────────────────────┘
             │
             │ 1. MD5 해시 비교 (변경 감지)
             │ 2. SCP 다운로드
             ↓
┌────────────┴───────────────────────────────────────────────┐
│  M1 MacBook Air (로컬)                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CI/CD 파이프라인                                    │   │
│  │  1. extract_weights.py (PyTorch → Binary 4MB)      │   │
│  │  2. CMake + Make (C++ 빌드 → 908KB)                │   │
│  │  3. 기존 서버 중지                                   │   │
│  │  4. 새 서버 시작 (포트 8891)                        │   │
│  │  5. Health Check & 추론 테스트                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  litecnn_server (Pure C++)                          │   │
│  │  - 메모리: ~15MB                                    │   │
│  │  - 응답시간: <100ms                                 │   │
│  │  - API: http://localhost:8891/predict              │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

## 사용법

### 1. 수동 배포

GPU 서버의 최신 체크포인트를 자동으로 찾아서 배포:

```bash
cd ~/projects/litecnn-pure-cpp
./scripts/deploy_from_gpu.sh
```

특정 체크포인트 배포:

```bash
./scripts/deploy_from_gpu.sh ~/mycnn/checkpoints_cycle8/best_model.pth
```

### 2. 자동 배포 (Cron Job)

OpenClaw Cron Job으로 30분마다 자동 체크:

```bash
# OpenClaw cron 등록
openclaw cron add \
  --name "GPU Model Auto-Deploy" \
  --schedule "*/30 * * * *" \
  --command "cd ~/projects/litecnn-pure-cpp && ./scripts/watch_and_deploy.sh"
```

또는 macOS launchd 사용:

```bash
# ~/Library/LaunchAgents/com.litecnn.autodeploy.plist 생성
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

# 등록 & 시작
launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
launchctl start com.litecnn.autodeploy
```

### 3. OpenClaw Sub-Agent 통합

OpenClaw skill로 패키징하여 Discord 명령어로 배포:

```bash
# Discord에서
!deploy-model

# 또는 자동 감지 활성화
!watch-gpu on
```

## 배포 과정

### Step 1: 체크포인트 다운로드 (SCP)
```
GPU 서버: ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth (12MB)
    ↓ sshpass + scp
로컬: ~/projects/litecnn-pure-cpp/weights/LiteCNNPro_best.pth
```

### Step 2: 가중치 변환 (PyTorch → Binary)
```python
python3 extract_weights.py \
  weights/LiteCNNPro_best.pth \
  weights/model_weights.bin
```

출력: `model_weights.bin` (4.03MB, Big Endian binary format)

### Step 3: C++ 빌드
```bash
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j8
```

출력: `litecnn_server` (908KB ARM64 binary)

최적화 플래그:
- `-Os`: 크기 최적화
- `-ffunction-sections -fdata-sections`: 미사용 코드 제거
- `-Wl,--gc-sections` (Linux) / `-Wl,-dead_strip` (macOS): 링커 최적화

### Step 4: 서버 재시작
```bash
# 기존 프로세스 종료
pkill -f "litecnn_server.*8891"

# 새 서버 시작
./build/litecnn_server \
  --port 8891 \
  --breeds breed_classes.json \
  --weights weights/model_weights.bin &
```

### Step 5: Health Check & 검증
```bash
# Health check
curl http://localhost:8891/health
# → {"status":"ok"}

# 추론 테스트
curl -X POST http://localhost:8891/predict \
  -F "image=@test_border_collie.jpg"
# → {"predictions":[{"breed_ko":"보더 콜리",...}]}
```

## 상태 관리

배포 상태는 `~/.litecnn_last_deploy.txt`에 저장됩니다:

```bash
# 마지막 배포된 모델의 MD5 해시
cat ~/.litecnn_last_deploy.txt
# → a3f8d9e2c1b4...
```

변경 감지 로직:
1. GPU 서버의 최신 체크포인트 MD5 계산
2. 로컬 저장된 MD5와 비교
3. 다르면 → 배포 실행
4. 같으면 → 스킵 (중복 배포 방지)

## 로그 & 디버깅

### 배포 로그
```bash
tail -f /tmp/litecnn-deploy.log
```

### 서버 로그
```bash
tail -f /tmp/litecnn_server_8891.log
```

### 자동 배포 로그 (launchd)
```bash
tail -f /tmp/litecnn-autodeploy.log
```

### 메모리 & 성능 확인
```bash
# 프로세스 메모리 사용량
ps aux | grep litecnn_server

# 추론 응답시간 측정
time curl -X POST http://localhost:8891/predict \
  -F "image=@test.jpg" -s > /dev/null
```

## 성능 지표

| 단계 | 시간 | 설명 |
|------|------|------|
| 1. SCP 다운로드 | ~2초 | 12MB over LAN |
| 2. 가중치 변환 | ~0.5초 | PyTorch → Binary |
| 3. C++ 빌드 | ~8초 | ARM64 optimized |
| 4. 서버 재시작 | ~3초 | Cold start |
| **총 배포 시간** | **~15초** | Full pipeline |

## 문제 해결

### 1. SSH 인증 실패
```bash
# sshpass 설치 확인
which sshpass
brew install hudochenkov/sshpass/sshpass
```

### 2. 빌드 실패
```bash
# CMake 재설정
cd ~/projects/litecnn-pure-cpp
rm -rf build && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
```

### 3. 서버 시작 실패
```bash
# 포트 충돌 확인
lsof -i :8891

# 강제 종료
pkill -9 -f litecnn_server
```

### 4. 추론 결과 이상
```bash
# 가중치 파일 검증
ls -lh weights/model_weights.bin
# → 4.03MB 확인

# 클래스 개수 확인
jq 'keys | length' breed_classes.json
# → 131
```

## 보안 고려사항

⚠️ **현재 구현은 내부 네트워크 전용입니다**

개선 사항:
- [ ] SSH 키 인증으로 전환 (비밀번호 제거)
- [ ] HTTPS 지원 추가
- [ ] API 토큰 인증
- [ ] Rate limiting

## 향후 개선

- [ ] Docker 컨테이너로 격리
- [ ] 배포 롤백 기능
- [ ] A/B 테스트 자동화 (이전 모델과 성능 비교)
- [ ] Slack/Discord 알림 통합
- [ ] 배포 이력 대시보드

---

**마지막 업데이트**: 2026-02-06  
**작성자**: 텔리크로 🖤
