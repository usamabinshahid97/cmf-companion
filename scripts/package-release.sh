#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
    bash scripts/build.sh
elif [ "$#" -ne 1 ] || [ "$1" != "--skip-build" ]; then
    printf 'Usage: %s [--skip-build]\n' "$0" >&2
    exit 2
fi

release_app="$(pwd)/dist/CMF Companion.app"
release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")
release_arch=$(lipo -archs "$release_app/Contents/MacOS/CMFCompanion")
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Expected a three-part release version, got: %s\n' "$release_version" >&2
    exit 1
fi
if [ "$release_arch" != "arm64" ]; then
    printf 'The published cask currently supports arm64 only, got: %s\n' "$release_arch" >&2
    exit 1
fi
codesign --verify --deep --strict "$release_app"

release_name="CMF-Companion-${release_version}-Apple-Silicon.zip"
if [ -e "dist/$release_name" ]; then
    printf 'Archive already exists; refusing to replace release bytes: dist/%s\n' "$release_name" >&2
    exit 1
fi
release_temp=$(mktemp -d "$(pwd)/dist/.release.XXXXXX")
trap 'rm -rf "$release_temp"' EXIT
ditto -c -k --keepParent --norsrc --noextattr "$release_app" "$release_temp/$release_name"
unzip -tq "$release_temp/$release_name"
mv "$release_temp/$release_name" "dist/$release_name"
(cd dist && shasum -a 256 "$release_name" > "$release_name.sha256")
printf 'Packaged: dist/%s\n' "$release_name"
cat "dist/$release_name.sha256"
