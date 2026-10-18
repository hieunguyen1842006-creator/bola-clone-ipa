#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""repack_patch.py — đổi các string nhận dạng trong NVHMenu.bytes.

Không sửa IL, chỉ thay string literal trong string table (tham chiếu bằng index),
nên logic patch giữ nguyên. Chạy sau mỗi lần lấy patch gốc:

    python tools/repack_patch.py

Yêu cầu: ifixbytes.py (đặt cạnh hoặc trỏ BIFFIX_DIR bên dưới).
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCH = os.path.join(ROOT, "Resources", "NVHMenu.bytes")

# Thư mục chứa ifixbytes.py trong workspace (đổi nếu cần).
IFIX_DIRS = [
    os.environ.get("BIFFIX_DIR", ""),
    r"D:\FileChuaHack\LQ IOS DEEPSEEEK HARNESS\NEWW XỬ LÍ THEO DẠNG MỚI",
]

# index -> (giá trị cũ, giá trị mới)
REPLACEMENTS = {
    0: ("__bolaminhduc_menu", "__nvh_menu"),
    1: ("__bolac", "__nvhcfg"),
    2: ("/bolacfg.bin", "/nvhcfg.bin"),
    4: ("/.bola_tok", "/.nvhtok"),
    6: ("|BOLATK1|", "|NVHTK01|"),
}


def load_ifix():
    for d in IFIX_DIRS:
        if d and os.path.isfile(os.path.join(d, "ifixbytes.py")):
            sys.path.insert(0, d)
            import ifixbytes  # noqa: WPS433
            return ifixbytes
    raise SystemExit("Không tìm thấy ifixbytes.py — đặt biến môi trường BIFFIX_DIR")


def main() -> int:
    ix = load_ifix()
    raw = open(PATCH, "rb").read()
    pf = ix.parse_file(PATCH)

    # Hợp đồng: serialize(parse(x)) == x
    if ix.serialize(pf) != raw:
        raise SystemExit("roundtrip không khớp — dừng để tránh phá patch")

    changed = 0
    for idx, (old, new) in REPLACEMENTS.items():
        cur = pf.strings[idx]
        if cur == new:
            print("  [skip] S%02d đã là %r" % (idx, new))
            continue
        if cur != old:
            raise SystemExit("S%02d lạ: %r (mong %r)" % (idx, cur, old))
        if len(new.encode("utf-8")) > 255:
            raise SystemExit("S%02d quá dài" % idx)
        pf.strings[idx] = new
        changed += 1
        print("  S%02d %r -> %r" % (idx, old, new))

    out = ix.serialize(pf)
    # Kiểm tra lại cấu trúc sau khi sửa
    back = ix.parse_bytes(out)
    if back.strings[6] != "|NVHTK01|" or back.strings[2] != "/nvhcfg.bin":
        raise SystemExit("verify sau repack thất bại")

    open(PATCH, "wb").write(out)
    print("repack xong: %d string, %d B -> %d B" % (changed, len(raw), len(out)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
