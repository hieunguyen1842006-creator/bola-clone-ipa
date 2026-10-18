#!/usr/bin/env bash
# Build app iOS từ dòng lệnh (macOS + Xcode).
#   ./tools/build_ios.sh            -> build Debug, xuất .app ra build/
#   SDK=iphoneos CONFIG=Release ./tools/build_ios.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="${SDK:-iphonesimulator}"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-build}"
SCHEME="BolaClone"
PROJ="BolaClone.xcodeproj"

if ! command -v xcodebuild >/dev/null; then
  echo "!! cần macOS + Xcode (xcodebuild không có trên Linux/Windows)" >&2
  exit 2
fi
if [ ! -d "$PROJ" ] && command -v xcodegen >/dev/null; then
  xcodegen generate
fi

xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk "$SDK" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build | tee "$DERIVED/xcodebuild.log" | tail -20

APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "BolaClone.app" | head -1)
echo
echo "== .app: $APP"
