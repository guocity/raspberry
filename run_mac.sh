#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🔨 Building and launching Raspberry for macOS..."
xcodebuild -project "$DIR/Raspberry.xcodeproj" -scheme Raspberry_macOS -configuration Debug build CODE_SIGNING_ALLOWED=NO > /dev/null
killall Raspberry 2>/dev/null || true
open "$DIR/build/macOS/Raspberry.app"
echo "✅ Raspberry is running!"
