#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_menu_vm22.py — ghep menu vao HS2 KHONG them hook moi.

Tai sao: hook NetworkModule::UpdateFrame thay TOAN BO than goc (bom goi mang)
-> game treo o man hinh load. Fix: goi block menu tu vm22 (get_frameSynchr cua
LQFull, device-proven, chay moi frame) ngay truoc return.

Cach lam:
  1. Remap toan bo index cua Menu.bytes sang HS2 (dung lai Remap cua merge_menu).
  2. Append block menu vao cuoi dst.blocks — KHONG dang ky interpret hook.
  3. Chen Ldarg0 / Call argc1 tai pc1010 (truoc Ldloc16/Ret cuoi).
     Moi branch ve pc1010 PHAI van den pc1010, khong nhay qua menu.
     Menu tra void, vm22 van tra LFrameSynchr nhu cu.
  4. Chi dich > 1010 moi doi offset; cac handler ket thuc truoc pc1010 giu nguyen.
  5. Giu nguyen bang hook cua dst.

Chay: python tools/merge_menu_vm22.py <HS2.bytes> <Menu.bytes> <out.bytes>
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

OP_CALL = 0x2D            # Call trong file da remap sang LQMB (merge_menu.OP_CALL)
INSERT_PC = 1010          # truoc Ldloc16(1010)/Ret(1011) goc
# Branch opcodes LQMB (opcode_table_lqmb_full.json std_to_game):
# Br 93, Brfalse 134, Brtrue 127, Beq 110, Bge 125, Bgt 11, Ble 17, Blt 47,
# Bne_Un 43, Bge_Un 33, Bgt_Un 30, Ble_Un 176, Blt_Un 111, Leave 153
BR_OPS = {93, 134, 127, 110, 125, 11, 17, 47, 43, 33, 30, 176, 111, 153}


def merge(dst_path: str, menu_path: str, out_path: str) -> None:
    dst, dtag, denc, dres = mm.load(dst_path)
    menu, _mt, _me, _mr = mm.load(menu_path)

    print(f"== dst : {os.path.basename(dst_path)} blocks={len(dst['blocks'])} "
          f"hooks={len(dst['interpret'])}")
    print(f"== menu: {os.path.basename(menu_path)} blocks={len(menu['blocks'])} "
          f"hooks={len(menu['interpret'])}")

    # ---- 1. remap + append block (khong hook) ----
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

    # Separate counter: sharing __mCalls would alter Classic's modulo-20 polling.
    f0 = menu["fields"][0]
    assert f0["name"] == "__mMenuCalls"
    assert menu["types"][f0["declType"]].split(",")[0] == "NucleusDrive.Logic.LFramework", \
        "field __mMenuCalls phai khai tren LFramework — gen_menu34 chua doi?"
    m0 = menu["interpret"][0]["method"]
    assert menu["types"][m0["declType"]].split(",")[0] == "NucleusDrive.Logic.LFramework" \
        and m0["name"] == "get_frameSynchr", "menu hook phai la LFramework::get_frameSynchr"

    new_vm = vmap[menu["interpret"][0]["vm"]]
    print(f"   menu block -> vm{new_vm} (KHONG dang ky hook)")

    # ---- 2. splice Call vao vm22 ----
    b22 = dst["blocks"][22]
    ins = b22["instrs"]
    n = len(ins) // 2
    assert n == 1012, f"vm22 goc phai 1012 lenh, thay {n}"
    assert ins[2 * 1009] == 93 and ins[2 * 1009 + 1] == 1, "pc1009 phai Br 1"
    assert ins[2 * 1010] == 72 and ins[2 * 1010 + 1] == 16, "pc1010 phai Ldloc16"
    assert ins[2 * 1011] == 173 and ins[2 * 1011 + 1] == 1, "pc1011 phai Ret 1"
    assert not any(ins[2 * i] == 149 for i in range(n)), "vm22 co Switch — dung splice"

    # All six return branches must land on the inserted Ldarg0, not skip it.
    inserted = [164, 0, OP_CALL, (1 << 16) | new_vm]
    width = len(inserted) // 2
    for pc in range(n):
        code, operand = ins[2 * pc:2 * pc + 2]
        if code in BR_OPS:
            target = pc + operand
            moved_pc = pc + (width if pc >= INSERT_PC else 0)
            moved_target = target + (width if target > INSERT_PC else 0)
            ins[2 * pc + 1] = moved_target - moved_pc
    for h in b22["handlers"]:
        for j in (2, 3, 4, 5):
            assert h[j] < INSERT_PC, "handler overlaps menu insertion boundary"

    ins[2 * INSERT_PC:2 * INSERT_PC] = inserted
    print(f"   vm22: +Ldarg0/Call argc1 vm{new_vm} @pc{INSERT_PC}, "
          f"return branches preserved, len={len(ins)//2}")

    # ---- 3. roundtrip + verify ----
    body = mm.lqmb_serialize(dst)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    assert len(back["interpret"]) == 6, f"hooks phai 6, thay {len(back['interpret'])}"
    assert all(h["method"]["name"] != "UpdateFrame" for h in back["interpret"])

    b = back["blocks"][22]
    i2 = b["instrs"]
    assert len(i2) // 2 == 1014
    assert i2[2 * 1009 + 1] == 1
    assert i2[2 * 1010:2 * 1012] == inserted
    assert i2[2 * 1012:] == [72, 16, 173, 1]
    for h in b["handlers"]:
        assert all(0 <= h[j] <= 1014 for j in (2, 3, 4, 5)), f"handler vuot bien: {h}"

    # block goc tru vm22 phai khong doi
    for i in range(22):
        assert back["blocks"][i]["instrs"] == dst["blocks"][i]["instrs"], f"vm{i} bi doi"

    # operand block moi trong pham vi
    for bi in sorted(vmap.values()):
        ins2 = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins2) - 1, 2):
            c, o = ins2[k], ins2[k + 1]
            if c == mm.OP_CALLEXTERN or c == mm.OP_NEWOBJ:
                assert (o & 0xFFFF) < len(back["methods"])
            elif c == mm.OP_LDSTR:
                assert o < len(back["strings"])
            elif c in mm.FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"])
            elif c in mm.TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"])
            elif c == OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"])
    # Compare against the original input, not the already-modified destination.
    original, *_ = mm.load(dst_path)
    from test_menu_vm22 import check, check_tokens
    check(original, back)
    check_tokens(menu, back, 0, new_vm)
    print("   verify OK: 6 return branches reach menu; argc1/Ret0/catch remap valid; "
          "token audit passed")

    out = mm.resd_encrypt(body, dres, dtag, denc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: merge_menu_vm22.py <HS2.bytes> <Menu.bytes> <out.bytes>")
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
