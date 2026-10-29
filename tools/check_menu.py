#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_menu.py — kiem tra Menu.bytes sinh ra tu build_menu.py co hop le khong.

Menu.bytes la container ResD tag 0 (plain, khong AES) chua IFix LQMB.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]
lqmb_serialize = _ns["lqmb_serialize"]

MAGIC_LQMB = bytes.fromhex("d0db2c0e465fd41f")


def check(path: str) -> int:
    blob = open(path, "rb").read()
    print(f"== {os.path.basename(path)} ({len(blob)} B)  head={blob[:8].hex(' ')}")

    body = None
    # thu doc nhu container ResD (u16 magic 0x4A22)
    if len(blob) > 8:
        magic = int.from_bytes(blob[0:2], "little")
        if magic == 0x4A22:
            tag = int.from_bytes(blob[2:4], "little")
            orig = int.from_bytes(blob[4:8], "little")
            body = blob[8:]
            print(f"   ResD: tag={tag} origLen={orig} body={len(body)}")
            if body[:8] != MAGIC_LQMB:
                print("   ! body khong bat dau bang magic LQMB")

    if body is None or body[:8] != MAGIC_LQMB:
        body = blob
        print("   (doc truc tiep, khong qua wrapper)")

    if body[:8] != MAGIC_LQMB:
        print("   FAIL: khong phai IFix LQMB")
        return 1

    pf = lqmb_parse(body)
    print(f"   types={len(pf['types'])} methods={len(pf['methods'])} "
          f"strings={len(pf['strings'])} fields={len(pf['fields'])} "
          f"blocks={len(pf['blocks'])} hooks={len(pf['interpret'])} "
          f"nextAlloc={pf['nextAlloc']}")
    print(f"   bridge={pf['bridge']}")
    print(f"   wrapper={pf['wrapper']}")
    print(f"   fsvm={pf['fsvm']}")

    ok = True
    if pf["nextAlloc"] != len(pf["blocks"]):
        print(f"   FAIL nextAlloc {pf['nextAlloc']} != {len(pf['blocks'])}")
        ok = False

    # roundtrip
    try:
        again = lqmb_serialize(pf)
        if again != body:
            print(f"   FAIL round-trip: {len(again)} != {len(body)}")
            ok = False
        else:
            print("   round-trip: OK")
    except Exception as e:
        print(f"   FAIL serialize: {e}")
        ok = False

    print("\n   hook:")
    for h in pf["interpret"]:
        m = h["method"]
        d = pf["types"][m["declType"]].split(",")[0]
        n = len(pf["blocks"][h["vm"]]["instrs"]) // 2
        print(f"     vm{h['vm']} {n} lenh  {d}::{m['name']}")

    print("\n   field moi:")
    for f in pf["fields"]:
        if f["isNew"]:
            print(f"     {pf['types'][f['declType']].split(',')[0]}::{f['name']} "
                  f": {pf['types'][f['ftype']].split(',')[0]}")

    print("\n   string 'iFix.' keys:")
    for i, s in enumerate(pf["strings"]):
        if s.startswith("iFix."):
            print(f"     [{i}] {s}")

    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else "_lqmenu/Menu.bytes"
    raise SystemExit(check(p))
