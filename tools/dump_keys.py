#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dump_keys.py — liet ke moi string trong patch, nhom theo block/hook nao dung.
Dung de tim PlayerPrefs key ("iFix.*") = bang dieu khien mod.

Chay: python tools/dump_keys.py <file.bytes> [filter]
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


def main(path: str, flt: str = "") -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    _t, _o, body, _e = resd_decrypt(blob, res)
    pf = lqmb_parse(body)

    hook_of = {h["vm"]: h for h in pf["interpret"]}
    print(f"== {os.path.basename(path)}  strings={len(pf['strings'])}")

    # string nao duoc dung trong block nao
    used: dict[int, list[str]] = {}
    for i, blk in enumerate(pf["blocks"]):
        for k in range(0, len(blk["instrs"]) - 1, 2):
            if blk["instrs"][k] == 0x27:
                sid = blk["instrs"][k + 1]
                if 0 <= sid < len(pf["strings"]):
                    used.setdefault(sid, []).append(
                        f"vm{i}" + (
                            "(" + pf["types"][hook_of[i]["method"]["declType"]].split(",")[0]
                            + "::" + hook_of[i]["method"]["name"] + ")"
                            if i in hook_of else "(guard/aux)"))

    low = flt.lower()
    for sid, s in enumerate(pf["strings"]):
        if low and low not in s.lower():
            continue
        where = ", ".join(used.get(sid, [])) or "khong dung"
        print(f"  [{sid:3d}] {s!r}\n          {where}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: dump_keys.py <file.bytes> [filter]")
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
