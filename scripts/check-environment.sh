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
if xcrun --find simctl >/dev/null 2>&1; then
  print '\n模拟器：'
  xcrun simctl list devices available
else
  print '\n尚无完整 Xcode / 模拟器。可先运行 ./scripts/run-mac.sh。'
fi
