#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_ti.py <file.bytes> <resName> [vm...] — in type table, va dump block vm."""
import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools")
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

OPS = {
    0x27: "Ldstr", 0x7A: "CallExtern", 0x2D: "Call", 0xA7: "Ldfld", 0x4B: "Stfld",
    0x3C: "Ldsfld", 0x49: "Newobj", 0x58: "Castclass", 0x18: "Castclass2",
    0x8A: "Castclass3", 0x22: "Box", 0x59: "Newarr", 0x5E: "Ldtoken",
    0x97: "Initobj", 0x16: "Constrained", 0x86: "Brfalse", 0x7F: "Brtrue",
    0x5D: "Br", 0x67: "Nop", 0xA4: "Ldarg", 0x48: "Ldloc", 0x24: "Stloc",
    0x8F: "Ldc_I4", 0x0D: "Ldloca", 0xAD: "Ret", 0xA6: "Ceq", 0x2B: "Beq",
}


def main(path, res, vms):
    blob = open(path, "rb").read()
    _t, _ol, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    if vms:
        for v in vms:
            v = int(v)
            ins = pf["blocks"][v]["instrs"]
            print(f"--- vm{v} ({len(ins)//2} instr)")
            for k in range(0, len(ins), 2):
                c, o = ins[k], ins[k + 1]
                nm = OPS.get(c, hex(c))
                extra = ""
                if c == 0x27 and o < len(pf["strings"]):
                    extra = repr(pf["strings"][o])
                elif c == 0x7A and (o & 0xFFFF) < len(pf["methods"]):
                    m = pf["methods"][o & 0xFFFF]
                    dt = pf["types"][m["declType"]].split(",")[0]
                    ps = ",".join(pf["types"][p["id"]].split(",")[0].split(".")[-1]
                                  for p in m["params"])
                    extra = f"{dt}::{m['name']}({ps}) argc={o>>16}"
                elif c in (0xA7, 0x4B, 0x3C) and (o & 0xFFFF) < len(pf["fields"]):
                    f = pf["fields"][o & 0xFFFF]
                    extra = f"{pf['types'][f['declType']].split(',')[0].split('.')[-1]}::{f['name']}"
                elif c in (0x58, 0x18, 0x8A, 0x22, 0x59, 0x5E, 0x97, 0x16) and (o & 0xFFFF) < len(pf["types"]):
                    extra = pf["types"][o & 0xFFFF].split(",")[0]
                print(f"  {k//2:>5} {nm:<12} {o:>8}  {extra}")
        return
    for i, t in enumerate(pf["types"]):
        print(f"[{i}] {t}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
