#!/bin/zsh
# 编译并打包成 Pomodoro.app；可选 --universal / --zip / --install / --install-cli
set -e
cd "$(dirname "$0")"

INSTALL_APP=false
INSTALL_CLI=false
UNIVERSAL=false
MAKE_ZIP=false

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL_APP=true ;;
    --install-cli) INSTALL_CLI=true ;;
    --universal) UNIVERSAL=true ;;
    --zip) MAKE_ZIP=true ;;
    -h|--help)
      echo "用法: ./build.sh [--universal] [--zip] [--install] [--install-cli]"
      echo "  --universal    编译 Apple Silicon + Intel 通用二进制（arm64 + x86_64）"
      echo "  --zip          打包成 build/Pomodoro-<version>-macos-*.zip 并输出 SHA-256"
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

if [ "$UNIVERSAL" = true ]; then
  swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 Sources/*.swift \
    -o build/Pomodoro-arm64 -framework SwiftUI -framework AppKit
  swiftc -O -swift-version 5 -target x86_64-apple-macosx14.0 Sources/*.swift \
    -o build/Pomodoro-x86_64 -framework SwiftUI -framework AppKit
  lipo -create build/Pomodoro-arm64 build/Pomodoro-x86_64 -output "$APP/Contents/MacOS/Pomodoro"
  rm -f build/Pomodoro-arm64 build/Pomodoro-x86_64
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" Sources/*.swift \
    -o "$APP/Contents/MacOS/Pomodoro" -framework SwiftUI -framework AppKit
fi

cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 已生成 $PWD/$APP"

if [ "$MAKE_ZIP" = true ]; then
  VERSION="${VERSION:-v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
  if [ "$UNIVERSAL" = true ]; then
    ZIP="build/Pomodoro-${VERSION}-macos-universal.zip"
  else
    ZIP="build/Pomodoro-${VERSION}-macos-$(uname -m).zip"
  fi
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "✅ 已打包 $PWD/$ZIP"
  shasum -a 256 "$ZIP"
fi

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
