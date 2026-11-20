#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_module290.py — bê TOÀN BỘ block MODULE290 (2895 block) vào HS2 menu pack.

module.bin = LQMB raw (magic d0db2c0e465fd41f), bridge/wrapper cùng Project.Plugins_d
với HS2. Chỉ APPEND blocks + remap bảng — KHÔNG đăng ký interpret hooks của module
(tránh đè hook classic). Tick của module chạy qua dispatcher: vm24 (menu) chèn
Ldarg0 + Call vm_tick (vm1583 của module — trampoline giữ thân gốc CTimerManager::Update
và gọi vm1581 module tick) ngay trước Ret cuối. Slot CTimerManager-Update0 dùng chung:
slot null → preamble fallback thân gốc → không đệ quy.

Chạy: python tools/merge_module290.py <HS2_menu.bytes> <module.bin> <out.bytes>
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

OP_CALL = 0x2D
OP_LDARG = 164
OP_RET = 173
OP_SWITCH = 149


def merge(hs2_menu_path: str, module_path: str, out_path: str) -> None:
    dst, dtag, denc, dres = mm.load(hs2_menu_path, "HeroSkin_2")
    blob = open(module_path, "rb").read()
    src = mm.lqmb_parse(blob)

    print(f"== dst : {os.path.basename(hs2_menu_path)} blocks={len(dst['blocks'])} "
          f"hooks={len(dst['interpret'])}")
    print(f"== src : module290 blocks={len(src['blocks'])} "
          f"types={len(src['types'])} methods={len(src['methods'])} "
          f"strings={len(src['strings'])} fields={len(src['fields'])}")

    base = len(dst["blocks"])
    vmap = {}
    for bi in range(len(src["blocks"])):
        blk = src["blocks"][bi]
        vmap[bi] = base + bi
        dst["blocks"].append({"instrs": list(blk["instrs"]),
                              "handlers": [list(h) for h in blk["handlers"]]})
    dst["nextAlloc"] = len(dst["blocks"])

    rp = mm.Remap(dst)
    for sbi in range(len(src["blocks"])):
        ins = dst["blocks"][vmap[sbi]]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            code, op = ins[k], ins[k + 1]
            if code == mm.OP_LDSTR:
                ins[k + 1] = rp.str_(src, op)
            elif code in (mm.OP_CALLEXTERN, mm.OP_NEWOBJ):
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(src, op & 0xFFFF)
            elif code in mm.FIELD_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.field_(src, op & 0xFFFF)
            elif code in mm.TYPE_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.type_(src, op & 0xFFFF)
            elif code == OP_CALL:
                ins[k + 1] = ((op >> 16) << 16) | vmap[op & 0xFFFF]
        for handler in dst["blocks"][vmap[sbi]]["handlers"]:
            handler[1] = rp.type_(src, handler[1])
    for i in range(len(src["fields"])):
        rp.field_(src, i)

    # ---- dispatcher: chèn Ldarg0 + Call vm_tick vào vm24 (menu block) ----
    tick_src = None
    for h in src["interpret"]:
        if h["method"]["name"] == "Update" and \
                src["types"][h["method"]["declType"]].split(",")[0] == "CTimerManager":
            tick_src = h["vm"]
            break
    assert tick_src is not None, "module290 thiếu hook CTimerManager::Update"
    tick_dst = vmap[tick_src]

    menu_vm = dst["interpret"][-1]["vm"]
    ins = dst["blocks"][menu_vm]["instrs"]
    n = len(ins) // 2
    rets = [k for k in range(n) if ins[2 * k] == OP_RET]
    assert len(rets) == 1, f"menu block phải có đúng 1 Ret, thấy {len(rets)}"
    ret_pc = rets[0]
    assert not any(ins[2 * k] == OP_SWITCH for k in range(n)), "menu block có Switch"
    insert_pc = ret_pc          # ngay trước Ret cuối
    width = 2
    BR = {93, 134, 127, 110, 125, 11, 17, 47, 43, 33, 30, 176, 111, 153}
    for k in range(n):
        if ins[2 * k] in BR:
            tgt = k + ins[2 * k + 1]
            if tgt >= insert_pc:
                ins[2 * k + 1] += width
    for h in dst["blocks"][menu_vm]["handlers"]:
        for j in (2, 3, 4, 5):
            if h[j] >= insert_pc:
                h[j] += width
    ins[2 * insert_pc:2 * insert_pc] = [OP_LDARG, 0, OP_CALL, (1 << 16) | tick_dst]
    print(f"   dispatcher: vm{menu_vm} pc{insert_pc} += Ldarg0/Call vm{tick_dst} (module tick)")

    # ---- roundtrip + verify ----
    body = mm.lqmb_serialize(dst)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    assert len(back["interpret"]) == 7, f"hooks phải 7, thấy {len(back['interpret'])}"
    i2 = back["blocks"][menu_vm]["instrs"]
    assert i2[2 * insert_pc:2 * (insert_pc + 2)] == [OP_LDARG, 0, OP_CALL, (1 << 16) | tick_dst]
    assert i2[2 * (insert_pc + 2)] == OP_RET
    # mọi operand của block mới trong phạm vi
    for bi in range(base, len(back["blocks"])):
        ins2 = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins2) - 1, 2):
            c, o = ins2[k], ins2[k + 1]
            if c in (mm.OP_CALLEXTERN, mm.OP_NEWOBJ):
                assert (o & 0xFFFF) < len(back["methods"]), f"method idx vm{bi} pc{k}"
            elif c == mm.OP_LDSTR:
                assert o < len(back["strings"]), f"string idx vm{bi} pc{k}"
            elif c in mm.FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"]), f"field idx vm{bi} pc{k}"
            elif c in mm.TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"]), f"type idx vm{bi} pc{k}"
            elif c == OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"]), f"call idx vm{bi} pc{k}"
    print(f"   verify OK: {len(back['blocks'])} blocks, dispatcher inserted, hooks still 7")

    out = mm.resd_encrypt(body, dres, dtag, denc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: merge_module290.py <HS2_menu.bytes> <module.bin> <out.bytes>")
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
