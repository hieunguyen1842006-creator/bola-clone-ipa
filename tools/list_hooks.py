#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""list_hooks.py — in danh sach hook (signature + so lenh + opcode dac trung)
cua mot file patch .bytes, de tim hook nao lam viec gi (skin/HUD/aim/cam...).

Chay: python tools/list_hooks.py <file.bytes>
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


def main(path: str) -> None:
    blob = open(path, "rb").read()
    res_name = os.path.splitext(os.path.basename(path))[0]
    _t, _ol, body, enc = resd_decrypt(blob, res_name)
    pf = lqmb_parse(body)
    types = pf["types"]

    print(f"== {os.path.basename(path)} ({len(blob)} B) hooks={len(pf['interpret'])} "
          f"blocks={len(pf['blocks'])} types={len(types)} methods={len(pf['methods'])}")
    print(f"{'vm':>4} {'#ins':>5}  signature")
    for h in pf["interpret"]:
        m = h["method"]
        decl = types[m["declType"]].split(",")[0]
        params = ",".join(types[p["id"]].split(",")[0].split(".")[-1]
                          for p in m["params"])
        n = len(pf["blocks"][h["vm"]]["instrs"]) // 2
        print(f"{h['vm']:>4} {n:>5}  {decl}::{m['name']}({params})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: list_hooks.py <file.bytes>")
    main(sys.argv[1])
