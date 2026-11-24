#!/usr/bin/env bash
# 番茄钟 Pomodoro — macOS 本机一键编译、安装与启动脚本
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> [1/3] 编译并安装 Pomodoro.app 到 /Applications，链接 pomo 到 ~/.local/bin ..."
./build.sh --install --install-cli

echo "==> [2/3] 启动 /Applications/Pomodoro.app ..."
pkill -x Pomodoro 2>/dev/null || true
sleep 0.4
open /Applications/Pomodoro.app

echo "==> [3/3] 等待本机接口 http://127.0.0.1:47625/v1/health 就绪 ..."
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:47625/v1/health >/dev/null 2>&1; then
    echo "✅ 番茄钟已成功部署并启动！"
    ~/.local/bin/pomo status
    exit 0
  fi
  sleep 0.3
done

echo "⚠️ 未能在超时时间内检测到 127.0.0.1:47625，请检查应用窗口状态。" >&2
exit 1
