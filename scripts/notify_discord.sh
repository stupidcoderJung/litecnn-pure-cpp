#!/usr/bin/env bash
# Discord 알림 헬퍼 스크립트
# 사용법: ./notify_discord.sh "메시지 내용"

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"message\""
    exit 1
fi

# OpenClaw message tool 사용
# Discord #server-monitoring 채널로 전송
openclaw message send \
    --channel discord \
    --target "server-monitoring" \
    --message "$MESSAGE" \
    2>&1 | grep -v "^{" || echo "✅ Discord 알림 전송 완료"
