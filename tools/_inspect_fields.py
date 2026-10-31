#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_inspect_fields.py — in bang field / type cua mot payload .bytes (tam thoi)."""
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


def main(path: str, needle: str) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    _t, _ol, body, _e = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    types = pf["types"]
    print(f"== {os.path.basename(path)} fields={len(pf['fields'])} types={len(types)}")

    print("-- fields:")
    for i, f in enumerate(pf["fields"]):
        dt = types[f["declType"]].split(",")[0] if f["declType"] < len(types) else "?"
        if needle.lower() not in dt.lower():
            continue
        ft = types[f["ftype"]].split(",")[0] if f["ftype"] < len(types) else "?"
        print(f"   [{i:>4}] isNew={f['isNew']} {dt} :: {f['name']}  ({ft})")

    print("-- types:")
    for i, t in enumerate(types):
        if needle.lower() in t.lower():
            print(f"   [{i:>4}] {t}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "CRoleInfo")
