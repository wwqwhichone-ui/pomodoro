#!/bin/zsh
# 编译并打包成 Pomodoro.app；可选 --install（安装到 /Applications）和 --install-cli（安装 pomo 命令行）
set -e
cd "$(dirname "$0")"

INSTALL_APP=false
INSTALL_CLI=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL_APP=true ;;
    --install-cli) INSTALL_CLI=true ;;
    -h|--help)
      echo "用法: ./build.sh [--install] [--install-cli]"
      echo "  --install      编译后复制到 /Applications/Pomodoro.app"
      echo "  --install-cli  将 tools/pomo 软链到 ~/.local/bin/pomo"
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      exit 1
      ;;
  esac
done

APP=build/Pomodoro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ ! -f AppIcon.icns ] && [ -f tools/make_icon.swift ]; then
  swift tools/make_icon.swift
  iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
fi

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Pomodoro" \
  -framework SwiftUI -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 已生成 $PWD/$APP"

if [ "$INSTALL_APP" = true ]; then
  rm -rf /Applications/Pomodoro.app
  cp -R "$APP" /Applications/
  echo "✅ 已安装到 /Applications/Pomodoro.app"
fi

if [ "$INSTALL_CLI" = true ]; then
  mkdir -p "$HOME/.local/bin"
  chmod +x "$PWD/tools/pomo"
  ln -sf "$PWD/tools/pomo" "$HOME/.local/bin/pomo"
  echo "✅ 已安装命令行: $HOME/.local/bin/pomo"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "提示: 请将 ~/.local/bin 加入 PATH，例如: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
fi
