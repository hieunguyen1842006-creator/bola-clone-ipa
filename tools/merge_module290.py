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
    # MENU pack = BẢN MỚI THUẦN: bỏ 6 hook classic (vm22 đọc nvh_aov.txt +
    # vm3 vẽ ESP quái classic là lý do user còn thấy ESP cũ).
    CLASSIC = {"LoadMsg", "CacheRecord", "UpdateLogic", "GetActorSkinID",
               "get_frameSynchr", "IsAtMyTeam"}
    kept = [h for h in dst["interpret"]
            if h["method"]["name"] not in CLASSIC]
    dropped = len(dst["interpret"]) - len(kept)
    dst["interpret"] = kept
    assert len(dst["interpret"]) == 1, "menu hook phải còn lại"
    print(f"   strip classic hooks: -{dropped}, còn {len(dst['interpret'])}")
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

    # ---- tái hiện luồng gốc: phá deadlock key-UI của module ----
    # Thiết kế của module: nút KEY chỉ xuất hiện khi keyui_wants==1, mà wants
    # chỉ được bật bởi chính nút KEY (deadlock trên máy mới). Stage-0 gốc phá
    # deadlock bằng grant GameObject ký RSA. Ở đây: khi pref nvh.m290.on = 1
    # và CHƯA auth (field 2075 = false), set keyui_wants (field 2250) = 1 mỗi
    # tick → module TỰ fetch schema + dựng BẢNG LOGIN KEY của chính nó; user
    # nhập key trong game → submit → server verify → auth=true → toàn bộ
    # menu + ESP mới của module mở khoá đúng như bản gốc.
    # Đồng thời NOP 2 cổng IsGameLogicStarted (vm10 + vm8) để tick + dựng
    # canvas chạy ngay ở LOBBY — bảng login hiện như bản gốc, ESP vẫn gate
    # battle riêng (mainBattleLogic null ở lobby → an toàn).
    MENU_ON = "nvh.m290.on"
    menu_on_str = None
    for j, t in enumerate(dst["strings"]):
        if t == MENU_ON:
            menu_on_str = j
            break
    if menu_on_str is None:
        dst["strings"].append(MENU_ON)
        menu_on_str = len(dst["strings"]) - 1

    auth_dst = rp.field_(src, 2075)     # auth bool (writers: vm1884/vm1902/1792/1798)
    wants_dst = rp.field_(src, 2250)    # keyui_wants (writers: vm1790=0/vm1791=1)
    vm77_dst = vmap[77]                 # module boot + tick-hub caller (vm61)

    getint = None
    for j, m in enumerate(dst["methods"]):
        if (m["name"] == "GetInt"
                and dst["types"][m["declType"]].split(",")[0] == "UnityEngine.PlayerPrefs"
                and len(m["params"]) == 2):
            getint = j
            break
    assert getint is not None, "thiếu PlayerPrefs::GetInt(argc2) trong dst"

    # vm10 dst = hook get_frameSynchr của module
    vm10_dst = vmap[10]
    ins10 = dst["blocks"][vm10_dst]["instrs"]
    n10 = len(ins10) // 2
    assert not any(ins10[2 * k] == OP_SWITCH for k in range(n10)), "vm10 có Switch"
    # splice tại pc1 (giữ StackSpace pc0); branch operand TƯƠNG ĐỐI — site lẫn
    # target cùng dịch nên KHÔNG đổi (bài học tramp v1.9); handler +W (tuyệt đối)
    # I0 Ldstr  I1 Ldc  I2 GetInt  I3 Brfalse->END
    # I4 Ldarg  I5 Call vm77 (boot + tick hub vm61, dedupe frameCount sẵn trong vm77)
    # I6 Ldarg  I7 Ldfld auth  I8 Brtrue->skipW  I9 Ldarg  I10 Ldc1  I11 Stfld wants
    sp = [39, menu_on_str,
          143, 0,
          122, (2 << 16) | getint,
          134, 9,                # Brfalse -> END (switch OFF: bỏ hết)
          164, 0,
          45, (1 << 16) | vm77_dst,   # Call vm77 mỗi frame (dedupe bên trong)
          164, 0,
          167, auth_dst,
          127, 4,                # Brtrue -> skipW (đã auth: đừng ép wants)
          164, 0,
          143, 1,
          75, wants_dst]         # Stfld keyui_wants = 1
    W = len(sp) // 2             # 11
    BRSET = {93, 134, 127, 110, 125, 11, 17, 47, 43, 33, 30, 176, 111, 153}
    for h in dst["blocks"][vm10_dst]["handlers"]:
        for j in (2, 3, 4, 5):
            if h[j] >= 1:
                h[j] += W
    ins10[2 * 1:2 * 1] = sp
    print(f"   key-ui bootstrap: vm{vm10_dst} += wants=1 gate(pref/auth), +{W} ins")

    # NOP cổng IsGameLogicStarted trong vm10 (CallExtern + Brfalse liền nhau)
    def nop_gate(block_idx, blk_ins, blk_n):
        hit = 0
        for k in range(blk_n - 1):
            if blk_ins[2 * k] == 122 and blk_ins[2 * k + 2] == 134:
                mi = blk_ins[2 * k + 1] & 0xFFFF
                if dst["methods"][mi]["name"] == "get_IsGameLogicStarted":
                    blk_ins[2 * k] = 103
                    blk_ins[2 * k + 1] = 0
                    blk_ins[2 * k + 2] = 103
                    blk_ins[2 * k + 3] = 0
                    hit += 1
        return hit
    g1 = nop_gate(vm10_dst, ins10, len(ins10) // 2)
    vm8_dst = vmap[8]
    ins8 = dst["blocks"][vm8_dst]["instrs"]
    g2 = nop_gate(vm8_dst, ins8, len(ins8) // 2)
    print(f"   NOP IsGameLogicStarted gates: vm{vm10_dst} x{g1}, vm{vm8_dst} x{g2}")
    assert g1 == 1 and g2 == 1, "không tìm thấy đúng 1 cổng IsGameLogicStarted mỗi block"

    # vm51/vm52 = reflection re-install hook (loader đã cài rồi — chạy lại chỉ
    # có nguy cơ throw → field 27 latch = ESP fleet chết vĩnh viễn). NOP 2 Call.
    vm51_dst, vm52_dst = vmap[51], vmap[52]
    nopd = 0
    for k in range(len(ins8) // 2):
        if ins8[2 * k] == OP_CALL:
            tgt = ins8[2 * k + 1] & 0xFFFF
            if tgt in (vm51_dst, vm52_dst):
                ins8[2 * k] = 103
                ins8[2 * k + 1] = 0
                nopd += 1
    print(f"   NOP vm51/vm52 reflection re-install trong vm8: x{nopd}")
    assert nopd == 2, f"phải NOP đúng 2 Call vm51/vm52 trong vm8, thấy {nopd}"
    vm82_dst = vmap[82]
    ins82 = dst["blocks"][vm82_dst]["instrs"]
    nopd2 = 0
    for k in range(len(ins82) // 2):
        if ins82[2 * k] == OP_CALL:
            tgt = ins82[2 * k + 1] & 0xFFFF
            if tgt in (vm51_dst, vm52_dst):
                ins82[2 * k] = 103
                ins82[2 * k + 1] = 0
                nopd2 += 1
    print(f"   NOP vm51/vm52 reflection re-install trong vm82: x{nopd2}")

    # ---- đăng ký 5 hook KHÔNG trùng của module (vm1583 do vm24 chiếm) ----
    # vm10 get_frameSynchr (tick hub 10Hz, tự trả _frameSynchr như getter gốc),
    # vm84 get_deltaTime (trampoline chuẩn), vm1800/1802/1803 (vỏ replay
    # GIỮ logic gốc — không thay hành vi game).
    MOD_SKIP = {"Update"}   # CTimerManager::Update — vm24 đã chiếm
    for h in src["interpret"]:
        m = h["method"]
        if m["name"] in MOD_SKIP:
            continue
        dt = rp.type_(src, m["declType"])
        ps = [dict(q, id=(rp.type_(src, q["id"]) if not q["isName"] else q["id"]))
              for q in m["params"]]
        ta = [rp.type_(src, x) for x in m["typeArgs"]]
        mi = -1
        for j, cm in enumerate(dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [q["id"] for q in cm["params"]] == [q["id"] for q in ps]
                    and [q["isName"] for q in cm["params"]] == [q["isName"] for q in ps]):
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
                "params": [dict(q) for q in rec["params"]],
            },
            "vm": vmap[h["vm"]],
        })
        print(f"   + module hook {dst['types'][rec['declType']].split(',')[0]}"
              f"::{rec['name']} -> vm{vmap[h['vm']]}")

    # ---- dispatcher: chèn Ldarg0 + Call vm_tick vào vm24 (menu block) ----
    tick_src = None
    for h in src["interpret"]:
        if h["method"]["name"] == "Update" and \
                src["types"][h["method"]["declType"]].split(",")[0] == "CTimerManager":
            tick_src = h["vm"]
            break
    assert tick_src is not None, "module290 thiếu hook CTimerManager::Update"
    tick_dst = vmap[tick_src]

    # menu block = hook CTimerManager::Update (interpret[-1] giờ là module hook)
    menu_vm = None
    for h in dst["interpret"]:
        if (h["method"]["name"] == "Update"
                and dst["types"][h["method"]["declType"]].split(",")[0] == "CTimerManager"):
            menu_vm = h["vm"]
            break
    assert menu_vm is not None, "không tìm thấy menu hook CTimerManager::Update"
    ins = dst["blocks"][menu_vm]["instrs"]
    n = len(ins) // 2
    rets = [k for k in range(n) if ins[2 * k] == OP_RET]
    assert len(rets) == 1, f"menu block phải có đúng 1 Ret, thấy {len(rets)}"
    ret_pc = rets[0]
    assert not any(ins[2 * k] == OP_SWITCH for k in range(n)), "menu block có Switch"
    # dispatcher có GATE: đọc pref "nvh.m290.on" (mặc định TẮT) trước khi gọi
    # tick module — lỗi module không được kéo menu chết cùng.
    gate_str = None
    for j, t in enumerate(dst["strings"]):
        if t == "nvh.m290.on":
            gate_str = j
            break
    if gate_str is None:
        dst["strings"].append("nvh.m290.on")
        gate_str = len(dst["strings"]) - 1
    getint = None
    for j, m in enumerate(dst["methods"]):
        if (m["name"] == "GetInt"
                and dst["types"][m["declType"]].split(",")[0] == "UnityEngine.PlayerPrefs"
                and len(m["params"]) == 2):
            getint = j
            break
    assert getint is not None, "thiếu PlayerPrefs::GetInt(argc2) trong dst"
    disp = [mm.OP_LDSTR, gate_str,
            143, 0,                       # Ldc_I4 0
            122, (2 << 16) | getint,      # CallExtern PlayerPrefs::GetInt argc2
            134, 3,                       # Brfalse -> Ret (pcI+6)
            OP_LDARG, 0,
            OP_CALL, (1 << 16) | tick_dst]
    insert_pc = ret_pc          # ngay trước Ret cuối
    width = len(disp) // 2      # 6 lệnh
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
    ins[2 * insert_pc:2 * insert_pc] = disp
    print(f"   dispatcher: vm{menu_vm} pc{insert_pc} += gate(nvh.m290.on) "
          f"/ Ldarg0 / Call vm{tick_dst}")

    # ---- roundtrip + verify ----
    body = mm.lqmb_serialize(dst)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    assert len(back["interpret"]) == 6, f"hooks phải 6 (menu + 5 module), thấy {len(back['interpret'])}"
    i2 = back["blocks"][menu_vm]["instrs"]
    assert i2[2 * insert_pc:2 * insert_pc + len(disp)] == disp
    assert i2[2 * (insert_pc + width)] == OP_RET
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
