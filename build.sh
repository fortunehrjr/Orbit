#!/bin/zsh
# Builds Orbit.app into ./dist
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Universal binary (Apple silicon + Intel)
swift build -c release --arch arm64 --arch x86_64
if [ ! -f Resources/AppIcon.icns ]; then
  T=$(mktemp -d); mkdir -p "$T/AppIcon.iconset"
  swift Tools/MakeIcon.swift "$T/icon.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
fi
APP=dist/Orbit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Orbit" "$APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
