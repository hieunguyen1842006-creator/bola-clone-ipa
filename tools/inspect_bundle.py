#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""inspect_bundle.py — doc file .bytes cua app: co the la
  - bundle "LQ2\\0" (nhieu file) -> liet ke tung file + hook
  - container ResD (1 file)      -> liet ke hook
Dung de biet payload nao co hook skin/HUD.

Chay: python tools/inspect_bundle.py <file.bytes>
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


def parse_bundle(b: bytes):
    if len(b) < 9 or b[:4] != b"LQ2\x00":
        return None
    n = int.from_bytes(b[4:8], "little")
    o = 8
    out = []
    for _ in range(n):
        nl = b[o]
        o += 1
        name = b[o:o + nl].decode("utf-8", "replace")
        o += nl
        sz = int.from_bytes(b[o:o + 4], "little")
        o += 4
        out.append((name, b[o:o + sz]))
        o += sz
    return out


def show(name: str, blob: bytes) -> None:
    print(f"\n-- {name}  ({len(blob)} B)")
    res = os.path.splitext(os.path.basename(name))[0]
    try:
        _t, _ol, body, enc = resd_decrypt(blob, res)
    except Exception as e:
        print(f"   ! khong giai ma duoc: {e}")
        print(f"   head: {blob[:16].hex(' ')}")
        return
    try:
        pf = lqmb_parse(body)
    except Exception as e:
        print(f"   ! khong phai IFix: {e}")
        return
    types = pf["types"]
    print(f"   tag={_t} enc={enc} magic={pf['magic'][:4].hex()} "
          f"types={len(types)} methods={len(pf['methods'])} "
          f"blocks={len(pf['blocks'])} hooks={len(pf['interpret'])} "
          f"fields={len(pf['fields'])} strings={len(pf['strings'])}")
    print(f"   bridge={pf['bridge'].split(',')[0]}")
    for h in pf["interpret"]:
        m = h["method"]
        decl = types[m["declType"]].split(",")[0]
        n = len(pf["blocks"][h["vm"]]["instrs"]) // 2
        print(f"     vm{h['vm']:<4} {n:>5} ins  {decl}::{m['name']}")


def main(path: str) -> None:
    b = open(path, "rb").read()
    print(f"== {os.path.basename(path)} ({len(b)} B)")
    files = parse_bundle(b)
    if files is None:
        show(os.path.basename(path), b)
        return
    print(f"   bundle LQ2: {len(files)} file")
    for name, data in files:
        show(name, data)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: inspect_bundle.py <file.bytes>")
    main(sys.argv[1])
