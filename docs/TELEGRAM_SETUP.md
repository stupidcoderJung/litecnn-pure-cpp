# Telegram 알림 설정 가이드 📱

자동 배포 알림을 Telegram으로도 받을 수 있도록 설정하는 방법입니다.

## 🎯 개요

현재 알림 시스템은 **Discord + Telegram** 동시 전송을 지원합니다.  
Telegram을 설정하지 않아도 Discord 알림은 정상 작동하며, Telegram 실패 시 자동으로 스킵됩니다.

## 📱 Telegram 봇 생성

### 1. BotFather와 대화

1. Telegram에서 [@BotFather](https://t.me/botfather) 검색
2. `/start` 명령 실행
3. `/newbot` 명령으로 새 봇 생성
4. 봇 이름과 username 설정
5. **Bot Token** 받기 (예: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### 2. Chat ID 확인

**방법 1: @userinfobot 사용**
1. [@userinfobot](https://t.me/userinfobot) 검색
2. `/start` 명령 실행
3. **Chat ID** 받기 (예: `987654321`)

**방법 2: 직접 확인**
1. 생성한 봇에게 메시지 전송 (아무 메시지나)
2. 브라우저에서 접속:
   ```
   https://api.telegram.org/bot<BOT_TOKEN>/getUpdates
   ```
3. JSON 응답에서 `chat.id` 찾기

## ⚙️ OpenClaw 설정

### 1. Gateway 설정 파일 수정

```bash
# 설정 파일 편집
nano ~/.openclaw/config/gateway.yaml
```

### 2. Telegram 채널 추가

```yaml
channels:
  telegram:
    enabled: true
    token: "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"  # BotFather에서 받은 토큰
    defaultChatId: "987654321"  # 본인 Chat ID
```

### 3. Gateway 재시작

```bash
openclaw gateway restart
```

또는:

```bash
pkill -HUP openclaw-gateway
```

## ✅ 테스트

### 수동 테스트

```bash
# Telegram으로 테스트 메시지 전송
openclaw message send \
  --channel telegram \
  --message "테스트 메시지"
```

성공 시:
```json
{
  "ok": true,
  "result": {
    "message_id": 123,
    "chat": {
      "id": 987654321
    }
  }
}
```

### 알림 스크립트 테스트

```bash
cd ~/projects/litecnn-pure-cpp
./scripts/notify.sh "🧪 Telegram 알림 테스트!"
```

출력 예시:
```
📢 Discord 전송 중...
✅ Discord 전송 완료
📱 Telegram 전송 중...
✅ Telegram 전송 완료
```

## 🔧 문제 해결

### Telegram 알림이 안 옴

```bash
# OpenClaw 상태 확인
openclaw status

# 설정 확인
cat ~/.openclaw/config/gateway.yaml | grep -A 5 telegram

# Gateway 로그 확인
openclaw logs --follow
```

### "Unknown target" 에러

Telegram은 `--target` 없이 전송하면 `defaultChatId`로 전송됩니다.  
에러가 발생하면 설정 파일에 `defaultChatId`가 올바른지 확인하세요.

### Bot Token 오류

- Token 형식: `숫자:영문자+숫자`
- 예: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`
- 공백이나 줄바꿈이 들어가지 않도록 주의

## 📊 알림 예시

설정 완료 후 자동 배포 시 다음과 같은 알림을 받습니다:

### Discord
```
🔥 새 모델 감지!
GPU 서버에서 새로운 모델이 학습되었습니다.
TO-BE 서버(8892) 자동 배포를 시작합니다...

📊 모델 정보:
- Cycle: cycle 8
- 모델명: best_model_cycle8.pth
- 경로: ~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
- 이전 해시: a3f8d9e2...
- 새 해시: b7c4e1f3...
```

### Telegram
동일한 메시지가 Telegram으로도 전송됩니다.

## 🚀 고급 설정

### 그룹 채팅에 알림 보내기

1. 봇을 그룹 채팅에 추가
2. 그룹 Chat ID 확인 (음수로 시작, 예: `-123456789`)
3. `defaultChatId`를 그룹 ID로 변경

### 여러 채팅에 동시 전송

OpenClaw는 현재 하나의 `defaultChatId`만 지원하므로,  
여러 채팅에 보내려면 스크립트를 수정해야 합니다.

`scripts/notify.sh`:
```bash
# 개인 채팅
openclaw message send --channel telegram --target "987654321" --message "$MESSAGE"

# 그룹 채팅
openclaw message send --channel telegram --target "-123456789" --message "$MESSAGE"
```

## 📝 참고

- **OpenClaw Telegram 문서**: https://docs.openclaw.ai/channels/telegram
- **Telegram Bot API**: https://core.telegram.org/bots/api
- **BotFather**: https://t.me/botfather

---

**작성**: 텔리크로 🖤  
**마지막 업데이트**: 2026-02-06
