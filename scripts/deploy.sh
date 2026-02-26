#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building Dictava..."
xcodebuild -project Dictava.xcodeproj -scheme Dictava -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5

BUILD_DIR=$(find ~/Library/Developer/Xcode/DerivedData/Dictava-*/Build/Products/Debug/Dictava.app -maxdepth 0 2>/dev/null | head -1)
if [[ -z "$BUILD_DIR" ]]; then
    echo "Error: Build output not found"
    exit 1
fi

echo "Quitting Dictava..."
osascript -e 'quit app "Dictava"' 2>/dev/null || true
sleep 1

echo "Deploying to /Applications..."
rm -rf /Applications/Dictava.app
cp -R "$BUILD_DIR" /Applications/Dictava.app

echo "Launching Dictava..."
open /Applications/Dictava.app

echo "Done."
