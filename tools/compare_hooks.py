#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""compare_hooks.py — so hook privacy/host/zoom cua file THAT voi patch TU SINH.

In tung field cua method record + type string day du + IL tung lenh,
danh dau moi khac biet. Neu khac -> day la nguyen nhan treo.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

_gsrc = open(os.path.join(ROOT, "verify_lq_generator.py"), encoding="utf-8").read()
_gsrc = _gsrc.split("def run_python_gen")[0]
_G: dict = {"__file__": os.path.join(ROOT, "verify_lq_generator.py")}
exec(_gsrc, _G)


class G:
    make_patch = staticmethod(_G["make_patch"])


def method_sig(pf, m):
    decl = pf["types"][m["declType"]]
    params = "|".join(pf["types"][p["id"]] for p in m["params"])
    return (m["name"], decl, params, m["isGeneric"], tuple(m["typeArgs"]))


def hook_map(pf):
    out = {}
    for h in pf["interpret"]:
        out[method_sig(pf, h["method"])[0] + "#" + str(h["vm"])] = h
    return out


def by_name(pf, names):
    out = {}
    for h in pf["interpret"]:
        n = method_sig(pf, h["method"])[0]
        if n in names:
            out.setdefault(n, []).append(h)
    return out


def il_of(pf, vm):
    return list(pf["blocks"][vm]["instrs"])


def main(real_path: str):
    blob = open(real_path, "rb").read()
    res_name = os.path.splitext(os.path.basename(real_path))[0]
    _t, _ol, body, enc = resd_decrypt(blob, res_name)
    real = lqmb_parse(body)

    mine = G.make_patch(zoom=2.0, privacy_off=True, fake_host=True)
    print(f"file that : types={len(real['types'])} methods={len(real['methods'])} "
          f"blocks={len(real['blocks'])} nextAlloc={real['nextAlloc']} "
          f"fsvm={len(real['fsvm'])} fields={len(real['fields'])}")
    print(f"tu sinh   : types={len(mine['types'])} methods={len(mine['methods'])} "
          f"blocks={len(mine['blocks'])} nextAlloc={mine['nextAlloc']} "
          f"fsvm={len(mine['fsvm'])} fields={len(mine['fields'])}\n")

    want = ["IsPrivaceOn", "get_IsHostProfile", "GetZoomRate"]
    r = by_name(real, want)
    m = by_name(mine, want)

    failures = 0
    for name in want:
        rh = r.get(name, [])
        mh = m.get(name, [])
        print(f"== {name}: that x{len(rh)} / tu sinh x{len(mh)}")
        if len(rh) != len(mh):
            print(f"   !!! SO LUONG KHAC: that={len(rh)} tu sinh={len(mh)}")
            failures += 1
        for i, (a, b) in enumerate(zip(rh, mh)):
            sa, sb = method_sig(real, a["method"]), method_sig(mine, b["method"])
            print(f"   [{i}] that : name={sa[0]!r} decl={sa[1]!r} "
                  f"generic={sa[3]} typeArgs={sa[4]}")
            print(f"       sinh : name={sb[0]!r} decl={sb[1]!r} "
                  f"generic={sb[3]} typeArgs={sb[4]}")
            if sa[1] != sb[1]:
                print(f"       !!! DECL TYPE KHAC")
                failures += 1
            pa = sa[2].split("|") if sa[2] else []
            pb = sb[2].split("|") if sb[2] else []
            if pa != pb:
                print(f"       !!! PARAM KHAC: that={pa} sinh={pb}")
                failures += 1
            else:
                print(f"       params OK: {pa}")
            ia, ib = il_of(real, a["vm"]), il_of(mine, b["vm"])
            if ia == ib:
                print(f"       IL GIONG HET ({len(ia)//2} lenh)")
            else:
                print(f"       IL KHAC: that {len(ia)//2} lenh / sinh {len(ib)//2} lenh")
                for k in range(0, max(len(ia), len(ib)), 2):
                    xa = ia[k:k+2]
                    xb = ib[k:k+2]
                    if xa != xb:
                        print(f"         lenh {k//2}: that={xa} sinh={xb}")
                        failures += 1
                        break
        print()

    print("RESULT:", "PASS - khong khac gi" if failures == 0
          else f"KHAC BIET x{failures}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: compare_hooks.py <HeroSkin_1.bytes that>")
    main(sys.argv[1])
