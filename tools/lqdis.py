#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lqdis.py - disassembler LQMB voi ten opcode that (opcode_table_lqmb_full.json).

Dung:
    python tools/lqdis.py <file.bytes> <vm> [start_pc] [end_pc]
"""
from __future__ import annotations

import json
import os
import sys

import merge_menu as M

HERE = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.path.join(os.path.dirname(os.path.dirname(HERE)), "LQ IOS DATA",
                 "opcode_table_lqmb_full.json"),
    os.path.join(os.path.dirname(HERE), "..", "LQ IOS DATA",
                 "opcode_table_lqmb_full.json"),
    r"D:\FileChuaHack\LQ IOS DATA\opcode_table_lqmb_full.json",
]
TABLE = next(p for p in _CANDIDATES if os.path.exists(p))

_table = json.load(open(TABLE, encoding="utf-8"))
NAMES = _table["names"]
# game byte -> std name
G2N = {int(v): NAMES[int(k)] for k, v in _table["std_to_game"].items()}

BRANCHES = {"Br", "Brfalse", "Brtrue", "Beq", "Bge", "Bgt", "Ble", "Blt",
            "Bne_Un", "Bge_Un", "Bgt_Un", "Ble_Un", "Blt_Un", "Leave"}


def opname(code: int) -> str:
    return G2N.get(code, "op_0x%02x" % code)


def dis(pf, vm: int, start: int = 0, end: int | None = None) -> None:
    ins = pf["blocks"][vm]["instrs"]
    n = len(ins) // 2
    end = n if end is None else min(end, n)
    methods, fields, strings = pf["methods"], pf["fields"], pf["strings"]
    for i in range(start, end):
        pc = i * 2
        code, arg = ins[pc], ins[pc + 1]
        name = opname(code)
        ex = ""
        if name in ("Call", "CallExtern", "Callvirt", "Callvirtvirt"):
            mi, argc = arg & 0xFFFF, arg >> 16
            if mi < len(methods):
                m = methods[mi]
                t = pf["types"][m["declType"]].split(",")[0].split(".")[-1]
                ex = "%s::%s argc=%d" % (t, m["name"], argc)
            else:
                ex = "BAD_METHOD %d" % mi
        elif name in ("Ldfld", "Ldflda", "Stfld", "Ldsfld", "Ldsflda", "Stsfld"):
            if arg < len(fields):
                ex = fields[arg]["name"]
            else:
                ex = "BAD_FIELD %d" % arg
        elif name == "Ldstr":
            ex = repr(strings[arg]) if arg < len(strings) else "BAD_STR %d" % arg
        elif name in BRANCHES:
            ex = "-> %d" % (i + 1 + arg)
        elif name in ("Ldloc", "Stloc", "Ldarg", "Starg", "Ldloca", "Ldarga"):
            ex = "loc/arg %d" % arg
        print("%5d %-14s %-12d %s" % (i, name, arg, ex))


def main() -> int:
    path = sys.argv[1]
    vm = int(sys.argv[2])
    start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    end = int(sys.argv[4]) if len(sys.argv) > 4 else None
    res = os.path.splitext(os.path.basename(path))[0]
    if res.startswith("HeroSkin_1"):
        res = "HeroSkin_1"
    elif res.startswith("HeroSkin_2"):
        res = "HeroSkin_2"
    pf, _t, _e, _r = M.load(path, res)
    print("# %s vm%d ops=%d" % (path, vm, len(pf["blocks"][vm]["instrs"]) // 2))
    dis(pf, vm, start, end)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
