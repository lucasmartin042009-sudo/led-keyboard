#!/bin/bash
# Compile Led Keyboard et crée build/Led Keyboard.app
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Led Keyboard.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -framework Cocoa -framework SwiftUI -framework ApplicationServices \
  Sources/LedKeyboard.swift -o "$APP/Contents/MacOS/LedKeyboard"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "✅ App prête : $APP"
echo "   Lance-la avec : open \"$APP\""
