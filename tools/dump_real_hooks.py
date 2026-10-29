#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dump_real_hooks.py — dump method record + IL cua tung hook trong file patch that.

Muc dich: so signature (declType, name, params) va pattern IL (Call prologue,
Br) giua file that cua game va file tu sinh, de tim khac biet lam game treo.

Chay: python tools/dump_real_hooks.py <path-to-HeroSkin_N.bytes> [pattern]
"""
from __future__ import annotations

import os
import struct
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

# opcode hay gap
NAMES = {
    0x92: "BlockHeader", 0xA4: "Ldarg", 0x7A: "CallExtern", 0x27: "Ldstr",
    0x8D: "Ldc_R4", 0x8F: "Ldc_I4", 0xB3: "Mul", 0x24: "Stloc",
    0x48: "Ldloc", 0xAD: "Ret", 0x5D: "Br", 0x2D: "Call", 0x2B: "BrS",
}


def dump(path: str, pattern: str) -> None:
    blob = open(path, "rb").read()
    res_name = os.path.splitext(os.path.basename(path))[0]
    _t, _ol, body, enc = resd_decrypt(blob, res_name)
    pf = lqmb_parse(body)

    # che do dac biet: dump mot block bat ky theo index, ke ca block khong la hook
    if pattern.startswith("block:"):
        idx = int(pattern.split(":", 1)[1])
        blk = pf["blocks"][idx]
        ins = blk["instrs"]
        print(f"== block vm{idx} ({len(ins)//2} lenh)")
        hooked = {h["vm"] for h in pf["interpret"]}
        print(f"   la hook: {idx in hooked} | fsvm: {pf['fsvm']}")
        i = 0
        n = 0
        while i + 1 < len(ins):
            code, op = ins[i], ins[i + 1]
            nm = NAMES.get(code, hex(code))
            extra = ""
            if code == 0x7A:
                mi = op & 0xFFFF
                mm = pf["methods"][mi] if mi < len(pf["methods"]) else None
                if mm:
                    extra = (" -> " + pf["types"][mm["declType"]].split(",")[0]
                             + "::" + mm["name"] + f" (argc={op >> 16})")
            elif code == 0x27:
                extra = " '" + (pf["strings"][op] if op < len(pf["strings"]) else "?") + "'"
            elif code == 0x8D:
                import struct as _s
                extra = f" {_s.unpack('<f', _s.pack('<i', op))[0]}f"
            elif code == 0x92:
                extra = f" (locals={op >> 16}, maxstack={op & 0xFFFF})"
            elif code == 0x2D:
                extra = f" (callvm vm{op})"
            elif code in (0x5D, 0x2C, 0xA6, 0xA7):
                extra = f" (jump? {op})"
            print(f"  {n:4d} 0x{code:02X} {op:10d}  {nm}{extra}")
            n += 1
            i += 2
        return

    types = pf["types"]
    print(f"== {os.path.basename(path)} ({len(blob)} B) tag={_t} enc={enc}")
    print(f"   types={len(types)} methods={len(pf['methods'])} "
          f"blocks={len(pf['blocks'])} hooks={len(pf['interpret'])} "
          f"strings={len(pf['strings'])}")

    n_prologue = n_br = n_no_prologue = n_no_br = 0
    matched = 0
    for h in pf["interpret"]:
        m = h["method"]
        decl = types[m["declType"]].split(",")[0]
        full = decl + "::" + m["name"]
        if pattern and pattern.lower() not in full.lower():
            continue
        matched += 1
        params = ",".join(types[p["id"]].split(",")[0] for p in m["params"])
        print(f"\n  vm{h['vm']} {full}({params})")

        blk = pf["blocks"][h["vm"]]
        ins = blk["instrs"]
        n = 0
        lines = []
        i = 0
        while i + 1 < len(ins):
            code, op = ins[i], ins[i + 1]
            nm = NAMES.get(code, hex(code))
            if code == 0x92:
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm} "
                             f"(locals={op >> 16}, maxstack={op & 0xFFFF})")
            elif code == 0x7A:
                mi = op & 0xFFFF
                mm = pf["methods"][mi] if mi < len(pf["methods"]) else None
                tn = types[mm["declType"]].split(",")[0] + "::" + mm["name"] if mm else "?"
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm} -> {tn} "
                             f"(argc={op >> 16})")
            elif code == 0x2D:
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm} (callvm vm{op})")
            elif code == 0x8D:
                f = struct.unpack("<f", struct.pack("<i", op))[0]
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm} {f}f")
            elif code == 0x27:
                s = pf["strings"][op] if op < len(pf["strings"]) else "?"
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm} '{s}'")
            else:
                lines.append(f"    {n:3d} 0x{code:02X} {op:6d}  {nm}")
            n += 1
            i += 2
        for ln in lines:
            print(ln)

        # pattern: prologue Call + Br truoc cap Ldloc/Ret cuoi
        has_call = any(ins[i] == 0x2D for i in range(2, len(ins) - 4, 2))
        has_br = len(ins) >= 6 and ins[-4] == 0x5D and ins[-3] == 1
        if has_call:
            n_prologue += 1
        else:
            n_no_prologue += 1
        if has_br:
            n_br += 1
        else:
            n_no_br += 1

    print(f"\n  -> matched={matched}  callPrologue={n_prologue}/no={n_no_prologue}  "
          f"br1={n_br}/no={n_no_br}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: dump_real_hooks.py <file.bytes> [pattern]")
    dump(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
