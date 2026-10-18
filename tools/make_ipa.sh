#!/usr/bin/env bash
# Đóng gói .ipa từ .app đã build (dùng để sideload qua ESign/AltStore/Sideloadly).
#   ./tools/make_ipa.sh build/Build/Products/Release-iphoneos/BolaClone.app
set -euo pipefail
APP="${1:-}"
[ -d "$APP" ] || { echo "dùng: $0 <đường dẫn BolaClone.app>"; exit 1; }
OUT="${2:-BolaClone.ipa}"
rm -rf Payload "$OUT"
mkdir -p Payload
cp -R "$APP" Payload/
# nhúng patch nếu có (tuỳ chọn — patch là file IFix của game, đặt cùng tên trong Resources/)
if [ -f Resources/BolaminhducMenu.bytes ]; then
  cp Resources/BolaminhducMenu.bytes Payload/BolaClone.app/
fi
zip -qry "$OUT" Payload
rm -rf Payload
echo "-> $OUT ($(du -h "$OUT" | cut -f1))"
