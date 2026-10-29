#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""opcode_index.py — xac dinh opcode nao co operand la INDEX can remap.

Dua vao IL markdown da decode (co ten type/field/method sau operand):
  - "Ldfld   1 = Assets...::field"     -> operand la field index
  - "CallExtern ... -> Type::Method"   -> method index
  - "Castclass ..."                    -> type index
  - "Ldc_I4 5"                         -> hang so, KHONG remap

Chay: python tools/opcode_index.py <file.bytes> <il.md>
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

VM_RE = re.compile(r"^##\s+vm(\d+)\s+\((\d+)\s+l")
INSTR_RE = re.compile(r"^\s*(\d+)\s+(\S+)\s*(.*)$")


def parse_md(path: str):
    out, cur = {}, None
    for line in open(path, encoding="utf-8"):
        m = VM_RE.match(line)
        if m:
            cur = int(m.group(1)); out[cur] = []; continue
        if cur is None or line.startswith("```") or not line.strip():
            continue
        im = INSTR_RE.match(line)
        if im:
            out[cur].append((int(im.group(1)), im.group(2), im.group(3).strip()))
        elif line.startswith("##"):
            cur = None
    return out


def main(bytes_path: str, md_path: str) -> None:
    blob = open(bytes_path, "rb").read()
    res = os.path.splitext(os.path.basename(bytes_path))[0]
    _t, _o, body, _e = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    md = parse_md(md_path)

    # name -> {code: set(kieu operand)}
    info: dict[str, dict[int, set[str]]] = {}
    for vm, items in md.items():
        if vm >= len(pf["blocks"]):
            continue
        ins = pf["blocks"][vm]["instrs"]
        n = len(ins) // 2
        for idx, name, operand in items:
            if idx >= n:
                continue
            code = ins[idx * 2]
            op = ins[idx * 2 + 1]
            kind = classify(name, operand, op)
            info.setdefault(name, {}).setdefault(code, set()).add(kind)

    print(f"== {os.path.basename(bytes_path)}")
    print("\n  Opcode mang INDEX (can remap khi harvest):")
    for name in sorted(info):
        for code, kinds in sorted(info[name].items()):
            if kinds & {"field", "method", "string", "type", "block", "token"}:
                print(f"     0x{code:02X}  {name:22s} {sorted(kinds)}")
    print("\n  Opcode la HANG SO / dieu khien (giu nguyen):")
    for name in sorted(info):
        for code, kinds in sorted(info[name].items()):
            if not (kinds & {"field", "method", "string", "type", "block", "token"}):
                print(f"     0x{code:02X}  {name:22s} {sorted(kinds)}")


def classify(name: str, operand: str, opcode_val: int) -> str:
    if name in ("Ldfld", "Ldflda", "Stfld"):
        return "field"
    if name in ("Ldsfld", "Ldsflda", "Stsfld"):
        return "field_s"
    if name in ("CallExtern",):
        return "method"
    if name in ("Newobj",):
        return "method_new"
    if name in ("Ldstr",):
        return "string"
    if name in ("Castclass", "Castclass2", "Castclass3", "Isinst",
                "Ldtoken", "Newarr", "Box", "Unbox", "Initobj",
                "Ldtype", "Sizeof", "Constrained"):
        return "type"
    if name in ("Call",):
        return "block"
    if name in ("Br", "Brfalse", "Brtrue", "Beq", "Bge", "Bgt", "Ble",
                "Blt", "Bne_Un", "Leave", "Switch"):
        return "branch"
    if name in ("Ldarg", "Ldloc", "Stloc", "Ldloca", "Ldarga", "Starg"):
        return "slot"
    if name in ("Ldc_I4", "Ldc_I8", "Ldc_R4", "Ldc_R8", "BlockHeader"):
        return "const"
    return "other"


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: opcode_index.py <file.bytes> <il.md>")
    main(sys.argv[1], sys.argv[2])
