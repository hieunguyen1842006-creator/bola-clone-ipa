#!/usr/bin/env bash
# Build .app/.deb/.ipa bằng Theos trên Ubuntu/WSL.
#
# Theos không chấp nhận đường dẫn có dấu cách, nên nếu project nằm dưới
# "/mnt/d/FileChuaHack/FF DATA IOS/..." script sẽ rsync sang ~/bolaclone-build,
# build ở đó rồi copy .app/.deb/.ipa về build/ của project gốc.
#
#   ./tools/build_theos.sh            -> .app trong build/BolaClone.app
#   ./tools/build_theos.sh package    -> .deb trong build/
#   ./tools/build_theos.sh ipa        -> BolaClone.ipa
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"

export PATH="$HOME/swift/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/swift-deps/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export THEOS="${THEOS:-$HOME/theos}"

if [[ "$(uname)" == "Linux" ]]; then
  echo "[!] Linux: SDK Theos chỉ có .swiftinterface, thiếu binary overlay module."
  echo "    Build SwiftUI sẽ dừng ở Dispatch overlay (xem FIXES.md mục Build)."
  echo "    Muốn có IPA: dùng workflow .github/workflows/bola-clone-ipa.yml (macOS runner)."
fi

bash "$(dirname "$0")/setup_swift_ios.sh" >/dev/null

if [[ "$SRC" == *" "* ]]; then
  WORK="$HOME/bolaclone-build"
  echo "[*] path có dấu cách -> build tại $WORK"
  rm -rf "$WORK"
  mkdir -p "$WORK"
  rsync -a --exclude .build --exclude .theos --exclude packages \
        --exclude build --exclude '*.ipa' "$SRC/" "$WORK/"
  cd "$WORK"
else
  cd "$SRC"
fi

make "$@"

mkdir -p "$SRC/build"
if [ -d ".theos/_/Applications/BolaClone.app" ]; then
  rm -rf "$SRC/build/BolaClone.app"
  cp -R ".theos/_/Applications/BolaClone.app" "$SRC/build/"
  echo "[+] app  -> $SRC/build/BolaClone.app"
fi
if [ -f "BolaClone.ipa" ]; then
  cp "BolaClone.ipa" "$SRC/build/"
  echo "[+] ipa  -> $SRC/build/BolaClone.ipa"
fi
if compgen -G "packages/*.deb" > /dev/null; then
  cp packages/*.deb "$SRC/build/"
  echo "[+] deb  -> $SRC/build/"
fi
