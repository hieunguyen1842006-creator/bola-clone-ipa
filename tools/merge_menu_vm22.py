#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_menu_vm22.py — ghep menu vao HS2 theo dung host payload chay-that.

Host chuan: CTimerManager::Update — payload menuesp (menu thuc su LEN MAN HINH
tren may) hook dung method nay, IFix tu sinh trampoline cho base.Update()
(save wrapperArray slot -> null -> CallExtern than goc -> restore trong catch).
Copy nguyen duong di, khong tu che.

Cach lam:
  1. Remap toan bo index cua Menu.bytes sang HS2 (dung lai Remap cua merge_menu).
  2. Append block menu + DANG KY hook CTimerManager::Update (dedupe theo dst).
  3. Verify: interpret = 6 classic + 1 hook menu; hook block co trampoline IL
     (Ldsfld wrapperArray / IDMAP slot, Stelem_Ref, CallExtern <host>::Update
     argc1); token audit chay tren block hook.
  4. Khong splice vm22, khong dong Classic.

Chay: python tools/merge_menu_vm22.py <HS2.bytes> <Menu.bytes> <out.bytes>
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

OP_CALL = 0x2D
OP_LDFTN = 129


def merge(dst_path: str, menu_path: str, out_path: str) -> None:
    dst, dtag, denc, dres = mm.load(dst_path)
    menu, _mt, _me, _mr = mm.load(menu_path)

    print(f"== dst : {os.path.basename(dst_path)} blocks={len(dst['blocks'])} "
          f"hooks={len(dst['interpret'])}")
    print(f"== menu: {os.path.basename(menu_path)} blocks={len(menu['blocks'])} "
          f"hooks={len(menu['interpret'])}")

    # ---- 1. remap + append block ----
    rp = mm.Remap(dst)
    vmap = {}
    for bi in range(len(menu["blocks"])):
        blk = menu["blocks"][bi]
        vmap[bi] = len(dst["blocks"])
        dst["blocks"].append({"instrs": list(blk["instrs"]),
                              "handlers": [list(h) for h in blk["handlers"]]})
    dst["nextAlloc"] = len(dst["blocks"])

    for sbi, dbi in vmap.items():
        ins = dst["blocks"][dbi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            code, op = ins[k], ins[k + 1]
            if code == mm.OP_LDSTR:
                ins[k + 1] = rp.str_(menu, op)
            elif code in (mm.OP_CALLEXTERN, mm.OP_NEWOBJ):
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(menu, op & 0xFFFF)
            elif code in mm.FIELD_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.field_(menu, op & 0xFFFF)
            elif code in mm.TYPE_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.type_(menu, op & 0xFFFF)
            elif code == OP_CALL:
                tgt = op & 0xFFFF
                if tgt not in vmap:
                    raise SystemExit(f"menu block {sbi} Call vm{tgt} ngoai pham vi")
                ins[k + 1] = ((op >> 16) << 16) | vmap[tgt]
        for handler in dst["blocks"][dbi]["handlers"]:
            handler[1] = rp.type_(menu, handler[1])
    for i in range(len(menu["fields"])):
        rp.field_(menu, i)

    # Host chuan: CTimerManager::Update. Field khai tren CTimerManager.
    f0 = menu["fields"][0]
    assert f0["name"] == "__mMenuCalls"
    assert menu["types"][f0["declType"]].split(",")[0] == "CTimerManager", \
        "field __mMenuCalls phai khai tren CTimerManager — gen_menu34 chua doi?"
    m0 = menu["interpret"][0]["method"]
    assert menu["types"][m0["declType"]].split(",")[0] == "CTimerManager" \
        and m0["name"] == "Update", "menu hook phai la CTimerManager::Update"

    # ---- 2. DANG KY hook (copy tu merge_menu.py, dedupe theo dst) ----
    new_vm = vmap[menu["interpret"][0]["vm"]]
    for h in menu["interpret"]:
        m = h["method"]
        dt = rp.type_(menu, m["declType"])
        ps = [dict(p, id=(rp.type_(menu, p["id"]) if not p["isName"] else p["id"]))
              for p in m["params"]]
        ta = [rp.type_(menu, x) for x in m["typeArgs"]]
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
        print(f"   + hook {dst['types'][rec['declType']].split(',')[0]}"
              f"::{rec['name']} -> vm{vmap[h['vm']]}")

    # ---- 3. roundtrip + verify ----
    body = mm.lqmb_serialize(dst)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    assert len(back["interpret"]) == 7, f"hooks phai 7 (6 classic + Update), thay {len(back['interpret'])}"

    # Trampoline IL trong block hook — copy pattern vm42 menuesp.
    hb = back["blocks"][new_vm]
    i2 = hb["instrs"]
    names = {}
    fld_of = lambda idx: back["fields"][idx]["name"] if 0 <= idx < len(back["fields"]) else "?"
    ldsfld_wrapper = any(i2[2 * k] == 60 and fld_of(i2[2 * k + 1]) == "wrapperArray"
                         for k in range(0, len(i2) // 2))
    call_orig = any(i2[2 * k] == 122 and back["methods"][i2[2 * k + 1] & 0xFFFF]["name"] == "Update"
                    and (i2[2 * k + 1] >> 16) == 1
                    for k in range(0, len(i2) // 2))
    stelem = any(i2[2 * k] == 175 for k in range(0, len(i2) // 2))
    assert ldsfld_wrapper, "thieu Ldsfld wrapperArray — IFix chua sinh trampoline"
    assert call_orig, "thieu CallExtern <host>::Update argc1 — than goc se chet"
    assert stelem, "thieu Stelem_Ref (null slot / restore)"
    print("   trampoline OK: wrapperArray + CallExtern host::Update argc1 + Stelem_Ref")

    # block goc tru khong doi
    for i in range(24):
        if i == 22:
            continue
        assert back["blocks"][i]["instrs"] == dst["blocks"][i]["instrs"], f"vm{i} bi doi"

    # operand block moi trong pham vi
    for bi in sorted(vmap.values()):
        ins2 = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins2) - 1, 2):
            c, o = ins2[k], ins2[k + 1]
            if c in (mm.OP_CALLEXTERN, mm.OP_NEWOBJ):
                assert (o & 0xFFFF) < len(back["methods"])
            elif c == mm.OP_LDSTR:
                assert o < len(back["strings"])
            elif c in mm.FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"])
            elif c in mm.TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"])
            elif c == OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"])

    original, *_ = mm.load(dst_path)
    from test_menu_vm22 import check_tokens
    check_tokens(menu, back, 0, new_vm)
    print("   verify OK: 7 hooks; trampoline present; token audit passed")

    out = mm.resd_encrypt(body, dres, dtag, denc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: merge_menu_vm22.py <HS2.bytes> <Menu.bytes> <out.bytes>")
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
