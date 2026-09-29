#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
if ! xcrun --find simctl >/dev/null 2>&1; then
  print '需要完整 Xcode。请阅读 docs/开发环境.md；Mac 演示可直接运行 ./scripts/run-mac.sh。'
  exit 1
fi
if command -v xcodegen >/dev/null; then xcodegen generate; fi
open MelodyCamera.xcodeproj
open -a Simulator
print '请在 Xcode 选择已安装的 iPhone 模拟器，点击运行。真机需在 Signing 中选择 Personal Team。'
