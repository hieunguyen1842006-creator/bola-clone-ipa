#!/usr/bin/env bash
# Build + self-test phần logic (Foundation-only) trên Linux/WSL.
# Không cần Xcode. Dùng Swift toolchain giải nén ở ~/swift.
set -euo pipefail

cd "$(dirname "$0")/.."

export PATH="$HOME/swift/usr/bin:$PATH"
# Swift 6.1 toolchain cần libxml2.so.2; Ubuntu 26.04 chỉ có .so.16 nên dùng bản
# giải nén cục bộ trong ~/swift-deps/root (xem FIXES.md).
if [ -d "$HOME/swift-deps/root/usr/lib/x86_64-linux-gnu" ]; then
  export LD_LIBRARY_PATH="$HOME/swift-deps/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "[!] không thấy swift. Tải toolchain trước (xem tools/build_linux.sh --help)."
  exit 1
fi

echo "== swift =="
swift --version

echo "== build BolaCore =="
swift build -c debug

echo "== chạy self-test =="
swift run -c debug BolaSelfTest
