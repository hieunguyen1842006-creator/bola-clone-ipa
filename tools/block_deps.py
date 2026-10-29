#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""block_deps.py — phan tich phu thuoc cua mot block:
  - Call vmN (callvm) -> block nao
  - CallExtern -> method nao (va method do thuoc type nao)
  - Ldstr -> string nao
  - field refs (Ldfld/Stfld) -> field nao
Giup biet khi transplant mot hook sang patch khac thi phai copy nhung gi.

Chay: python tools/block_deps.py <file.bytes> <vm>
"""
from __future__ import annotations

import collections
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]


def analyze(pf, vm, seen=None):
    """Tra ve (callvm, methods, strings, fields) cua block vm, de quy qua callvm."""
    if seen is None:
        seen = set()
    if vm in seen:
        return set(), set(), set(), set()
    seen.add(vm)
    ins = pf["blocks"][vm]["instrs"]
    callvm, methods, strings, fields = set(), set(), set(), set()
    i = 0
    while i + 1 < len(ins):
        code, op = ins[i], ins[i + 1]
        if code == 0x2D and 0 <= op < len(pf["blocks"]):   # Call vmN
            callvm.add(op)
            a, b, c, d = analyze(pf, op, seen)
            callvm |= a; methods |= b; strings |= c; fields |= d
        elif code == 0x7A:                            # CallExtern
            methods.add(op & 0xFFFF)
        elif code == 0x27:                            # Ldstr
            strings.add(op)
        elif code in (0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x80, 0x81):
            fields.add(op)
        i += 2
    return callvm, methods, strings, fields


def main(path: str, vm: int) -> None:
    blob = open(path, "rb").read()
    res_name = os.path.splitext(os.path.basename(path))[0]
    _t, _ol, body, _enc = resd_decrypt(blob, res_name)
    pf = lqmb_parse(body)

    callvm, methods, strings, fields = analyze(pf, vm)
    types = pf["types"]

    print(f"== {os.path.basename(path)} vm{vm}")
    print(f"   blocks: {len(pf['blocks'])}  types: {len(types)}  "
          f"methods: {len(pf['methods'])}  strings: {len(pf['strings'])}  "
          f"fields: {len(pf['fields'])}  fsvm: {len(pf['fsvm'])}  anon: {len(pf['anon'])}")
    print(f"\n   callvm -> {sorted(callvm)}")
    print(f"   so method can: {len(methods)}")
    print(f"   so string can: {len(strings)}")
    print(f"   so field ref : {len(fields)}")

    # type can thiet: declType cua method + param types
    tneed = set()
    for mi in methods:
        m = pf["methods"][mi]
        tneed.add(m["declType"])
        for p in m["params"]:
            tneed.add(p["id"])
        for ta in m["typeArgs"]:
            tneed.add(ta)
    print(f"   so type can  : {len(tneed)} (ke ca trong method signature)")

    # hook method cua chinh vm
    hook = [h for h in pf["interpret"] if h["vm"] == vm]
    if hook:
        m = hook[0]["method"]
        print(f"\n   hook: {types[m['declType']].split(',')[0]}::{m['name']}")
        print(f"         declType={m['declType']} params={[p['id'] for p in m['params']]}")
        print(f"         isGeneric={m['isGeneric']} typeArgs={m['typeArgs']}")

        # generic method trong signature -> type co generic args
        gen = [mi for mi in methods if pf["methods"][mi]["isGeneric"]]
        print(f"   method generic can: {len(gen)}")
        print(f"   field isNew (tao field moi): "
              f"{[f['name'] for f in pf['fields'] if f['isNew']][:10]}")

    # fsvm: cap (field, vm)?
    print(f"\n   fsvm: {pf['fsvm']}")
    print(f"   anon: {len(pf['anon'])}")
    if pf["anon"]:
        print(f"   anon[0]: fields={len(pf['anon'][0]['fieldIds'])} "
              f"ifaces={len(pf['anon'][0]['interfaces'])} "
              f"vtable={len(pf['anon'][0]['vtable'])}")
    print(f"   newClasses: {pf['newClasses']}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: block_deps.py <file.bytes> <vm>")
    main(sys.argv[1], int(sys.argv[2]))
