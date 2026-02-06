#!/usr/bin/env bash
# 멀티 채널 알림 스크립트 (Discord + Telegram)
# 사용법: ./notify.sh "메시지 내용"

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"message\""
    exit 1
fi

# Discord #server-monitoring 채널
echo "📢 Discord 전송 중..."
if openclaw message send \
    --channel discord \
    --target "server-monitoring" \
    --message "$MESSAGE" 2>&1 | grep -q '"ok"'; then
    echo "✅ Discord 전송 완료"
else
    echo "⚠️ Discord 전송 실패"
fi

# Telegram 전송 (자동으로 사용자에게 전송)
echo "📱 Telegram 전송 중..."
# Telegram은 target 없이 전송하면 기본 사용자에게 전송됨
if openclaw message send --channel telegram --message "$MESSAGE" 2>&1 | grep -q '"ok"'; then
    echo "✅ Telegram 전송 완료"
else
    echo "⚠️ Telegram 설정되지 않음 (스킵)"
fi
