#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_lh.py <file.bytes> <resName> — list hooks (res name override)."""
import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools")
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]


def main(path, res):
    blob = open(path, "rb").read()
    _t, _ol, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    types = pf["types"]
    print(f"== {os.path.basename(path)} res={res} ({len(blob)} B) "
          f"hooks={len(pf['interpret'])} blocks={len(pf['blocks'])} "
          f"types={len(types)} methods={len(pf['methods'])} "
          f"strings={len(pf['strings'])} fields={len(pf['fields'])}")
    print(f"{'vm':>5} {'#ins':>5}  signature")
    for h in pf["interpret"]:
        m = h["method"]
        decl = types[m["declType"]].split(",")[0]
        params = ",".join(types[p["id"]].split(",")[0].split(".")[-1]
                          for p in m["params"])
        n = len(pf["blocks"][h["vm"]]["instrs"]) // 2
        print(f"{h['vm']:>5} {n:>5}  {decl}::{m['name']}({params})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
