#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build_menu34_pack.py — đóng gói LQFullMenu34.bytes (LQ2) từ:

    HeroSkin_1.bytes   lấy nguyên từ LQFull.bytes   (42 hook — skin/aim/zoom/…)
    HeroSkin_2.bytes   LQFull.bytes + Menu.bytes     (6 hook, menu gọi từ vm22)

rồi sinh LQFullMenu34.vault.

Chạy:
    python tools/build_menu34_pack.py [--skip-build]

--skip-build  không chạy build_menu.py/merge_menu.py, dùng Menu.bytes sẵn có.
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RES = os.path.join(ROOT, "Resources")

SRC_PACK = os.path.join(RES, "LQFull.bytes")
OUT_PACK = os.path.join(RES, "LQFullMenu34.bytes")
MENU = os.path.join(ROOT, "_lqmenu", "Menu.bytes")
WORK = os.path.join(ROOT, "_lqmenu", "work")


def parse_lq2(blob: bytes):
    if blob[:4] != b"LQ2\x00":
        raise SystemExit("không phải container LQ2: %r" % blob[:4])
    off = 4
    cnt = struct.unpack_from("<I", blob, off)[0]
    off += 4
    out = []
    for _ in range(cnt):
        nlen = blob[off]
        off += 1
        name = blob[off:off + nlen].decode()
        off += nlen
        size = struct.unpack_from("<I", blob, off)[0]
        off += 4
        out.append((name, blob[off:off + size]))
        off += size
    if off != len(blob):
        raise SystemExit("LQ2 còn byte thừa: %d" % (len(blob) - off))
    return out


def build_lq2(entries):
    out = bytearray(b"LQ2\x00")
    out += struct.pack("<I", len(entries))
    for name, data in entries:
        nb = name.encode()
        out += bytes([len(nb)]) + nb + struct.pack("<I", len(data)) + data
    return bytes(out)


def hook_names(path: str, res: str):
    """Đếm hook của một file ResD .bytes (dùng verify_swift_logic)."""
    sys.path.insert(0, HERE)
    src = open(os.path.join(HERE, "verify_swift_logic.py"), encoding="utf-8").read()
    ns: dict = {}
    exec(src.split("def main()")[0], ns)
    tag, _o, body, _e = ns["resd_decrypt"](open(path, "rb").read(), res)
    pf = ns["lqmb_parse"](body)
    return [h["method"]["name"] for h in pf["interpret"]], len(pf["blocks"])


def main():
    skip = "--skip-build" in sys.argv
    os.makedirs(WORK, exist_ok=True)

    if not skip:
        print("== build Menu.bytes (csc + IFix + pack)")
        rc = subprocess.run([sys.executable, os.path.join(HERE, "build_menu.py")],
                            cwd=ROOT)
        if rc.returncode != 0:
            raise SystemExit("build_menu.py thất bại")

    if not os.path.exists(MENU):
        raise SystemExit("thiếu %s — chạy build_menu.py trước" % MENU)

    entries = parse_lq2(open(SRC_PACK, "rb").read())
    print("== LQFull có %d file: %s" % (len(entries), [n for n, _ in entries]))

    hs1 = next(d for n, d in entries if n.startswith("HeroSkin_1"))
    hs2 = next(d for n, d in entries if n.startswith("HeroSkin_2"))

    p1 = os.path.join(WORK, "HeroSkin_1.bytes")
    p2 = os.path.join(WORK, "HeroSkin_2.bytes")
    open(p1, "wb").write(hs1)
    open(p2, "wb").write(hs2)

    hs2_menu = os.path.join(WORK, "HeroSkin_2_menu34.bytes")
    print("== merge menu vào HeroSkin_2 (splice vm22, không hook UpdateFrame)")
    rc = subprocess.run([sys.executable, os.path.join(HERE, "merge_menu_vm22.py"),
                         p2, MENU, hs2_menu], cwd=ROOT)
    if rc.returncode != 0:
        raise SystemExit("merge_menu_vm22.py thất bại")

    new_hs1 = hs1
    new_hs2 = open(hs2_menu, "rb").read()

    h1, b1 = hook_names(p1, "HeroSkin_1")
    h2, b2 = hook_names(hs2_menu, "HeroSkin_2")
    print("   HeroSkin_1: %d hook, %d block" % (len(h1), b1))
    print("   HeroSkin_2: %d hook, %d block" % (len(h2), b2))
    if "UpdateFrame" in h2:
        raise SystemExit("HeroSkin_2 còn hook UpdateFrame — sẽ treo load!")
    if "get_frameSynchr" not in h2:
        raise SystemExit("HeroSkin_2 mất hook get_frameSynchr — trùng hook!")
    if len(h2) != 6:
        raise SystemExit("HeroSkin_2 phải đúng 6 hook, thấy %d" % len(h2))

    out = build_lq2([("HeroSkin_1.bytes", new_hs1), ("HeroSkin_2.bytes", new_hs2)])
    open(OUT_PACK, "wb").write(out)
    print("== ghi %s (%d B)" % (OUT_PACK, len(out)))

    # Validate return-path reachability, not merely hook counts or serialization.
    rc = subprocess.run([sys.executable, "-I", os.path.join(HERE, "test_menu_vm22.py")], cwd=ROOT)
    if rc.returncode != 0:
        raise SystemExit("test_menu_vm22.py thất bại")

    # vault
    rc = subprocess.run([sys.executable, os.path.join(HERE, "make_vault.py")], cwd=ROOT)
    if rc.returncode != 0:
        raise SystemExit("make_vault.py thất bại")

    # verify vault đọc lại
    import hashlib
    vp = os.path.join(RES, "LQFullMenu34.vault")
    if os.path.exists(vp):
        key = hashlib.sha256(b"NVH-MOD-2026:vault:v1").digest()
        blob = open(vp, "rb").read()
        n = int.from_bytes(blob[5:9], "little")
        ks = b"".join(hashlib.sha256(key + i.to_bytes(4, "little")).digest()
                      for i in range((n + 31) // 32))
        pt = bytes(a ^ b for a, b in zip(blob[41:41 + n], ks))
        ok = hashlib.sha256(pt).digest() == blob[9:41] and pt == open(OUT_PACK, "rb").read()
        print("== vault verify: %s (%d B)" % ("OK" if ok else "FAIL", n))
        if not ok:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
