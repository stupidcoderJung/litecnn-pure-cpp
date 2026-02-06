# 자동화 시스템 🤖

TO-BE 서버(8892)의 자동 배포 및 Discord 알림 시스템 문서입니다.

## 🎯 개요

GPU 서버에서 학습이 완료되면 자동으로 TO-BE 서버(8892)에 배포되며, 모든 과정이 Discord로 실시간 알림됩니다.

```
GPU 서버 학습 완료
    ↓
30분마다 체크 (launchd)
    ↓
MD5 해시 변경 감지
    ↓
Discord 알림: "🔥 새 모델 감지!"
    ↓
자동 배포 (~15초)
    ↓
Discord 알림: "✅ 배포 완료!" or "❌ 배포 실패"
```

## 🚀 자동 배포 시스템

### launchd 서비스

**위치**: `~/Library/LaunchAgents/com.litecnn.autodeploy.plist`

**주기**: 30분마다 (1800초)

**로그**:
- 표준 출력: `/tmp/litecnn-autodeploy.log`
- 에러 출력: `/tmp/litecnn-autodeploy-error.log`

### 관리 명령어

```bash
# 서비스 시작
launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist

# 서비스 중지
launchctl unload ~/Library/LaunchAgents/com.litecnn.autodeploy.plist

# 상태 확인
launchctl list | grep litecnn

# 즉시 실행 (테스트용)
launchctl start com.litecnn.autodeploy

# 로그 확인
tail -f /tmp/litecnn-autodeploy.log
```

## 📢 Discord 알림

### 알림 시나리오

#### 1. 시스템 활성화
```
🤖 자동 배포 시스템 활성화

TO-BE 서버(8892) 자동 배포가 활성화되었습니다.
30분마다 GPU 서버를 체크하여 새 모델을 자동으로 배포합니다.

현재 상태:
- AS-IS (8891): 안정 버전 (수동 배포)
- TO-BE (8892): 실험 버전 (자동 배포)
- 체크 주기: 30분
- 배포 시간: ~15초

launchd PID: 11373 ✅
```

#### 2. 새 모델 감지
```
🔥 새 모델 감지!
GPU 서버에서 새로운 모델이 학습되었습니다.
TO-BE 서버(8892) 자동 배포를 시작합니다...

이전 해시: `a3f8d9e2...`
새 해시: `b7c4e1f3...`
```

#### 3. 배포 완료
```
✅ 배포 완료!
TO-BE 서버(8892)에 새 모델이 배포되었습니다.

해시: `b7c4e1f3...`
포트: `http://localhost:8892/predict`
시간: 2026-02-06 09:10:29
```

#### 4. 배포 실패
```
❌ 배포 실패
TO-BE 서버(8892) 배포 중 오류가 발생했습니다.
다음 주기(30분 후)에 재시도합니다.

해시: `b7c4e1f3...`
로그: `/tmp/litecnn-deploy.log`
```

### 수동 알림

```bash
# Discord로 메시지 전송
./scripts/notify_discord.sh "테스트 메시지"

# 상태 리포트 전송
./scripts/status_report.sh --discord
```

## 📊 상태 모니터링

### 상태 리포트 스크립트

**위치**: `scripts/status_report.sh`

**사용법**:
```bash
# 콘솔 출력만
./scripts/status_report.sh

# Discord 전송
./scripts/status_report.sh --discord
```

**출력 예시**:
```
📊 LiteCNN 서버 상태 리포트
2026-02-06 09:10:33

✅ AS-IS (프로덕션) (포트 8891)
- 상태: 실행 중
- PID: 10904
- 메모리: 31.8MB
- 가동시간: 16:39

✅ TO-BE (실험) (포트 8892)
- 상태: 실행 중
- PID: 10917
- 메모리: 21.2MB
- 가동시간: 16:37

📦 마지막 배포
- TO-BE 해시: `b7c4e1f3...`
- 파일: `~/.litecnn_last_deploy.txt`

🤖 자동 배포
- 상태: 활성화 ✅
- PID: 11373
- 체크 주기: 30분

API 엔드포인트:
- AS-IS: `http://localhost:8891/predict`
- TO-BE: `http://localhost:8892/predict`
```

## 🔧 스크립트 구조

### 1. `watch_and_deploy.sh`
**역할**: 30분마다 실행되어 새 모델을 감지하고 배포

**동작**:
1. GPU 서버 체크포인트 MD5 해시 계산
2. 로컬 저장된 해시와 비교
3. 변경 시 → 배포 시작 (Discord 알림)
4. 배포 성공/실패 → Discord 알림

### 2. `deploy_from_gpu.sh`
**역할**: 실제 배포 작업 수행

**동작**:
1. GPU 서버에서 체크포인트 다운로드
2. PyTorch → Binary 변환
3. C++ 빌드
4. TO-BE 서버(8892) 재시작
5. Health Check

### 3. `notify_discord.sh`
**역할**: Discord 알림 전송

**사용법**:
```bash
./scripts/notify_discord.sh "메시지 내용"
```

### 4. `status_report.sh`
**역할**: 서버 상태 수집 및 리포트

**사용법**:
```bash
./scripts/status_report.sh [--discord]
```

## 🔍 로그 & 디버깅

### 자동 배포 로그

```bash
# 실시간 로그
tail -f /tmp/litecnn-autodeploy.log

# 에러 로그
tail -f /tmp/litecnn-autodeploy-error.log

# 배포 상세 로그
tail -f /tmp/litecnn-deploy.log
```

### 서버 로그

```bash
# AS-IS 서버
tail -f /tmp/litecnn_server_8891.log

# TO-BE 서버
tail -f /tmp/litecnn_server_8892.log
```

### 배포 이력

```bash
# 마지막 배포된 모델 해시
cat ~/.litecnn_last_deploy.txt

# 배포 이력 초기화 (다음 체크 시 재배포됨)
rm ~/.litecnn_last_deploy.txt
```

## ⚙️ 설정 변경

### 체크 주기 변경

`~/Library/LaunchAgents/com.litecnn.autodeploy.plist` 파일 수정:

```xml
<key>StartInterval</key>
<integer>1800</integer>  <!-- 30분 = 1800초 -->
```

변경 후 재등록:
```bash
launchctl unload ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
```

### Discord 채널 변경

`scripts/notify_discord.sh` 파일 수정:

```bash
openclaw message send \
    --channel discord \
    --target "server-monitoring" \  # 여기 수정
    --message "$MESSAGE"
```

## 🚨 문제 해결

### 자동 배포가 실행되지 않음

```bash
# 서비스 상태 확인
launchctl list | grep litecnn

# 재시작
launchctl unload ~/Library/LaunchAgents/com.litecnn.autodeploy.plist
launchctl load ~/Library/LaunchAgents/com.litecnn.autodeploy.plist

# 로그 확인
tail -50 /tmp/litecnn-autodeploy.log
```

### Discord 알림이 안 옴

```bash
# 수동 테스트
./scripts/notify_discord.sh "테스트"

# OpenClaw 상태 확인
openclaw status

# 권한 확인
ls -l scripts/notify_discord.sh  # 실행 권한 확인
```

### 배포 실패

```bash
# 배포 로그 확인
tail -100 /tmp/litecnn-deploy.log

# GPU 서버 연결 테스트
sshpass -p '1' ssh love-lee@192.168.0.40 'echo OK'

# 체크포인트 확인
sshpass -p '1' ssh love-lee@192.168.0.40 \
  'ls -lh ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth'
```

## 📈 향후 개선

- [ ] **배포 이력 데이터베이스** - SQLite로 이력 관리
- [ ] **성능 메트릭** - 배포 전후 정확도 자동 비교
- [ ] **롤백 자동화** - 배포 실패 시 이전 버전으로 자동 롤백
- [ ] **웹 대시보드** - 실시간 배포 상태 모니터링
- [ ] **Slack 통합** - Discord 외 Slack 알림 추가

---

**작성**: 텔리크로 🖤  
**마지막 업데이트**: 2026-02-06  
**상태**: 활성화 ✅
