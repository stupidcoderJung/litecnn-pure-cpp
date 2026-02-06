# CI/CD Pipeline

## Overview

Automated deployment pipeline from GPU server to M1 Mac MPS server.

## Architecture

```
GPU Server (192.168.0.40)
  ├─ Train model (Cycle N)
  ├─ Save best_model.pth
  └─ Trigger export (manual or automatic)
       ↓
  ├─ Export to TorchScript (MPS-optimized)
  ├─ Transfer to M1 Mac
       ↓
M1 MacBook Air (192.168.0.59)
  ├─ Watch for new models (every 30 min)
  ├─ Download TorchScript model
  ├─ Build & Deploy MPS server
  └─ Notify Discord
```

## Components

### 1. GPU Server Export Script
**Location**: `scripts/mps/export_model.py`

Converts PyTorch checkpoint to TorchScript:
```bash
python3 scripts/mps/export_model.py
```

### 2. M1 Mac Watcher
**Location**: `scripts/mps/watch_and_deploy_mps.sh`

Monitors GPU server for new training cycles:
- Runs every 30 minutes (LaunchAgent)
- Checks for new `checkpoints_cycleN/` directories
- Downloads and deploys automatically

### 3. M1 Mac Deployer
**Location**: `scripts/mps/deploy_mps_server.sh`

Deploys MPS server locally:
```bash
bash scripts/mps/deploy_mps_server.sh
```

### 4. LaunchAgent
**Location**: `~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist`

Runs watcher every 30 minutes:
```bash
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

## Manual Deployment

### From GPU Server
```bash
# On GPU server
cd ~/mycnn
bash /path/to/scripts/mps/deploy_from_gpu.sh 13
```

### On M1 Mac
```bash
# Build and run
cd ~/projects/litecnn-pure-cpp
make -f Makefile.mps
./build/litecnn_server_mps
```

## Automatic Deployment

### Setup (One-time)

1. **Install LaunchAgent**:
```bash
cp scripts/mps/com.litecnn.mps.autodeploy.plist \
   ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

2. **Verify**:
```bash
launchctl list | grep litecnn
tail -f /tmp/mps-autodeploy.log
```

### Workflow

1. **Train** new model on GPU server (Cycle N)
2. **Save** `checkpoints_cycleN/best_model.pth`
3. **Wait** up to 30 minutes (or trigger manually)
4. **Automatic**:
   - Watcher detects new cycle
   - Exports to TorchScript
   - Downloads to M1 Mac
   - Deploys MPS server
   - Sends Discord notification

## Monitoring

### Status
```bash
launchctl list | grep litecnn
```

### Logs
```bash
# Auto-deploy watcher
tail -f /tmp/mps-autodeploy.log

# Server
tail -f /tmp/mps_server.log
```

### Health Check
```bash
curl http://localhost:8893/health | jq
```

## Troubleshooting

### Watcher not running
```bash
launchctl unload ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

### Manual trigger
```bash
bash /Users/young/projects/litecnn-pure-cpp/scripts/mps/watch_and_deploy_mps.sh
```

### Check state
```bash
cat /tmp/mps-autodeploy-state.txt  # Last deployed cycle
```

## Port Configuration

- **8891**: AS-IS (Pure C++ production, legacy)
- **8892**: TO-BE (Pure C++ experimental, legacy)
- **8893**: MPS (LibTorch GPU-accelerated) ← **Main Production**

## Deployment History

State file: `/tmp/mps-autodeploy-state.txt`

View deployment log:
```bash
grep "Deployment Complete" /tmp/mps-autodeploy.log
```

## FAQ

### Q1: Cycle 번호가 매번 바뀌는데 자동 감지되나요?
**A**: ✅ **네, 완전히 자동입니다!**

스크립트는 Cycle 번호를 하드코딩하지 않습니다. 매번 GPU 서버를 스캔해서:
```bash
checkpoints_cycle* 디렉토리 전체 검색
→ 숫자만 추출
→ 정렬해서 가장 큰 값 선택
```

**예시:**
- GPU 서버에 `checkpoints_cycle14`, `cycle15`, `cycle20` 존재
- 자동 감지: **20** (가장 최신)
- State 파일이 `15`라면?
  - 20 > 15 → ✅ **Cycle 20 자동 배포**

### Q2: 여러 Cycle이 동시에 생성되면?
**A**: 가장 최신 Cycle만 배포합니다.

**시나리오:**
```
시간 T0: State = 13
시간 T1: Cycle 14 생성
시간 T2: Cycle 15 생성
시간 T3: Cycle 16 생성
시간 T4: [30분 경과, 자동 체크]
        → 최신 = 16
        → State = 13
        → 16 > 13 → Cycle 16만 배포 ✅
        → State = 16
```

중간 Cycle (14, 15)은 건너뜁니다. 항상 **최신 모델만 프로덕션**에 배포됩니다.

### Q3: 배포 실패 시 재시도하나요?
**A**: 30분마다 재시도합니다.

**예시:**
```
시도 1 (13:00): Cycle 14 배포 실패 (네트워크 오류)
                → State 파일 업데이트 안됨 (여전히 13)
시도 2 (13:30): Cycle 14 재감지 (14 > 13)
                → 재시도 ✅
```

### Q4: Cycle 번호가 뒤로 갈 수 있나요? (예: 15 → 14)
**A**: State 파일이 보호합니다.

```
현재 State = 15
GPU 서버 최신 = 14 (이전 Cycle)
→ 14 < 15
→ "새 Cycle 없음" 판단
→ 배포 안함 ✅
```

### Q5: 수동으로 특정 Cycle 배포하려면?
**A**: State 파일을 수정하세요.

```bash
# Cycle 10을 다시 배포하고 싶다면
echo "9" > /tmp/mps-autodeploy-state.txt

# 다음 자동 체크 시 (최신 Cycle이 10 이상이면)
# → Cycle 10 (또는 그 이상) 배포됨
```

또는 직접 스크립트 실행:
```bash
bash /Users/young/projects/litecnn-pure-cpp/scripts/mps/watch_and_deploy_mps.sh
```

### Q6: 현재 배포된 Cycle은?
**A**: State 파일 확인:

```bash
cat /tmp/mps-autodeploy-state.txt
# 출력: 13 (마지막 배포된 Cycle)
```

또는 서버 Health API:
```bash
curl http://localhost:8893/health | jq '.model'
# 출력: "Cycle 13 (Epoch 27, 62.60%)"
```

### Q7: LaunchAgent 로그는?
**A**: 
```bash
# Watcher 로그
tail -f /tmp/mps-autodeploy.log

# 서버 로그
tail -f /tmp/mps_server.log

# 에러 로그
tail -f /tmp/mps-autodeploy-error.log
```

### Q8: 즉시 배포 테스트하려면?
**A**: 수동 실행:

```bash
cd /Users/young/projects/litecnn-pure-cpp
bash scripts/mps/watch_and_deploy_mps.sh

# 또는 강제 재배포 (State 초기화)
echo "0" > /tmp/mps-autodeploy-state.txt
bash scripts/mps/watch_and_deploy_mps.sh
```
