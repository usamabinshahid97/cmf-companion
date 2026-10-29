#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$(pwd)/dist/CMF Companion.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/AppIcon.iconset
cp .build/release/CMFCompanion "$app/Contents/MacOS/CMFCompanion"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$(pwd)/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
for document in LICENSE THIRD_PARTY.md; do
    if [ -f "$document" ]; then cp "$document" "$app/Contents/Resources/"; fi
done
codesign --force --sign - --identifier local.usama.cmfcompanion --entitlements Resources/CMFCompanion.entitlements "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
