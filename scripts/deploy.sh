#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building OpenDictator..."
xcodebuild -project OpenDictator.xcodeproj -scheme OpenDictator -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5

BUILD_DIR=$(find ~/Library/Developer/Xcode/DerivedData/OpenDictator-*/Build/Products/Debug/OpenDictator.app -maxdepth 0 2>/dev/null | head -1)
if [[ -z "$BUILD_DIR" ]]; then
    echo "Error: Build output not found"
    exit 1
fi

echo "Quitting OpenDictator..."
osascript -e 'quit app "OpenDictator"' 2>/dev/null || true
sleep 1

echo "Resetting holdToRecordEnabled..."
defaults write dev.julian0xff.opendictator holdToRecordEnabled -bool false 2>/dev/null || true

echo "Deploying to /Applications..."
rm -rf /Applications/OpenDictator.app
cp -R "$BUILD_DIR" /Applications/OpenDictator.app

echo "Launching OpenDictator..."
open /Applications/OpenDictator.app

echo "Done."
