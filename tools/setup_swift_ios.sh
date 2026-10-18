#!/usr/bin/env bash
# Tạo resource-dir lai cho Swift cross-compile iOS:
#   <res>/clang   -> builtin headers của toolchain Linux (stdarg.h, stddef.h…)
#   <res>/host    -> host stdlib (plugin/macro)
#   <res>/iphoneos-> Swift stdlib của SDK (bản Theos để phẳng)
#
#   ./tools/setup_swift_ios.sh [duong/dan/iPhoneOSxx.sdk]
set -euo pipefail

R="$HOME/swift-ios-res"
S="${1:-}"
if [ -z "$S" ]; then
  S="$(ls -d "$HOME"/theos/sdks/iPhoneOS*.sdk | sort -V | tail -1)"
fi
if [ ! -d "$S/usr/lib/swift" ]; then
  echo "!! không thấy $S/usr/lib/swift" >&2
  exit 1
fi

mkdir -p "$R"
ln -sfn "$HOME/swift/usr/lib/swift/clang"   "$R/clang"
ln -sfn "$HOME/swift/usr/lib/swift/host"    "$R/host"
ln -sfn "$HOME/swift/usr/lib/swift/apinotes" "$R/apinotes"
ln -sfn "$S/usr/lib/swift"                  "$R/iphoneos"

echo "[+] resource-dir: $R"
ls -l "$R"
