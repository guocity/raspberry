#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🚀 Opening Raspberry.xcodeproj in Xcode..."
open "$DIR/Raspberry.xcodeproj"
