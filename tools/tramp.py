#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tramp.py — gắn trampoline giữ thân gốc vào block hook CTimerManager::Update.

IL chuẩn copy từ vm42 của payload menuesp (menu THẬT lên màn hình trên máy):
  locA = wrapperArray
  locB = IDMAP slot field <Type>-<Method><0>
  locS = wrapperArray[locB]           (saved)
  wrapperArray[locB] = null
  this.Update()                       (CallExtern — reflection invoke thân gốc)
  wrapperArray[locB] = locS           (restore)

Translator chuẩn không sinh trampoline cho self-call (sinh Call vm0 = đệ quy),
nên trampoline được gắn tay trên Menu.bytes trước merge; các index mới được
merge remap tự động.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

OP_STACKSPACE = 146
OP_LDSFLD = 60
OP_STLOC = 36
OP_LDLOC = 72
OP_LDELEM_REF = 129
OP_LDNULL = 117
OP_STELEM_REF = 175
OP_LDARG = 164
OP_CALLEXTERN = 122


def ensure_type(p, full):
    """full là chuỗi ĐẦY ĐỦ assembly-qualified (copy từ payload chạy-thật).

    Chuỗi trần thiếu qualifier (vd 'IFix.IDMAP0') thì Type.GetType trên máy
    trả NULL → hook chết ngay Ldsfld đầu → thân gốc không chạy → treo load.
    """
    short = full.split(",")[0].strip()
    for i, t in enumerate(p["types"]):
        if t == full or t.split(",")[0].strip() == short:
            return i
    p["types"].append(full)
    return len(p["types"]) - 1


def ensure_field(p, decl_type, name):
    for i, f in enumerate(p["fields"]):
        if f["name"] == name:
            return i
    p["fields"].append({"isNew": False, "declType": decl_type, "name": name,
                        "ftype": -1, "ctor": -1})
    return len(p["fields"]) - 1


def ensure_method(p, decl_type, name):
    for i, m in enumerate(p["methods"]):
        if (m["name"] == name
                and p["types"][m["declType"]].split(",")[0]
                == p["types"][decl_type].split(",")[0]
                and len(m["params"]) == 0):
            return i
    p["methods"].append({"isGeneric": False, "declType": decl_type, "name": name,
                         "typeArgs": [], "params": []})
    return len(p["methods"]) - 1


def add_trampoline(menu_path, out_path, target_type, target_method):
    p, tag, enc, res = mm.load(menu_path)
    blk = p["blocks"][p["interpret"][0]["vm"]]
    ins = blk["instrs"]
    n = len(ins) // 2

    # Chuỗi CHÍNH XÁC từ payload chạy-thật (menuesp) — thiếu qualifier là treo.
    t_wrap = ensure_type(p, "IFix.ILFixDynamicMethodWrapper, Project.Plugins_d")
    t_idmap = ensure_type(p, "IFix.IDMAP0, Project.Plugins_d")
    f_arr = ensure_field(p, t_wrap, "wrapperArray")
    f_slot = ensure_field(p, t_idmap, target_type + "-" + target_method + "0")
    m_orig = ensure_method(p, ensure_type(p, target_type), target_method)
    assert p["methods"][m_orig]["params"] == [], "extern Update entry phải 0 params"

    # locals: 3 slot trên max slot đang dùng (StackSpace.locals có thể lớn hơn)
    max_loc = -1
    for k in range(n):
        c, o = ins[2 * k], ins[2 * k + 1]
        if c in (72, 36):  # Ldloc / Stloc
            max_loc = max(max_loc, o)
    base = max_loc + 1
    la, lb, ls = base, base + 1, base + 2
    locals_n = ins[1] >> 16
    maxstack = ins[1] & 0xFFFF
    if base + 2 >= locals_n:
        ins[1] = ((base + 3) << 16) | maxstack

    tram = []
    tram += [OP_LDSFLD, f_arr, OP_STLOC, la]
    tram += [OP_LDSFLD, f_slot, OP_STLOC, lb]
    tram += [OP_LDLOC, la, OP_LDLOC, lb, OP_LDELEM_REF, 0, OP_STLOC, ls]
    tram += [OP_LDLOC, la, OP_LDLOC, lb, OP_LDNULL, 0, OP_STELEM_REF, 0]
    tram += [OP_LDARG, 0, OP_CALLEXTERN, (1 << 16) | m_orig]
    tram += [OP_LDLOC, la, OP_LDLOC, lb, OP_LDLOC, ls, OP_STELEM_REF, 0]

    # chèn tại pc1 (giữ StackSpace ở pc0). Operand branch là TƯƠNG ĐỐI — site
    # và target cùng dịch +width nên KHÔNG đổi operand (sai chỗ này là lý do
    # v1.9 treo load). Chỉ handler offset (tuyệt đối) mới +width.
    width = len(tram) // 2
    assert not any(ins[2 * k] == 149 for k in range(n)), "block có Switch — cần shift jump table"
    for h in blk["handlers"]:
        for j in (2, 3, 4, 5):
            if h[j] >= 1:
                h[j] += width
    ins[2 * 1:2 * 1] = tram

    body = mm.lqmb_serialize(p)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["blocks"][0]["instrs"][2 * 1:2 * 1 + len(tram)] == tram

    # soát branch: phần thân sau trampoline phải khớp origin từng cặp, và mọi
    # nhánh phải trúng đúng lệnh cũ (site lẫn target cùng dịch +width)
    BR = {93, 134, 127, 110, 125, 11, 17, 47, 43, 33, 30, 176, 111, 153}
    orig, _, _, _ = mm.load(menu_path)
    oins = orig["blocks"][0]["instrs"]
    b2 = back["blocks"][0]["instrs"]
    for k in range(1, n):  # pc0 = StackSpace, giữ nguyên vị trí (operand locals đã +3)
        oc, oo = oins[2 * k], oins[2 * k + 1]
        nc, no = b2[2 * (k + width)], b2[2 * (k + width) + 1]
        assert (oc, oo) == (nc, no), \
            f"pc{k} bị lệch sau chèn: ({oc},{oo}) -> ({nc},{no})"
        if oc in BR:
            assert k + oo + width == (k + width) + no, \
                f"nhánh pc{k} target sai: cũ {k + oo}, mới {(k + width) + no}"
    assert b2[0] == 146 and b2[1] == ((max_loc + 4) << 16) | maxstack, \
        "StackSpace sau chèn sai"
    print(f"   branch audit OK: {n} ins, branch targets consistent")
    out = mm.resd_encrypt(body, res, tag, enc)
    open(out_path, "wb").write(out)
    print(f"trampoline: +{width} ins (fields {f_arr},{f_slot}, method {m_orig}), "
          f"locals {locals_n}->{ins[1] >> 16}, {n}->{n + width} ins")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: tramp.py <Menu.bytes> <out.bytes> "
                         "[target_type] [target_method]")
    tgt = sys.argv[3] if len(sys.argv) > 3 else "CTimerManager"
    mtd = sys.argv[4] if len(sys.argv) > 4 else "Update"
    add_trampoline(sys.argv[1], sys.argv[2], tgt, mtd)
