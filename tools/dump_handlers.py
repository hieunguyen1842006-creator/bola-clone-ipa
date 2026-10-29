#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dump_handlers.py — in exception handler cua tung block + vi tri Call guard,
de xac dinh handler offset la TUYET DOI hay TUONG DOI va co bao quanh Call guard.

Chay: python tools/dump_handlers.py <file.bytes>
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

GUARD_MARK = "aUZpeC5idW5kbGUuZ3VhcmQ"


def main(path: str) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    _t, _o, body, _e = resd_decrypt(blob, res)
    pf = lqmb_parse(body)

    guards = []
    for i, blk in enumerate(pf["blocks"]):
        ins = blk["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] == 0x27 and 0 <= ins[k + 1] < len(pf["strings"]) \
                    and pf["strings"][ins[k + 1]].startswith(GUARD_MARK):
                guards.append(i)
                break

    print(f"== {os.path.basename(path)} guards={guards}")
    for i, blk in enumerate(pf["blocks"]):
        if not blk["handlers"]:
            continue
        ins = blk["instrs"]
        n = len(ins) // 2
        call_at = [k // 2 for k in range(0, len(ins) - 1, 2)
                   if ins[k] == 0x2D and ins[k + 1] in guards]
        print(f"\n  vm{i}  ({n} lenh)  Call guard tai: {call_at}")
        for hi, h in enumerate(blk["handlers"]):
            vals = list(h)
            print(f"    handler[{hi}] = {vals}")
            # thu dien giai: [type, tryStart, tryEnd, handlerStart, handlerEnd, catchTypeId]
            if len(vals) == 6:
                t, ts, te, hs, he, ct = vals
                print(f"        type={t} try=[{ts},{te}) handler=[{hs},{he}) "
                      f"catchTypeId={ct}")
                for c in call_at:
                    inside_try = ts <= c < te
                    inside_h = hs <= c < he
                    if inside_try or inside_h:
                        print(f"        !!! Call guard @{c} nam trong "
                              f"{'TRY' if inside_try else ''}"
                              f"{'HANDLER' if inside_h else ''}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: dump_handlers.py <file.bytes>")
    main(sys.argv[1])
