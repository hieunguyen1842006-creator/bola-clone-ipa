#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_sq.py <file.bytes> <resName> <vm> — tom tat block: chi in Ldstr/CallExtern/field."""
import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools")
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

FLD = {0xA7, 0x4B, 0x3C}


def main(path, res, vm):
    blob = open(path, "rb").read()
    _t, _ol, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    for v in vm.split(","):
        v = int(v)
        ins = pf["blocks"][v]["instrs"]
        print(f"--- vm{v} ({len(ins)//2} instr)")
        for k in range(0, len(ins), 2):
            c, o = ins[k], ins[k + 1]
            if c == 0x27 and o < len(pf["strings"]):
                print(f"  {k//2:>5} Ldstr        {pf['strings'][o]!r}")
            elif c == 0x7A and (o & 0xFFFF) < len(pf["methods"]):
                m = pf["methods"][o & 0xFFFF]
                dt = pf["types"][m["declType"]].split(",")[0].split(".")[-1]
                ps = ",".join(pf["types"][p["id"]].split(",")[0].split(".")[-1]
                              for p in m["params"])
                print(f"  {k//2:>5} CallExtern   {dt}::{m['name']}({ps}) argc={o>>16}")
            elif c in FLD and (o & 0xFFFF) < len(pf["fields"]):
                f = pf["fields"][o & 0xFFFF]
                print(f"  {k//2:>5} {'Stfld' if c==0x4B else 'Ldfld':<11} "
                      f"{pf['types'][f['declType']].split(',')[0].split('.')[-1]}::{f['name']}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
