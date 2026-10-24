#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_dir="${TOODLE_UI_ARTIFACTS:-/tmp/toodle-ui-check}"
simulator="${TOODLE_SIMULATOR_ID:-booted}"
if [[ "$simulator" == "booted" ]]; then
    simulator="$(xcrun simctl getenv booted SIMULATOR_UDID)"
fi
mkdir -p "$artifact_dir"

# One gate for placement lint, token drift, blue-only palette, and both-theme contrast.
python3 "$repo_root/scripts/style_check.py"

# Compile the actual app, then capture its current launch screen for visual review.
xcodebuild -project "$repo_root/Toodle.xcodeproj" -scheme Toodle -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$artifact_dir/DerivedData" build -quiet
xcrun simctl install "$simulator" "$artifact_dir/DerivedData/Build/Products/Debug-iphonesimulator/Toodle.app"
xcrun simctl terminate "$simulator" com.toodle.ios >/dev/null 2>&1 || true
xcrun simctl launch "$simulator" com.toodle.ios
sleep 3
xcrun simctl io "$simulator" screenshot "$artifact_dir/launch.png"
sips -g pixelWidth -g pixelHeight "$artifact_dir/launch.png"
printf 'UI screenshot: %s\n' "$artifact_dir/launch.png"
