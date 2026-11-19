#!/usr/bin/env bash
# Builds build/release/Zeigarnik-<version>-macos.zip (ADR-007).
# ZEIGARNIK_SIGN_IDENTITY picks the codesign identity; it must stay the same across releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IDENTITY="${ZEIGARNIK_SIGN_IDENTITY:-Zeigarnik Release}"
DERIVED="build/release-dd"
OUT="build/release"
APP="$DERIVED/Build/Products/Release/Zeigarnik.app"

if [[ -n "$(/usr/bin/git status --porcelain)" ]]; then
  echo "working tree is not clean; commit first so the zip matches a commit" >&2
  exit 1
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)"
AGENT_VERSION="$(awk -F'"' '/zeigarnikVersion/ {print $2; exit}' Sources/ZeigarnikAgent/AgentService.swift)"
if [[ -z "$VERSION" || "$VERSION" != "$AGENT_VERSION" ]]; then
  echo "version mismatch: project.yml '$VERSION', AgentService.swift '$AGENT_VERSION'" >&2
  exit 1
fi

PREFIX_MAP="$ROOT=."

xcodebuild -project Zeigarnik.xcodeproj -scheme Zeigarnik -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  OTHER_SWIFT_FLAGS="-file-prefix-map $PREFIX_MAP" build

SWIFT_BUILD=(swift build -c release --product zeigarnik --arch arm64 --arch x86_64
  -Xswiftc -file-prefix-map -Xswiftc "$PREFIX_MAP")
"${SWIFT_BUILD[@]}"
CLI_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"

mkdir -p "$APP/Contents/Helpers"
cp "$CLI_DIR/zeigarnik" "$APP/Contents/Helpers/zeigarnik"

for binary in "$APP/Contents/MacOS/Zeigarnik" "$APP/Contents/Helpers/zeigarnik"; do
  strip -S "$binary" 2> >(grep -v "invalidate the code signature" >&2)
done

codesign --force --sign "$IDENTITY" --identifier com.ceaksan.zeigarnik.cli "$APP/Contents/Helpers/zeigarnik"
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) \
    -exec codesign --force --sign "$IDENTITY" {} \;
fi
codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"

for binary in "$APP/Contents/MacOS/Zeigarnik" "$APP/Contents/Helpers/zeigarnik"; do
  archs="$(lipo -archs "$binary")"
  if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
    echo "$binary is not universal: $archs" >&2
    exit 1
  fi
  if grep -a -q -e "Apple Development:" -e "Developer ID" -e "$HOME/" "$binary"; then
    echo "$binary still carries a personal certificate or a home path" >&2
    exit 1
  fi
done

mkdir -p "$OUT"
ZIP="$OUT/Zeigarnik-$VERSION-macos.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

codesign -dvv "$APP" 2>&1 | grep -E '^(Authority|TeamIdentifier)=' | head -2
shasum -a 256 "$ZIP"
