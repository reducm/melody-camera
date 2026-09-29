#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
swift build
APP="$PWD/.build/MelodyCamera.app"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build --show-bin-path)/MelodyCamera" "$APP/Contents/MacOS/MelodyCamera"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.melody.camera.preview</string>
<key>CFBundleName</key><string>MelodyCamera</string>
<key>CFBundleDisplayName</key><string>Melody 拍摄练习室</string>
<key>CFBundleExecutable</key><string>MelodyCamera</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
open "$APP"
