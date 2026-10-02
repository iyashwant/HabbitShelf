#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
python3 scripts/check-project.py
xcodebuild -project HabitBuddy.xcodeproj -scheme HabitBuddy \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
