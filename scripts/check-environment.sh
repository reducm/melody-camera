#!/bin/zsh
set -u
cd "$(dirname "$0")/.."
print '当前系统：'
sw_vers
print '\nSwift：'
swift --version
print '\n可用磁盘空间：'
df -h .
print '\n开发工具目录：'
xcode-select -p
print '\nXcode 与 SDK（列出 SDK 不代表平台运行组件已经安装）：'
if xcodebuild -version; then
  xcodebuild -showsdks
  if ! xcodebuild -checkFirstLaunchStatus; then
    print '\nXcode 首次配置未完成，请用户打开 Xcode 完成组件安装和系统授权。'
    exit 1
  fi
else
  print '\n未检测到可用的完整 Xcode。'
fi
if xcrun --find simctl >/dev/null 2>&1; then
  print '\n模拟器运行时（空列表表示尚未安装）：'
  xcrun simctl list runtimes
  print '\n模拟器：'
  xcrun simctl list devices available
else
  print '\n尚无完整 Xcode / 模拟器。可先运行 ./scripts/run-mac.sh。'
fi
if xcrun --find devicectl >/dev/null 2>&1; then
  print '\n连接的设备（手机型号与系统版本仍需在真机验收时记录）：'
  xcrun devicectl list devices
fi
