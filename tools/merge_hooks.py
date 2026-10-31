#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_hooks.py — chep CHON LOC hook tu payload nguon (src) vao payload dich (dst).

Khac merge_menu.py:
  * merge_menu.py chep TOAN BO src (dung khi src chi co 1 hook tu sinh).
  * file nay chep theo TEN hook (glob), va tu keo theo moi block con duoc goi
    qua OP_CALL -> du de ghep tinh nang tu payload khac ma khong sinh hook trung
    tren cung mot method (hook trung = hook sau de hook truoc).

Hook trung method voi dst -> BO QUA (dst giu ban cua no).

Chay:
  python tools/merge_hooks.py <dst.bytes> <src.bytes> <out.bytes> "Ten::Hook,Other::*"
"""
from __future__ import annotations

import fnmatch
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import merge_menu as M          # noqa: E402  (Remap + opcode + resd helpers)


def sig(pf, h) -> str:
    m = h["method"]
    return pf["types"][m["declType"]].split(",")[0].split(".")[-1] + "::" + m["name"]


def select_hooks(pf, patterns):
    out = []
    for h in pf["interpret"]:
        s = sig(pf, h)
        if any(fnmatch.fnmatchcase(s, p) for p in patterns):
            out.append(h)
    return out


def collect_blocks(pf, hooks):
    """BFS theo OP_CALL: moi block con duoc goi phai chep theo."""
    want, seen, stack = [], set(), [h["vm"] for h in hooks]
    while stack:
        b = stack.pop()
        if b in seen:
            continue
        seen.add(b)
        want.append(b)
        ins = pf["blocks"][b]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] == M.OP_CALL:
                stack.append(ins[k + 1] & 0xFFFF)
    return want


def merge_hooks(dst_path, src_path, out_path, patterns):
    dst, dtag, denc, dres = M.load(dst_path)
    src, _st, _se, _sr = M.load(src_path)

    da = dst["bridge"].split(",")[1].strip()
    sa = src["bridge"].split(",")[1].strip()
    if da != sa:
        raise SystemExit(f"assembly khac nhau: {da} vs {sa}")

    print(f"== dst: {os.path.basename(dst_path)}  hooks={len(dst['interpret'])} "
          f"blocks={len(dst['blocks'])}")
    print(f"== src: {os.path.basename(src_path)}  hooks={len(src['interpret'])} "
          f"blocks={len(src['blocks'])}")

    picked = select_hooks(src, patterns)
    if not picked:
        raise SystemExit("khong tim thay hook nao khop")

    dst_sigs = {sig(dst, h) for h in dst["interpret"]}
    hooks, skipped = [], []
    for h in picked:
        s = sig(src, h)
        (skipped if s in dst_sigs else hooks).append((s, h))
    for s, _ in skipped:
        print(f"   bo qua (dst da co): {s}")
    if not hooks:
        raise SystemExit("moi hook khop deu da co trong dst")

    before = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
              len(dst["fields"]), len(dst["blocks"]))
    rp = M.Remap(dst)

    # chep block (gom ca block con)
    vmap = {}
    for bi in collect_blocks(src, [h for _, h in hooks]):
        vmap[bi] = len(dst["blocks"])
        blk = src["blocks"][bi]
        dst["blocks"].append({
            "instrs": list(blk["instrs"]),
            "handlers": [list(x) for x in blk["handlers"]],
        })
    dst["nextAlloc"] = len(dst["blocks"])

    # remap operand trong block vua chep
    for sbi, dbi in vmap.items():
        ins = dst["blocks"][dbi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            code, op = ins[k], ins[k + 1]
            if code == M.OP_LDSTR:
                ins[k + 1] = rp.str_(src, op)
            elif code in (M.OP_CALLEXTERN, M.OP_NEWOBJ):
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(src, op & 0xFFFF)
            elif code in M.FIELD_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.field_(src, op & 0xFFFF)
            elif code in M.TYPE_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.type_(src, op & 0xFFFF)
            elif code == M.OP_CALL:
                tgt = op & 0xFFFF
                if tgt not in vmap:
                    raise SystemExit(f"block {sbi} Call vm{tgt} ngoai pham vi")
                ins[k + 1] = ((op >> 16) << 16) | vmap[tgt]

    # KHONG khai field hang loat: field chi duoc Remap.field_ keo vao khi co
    # lenh LDFLD/STFLD/LDSFLD that su dung no. Khai thua = IFix cap phat them
    # field moi cho class cua game -> doi layout, de vo.

    # hook
    for name, h in hooks:
        m = h["method"]
        dt = rp.type_(src, m["declType"])
        ps = [dict(p, id=(rp.type_(src, p["id"]) if not p["isName"] else p["id"]))
              for p in m["params"]]
        ta = [rp.type_(src, x) for x in m["typeArgs"]]
        mi = -1
        for j, cm in enumerate(dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [p["id"] for p in cm["params"]] == [p["id"] for p in ps]
                    and [p["isName"] for p in cm["params"]] == [p["isName"] for p in ps]):
                mi = j
                break
        if mi < 0:
            dst["methods"].append({
                "isGeneric": m["isGeneric"], "declType": dt, "name": m["name"],
                "typeArgs": ta, "params": ps,
            })
            mi = len(dst["methods"]) - 1
        rec = dst["methods"][mi]
        dst["interpret"].append({
            "method": {
                "isGeneric": rec["isGeneric"], "declType": rec["declType"],
                "name": rec["name"], "typeArgs": list(rec["typeArgs"]),
                "params": [dict(p) for p in rec["params"]],
            },
            "vm": vmap[h["vm"]],
        })
        print(f"   + hook {name} -> vm{vmap[h['vm']]}")

    after = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
             len(dst["fields"]), len(dst["blocks"]))
    print(f"   them: types +{after[0]-before[0]} methods +{after[1]-before[1]} "
          f"strings +{after[2]-before[2]} fields +{after[3]-before[3]} "
          f"blocks +{after[4]-before[4]}")

    body = M.lqmb_serialize(dst)
    back = M.lqmb_parse(body)
    assert M.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])

    added = set(vmap.values())
    for bi in sorted(added):
        ins = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            c, o = ins[k], ins[k + 1]
            if c == M.OP_CALLEXTERN:
                assert (o & 0xFFFF) < len(back["methods"]), "method idx sai"
            elif c == M.OP_LDSTR:
                assert o < len(back["strings"]), "string idx sai"
            elif c in M.FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"]), f"field idx sai: {o}"
            elif c == M.OP_NEWOBJ:
                assert (o & 0xFFFF) < len(back["methods"]), "newobj ctor idx sai"
            elif c in M.TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"]), f"type idx sai: {o}"
            elif c == M.OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"]), "vm idx sai"
    for i in range(before[4]):
        assert back["blocks"][i]["instrs"] == dst["blocks"][i]["instrs"], \
            f"block goc vm{i} bi doi"
    print("   verify: block goc nguyen ven + operand trong pham vi")
    print(f"   body {len(body)} B | hooks {len(back['interpret'])}")

    open(out_path, "wb").write(M.resd_encrypt(body, dres, dtag, denc))
    print(f"   ghi {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 5:
        raise SystemExit(
            'dung: merge_hooks.py <dst.bytes> <src.bytes> <out.bytes> "A::B,C::*"')
    merge_hooks(sys.argv[1], sys.argv[2], sys.argv[3],
                [p.strip() for p in sys.argv[4].split(",") if p.strip()])
