#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""block_calls.py — trong mot block, liet ke moi CallExtern/Ldstr kem vi tri,
va co the loc theo tu khoa. Dung de doc hieu hook lam gi (skin/HUD/aim...).

Chay: python tools/block_calls.py <file.bytes> <vm> [filter]
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


def main(path: str, vm: int, flt: str) -> None:
    blob = open(path, "rb").read()
    res_name = os.path.splitext(os.path.basename(path))[0]
    _t, _ol, body, _enc = resd_decrypt(blob, res_name)
    pf = lqmb_parse(body)
    types = pf["types"]
    ins = pf["blocks"][vm]["instrs"]

    print(f"== vm{vm}  ({len(ins)//2} lenh)")
    if ins:
        bh = ins[1]
        print(f"   BlockHeader locals={bh >> 16} maxstack={bh & 0xFFFF}")
    low = flt.lower()
    ncalls = nstr = 0
    i = 0
    n = 0
    while i + 1 < len(ins):
        code, op = ins[i], ins[i + 1]
        if code == 0x7A:  # CallExtern
            mi = op & 0xFFFF
            if mi < len(pf["methods"]):
                m = pf["methods"][mi]
                tn = types[m["declType"]].split(",")[0]
                sig = f"{tn}::{m['name']}"
                params = ",".join(types[p["id"]].split(",")[0].split(".")[-1]
                                  for p in m["params"])
                line = f"  {n:5d}  CALL {sig}({params}) [argc={op >> 16}]"
                if not low or low in line.lower():
                    print(line)
                ncalls += 1
        elif code == 0x27:  # Ldstr
            s = pf["strings"][op] if op < len(pf["strings"]) else "?"
            line = f"  {n:5d}  STR  {s!r}"
            if not low or low in line.lower():
                print(line)
            nstr += 1
        elif code == 0x2D:  # Call (callvm)
            line = f"  {n:5d}  VMCALL vm{op}"
            if not low or low in line.lower():
                print(line)
        n += 1
        i += 2
    print(f"\n  tong: {ncalls} CallExtern, {nstr} Ldstr")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: block_calls.py <file.bytes> <vm> [filter]")
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "")
