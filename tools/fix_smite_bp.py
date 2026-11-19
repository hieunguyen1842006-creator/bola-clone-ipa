#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fix_smite_bp.py — vá 3 lỗi auto-smite / auto-BP trong LQFull.bytes.

Sửa trong block 3 (vm3 = CPlayerLocationStat::UpdateLogic) của HeroSkin_2:

  [P0] AutoSmite: pc 849..883 thay trần HP tuyệt đối 'iFix.AutoSmite.Hp.v1'=1500
       bằng kiểm tra sát thương GetCurrentSkillDamageValue(slot5, target) > 0.
       Nhánh "dmg < hp => bỏ" ở pc 884..886 GIỮ NGUYÊN (đã đúng).
       -> hết trần 1500, smite được boss/baron/rồng.

  [P1] AutoBP: pc 464..479 thêm gate actorHp > 0 và đổi ngưỡng từ
       pref*0.02 (default 16 -> 0.32) sang hằng 0.1377 (đúng bản gốc).

  [P2] TargetMode: pc 633 đổi default 1 -> 0. Code hiện tại:
       1 = trừ boss, 2 = chỉ boss, 0 = tất cả. Default 1 làm mất boss
       theo mặc định; về 0 thì bằng hành vi bản gốc (không lọc gì).

Không đổi số lệnh của block => mọi offset nhánh khác giữ nguyên.

Chay: python tools/fix_smite_bp.py [--dry]
"""
from __future__ import annotations

import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from verify_swift_logic import resd_decrypt, resd_encrypt, lqmb_parse, lqmb_serialize  # noqa: E402

RES = os.path.join(ROOT, "Resources", "LQFull.bytes")
OUT = os.path.join(ROOT, "Resources", "LQFull.bytes")

OP_NOP = 0x67
OP_LDC_I4 = 0x8F
OP_LDC_R4 = 0x8D
OP_LDLOC = 0x48
OP_STLOC = 0x24
OP_LDLOCA = 0x0D
OP_LDFLD = 0xA7
OP_CGT = 0x28
OP_BLT = 0x2F
OP_CALL_M = 0x7A
OP_BRFALSE = 0x86
OP_BGT_UN = 0x1E

# method index trong HeroSkin_2 của Bola
M_GET_ACTOR_HP = 184                     # ValuePropertyComponent::get_actorHp
M_GET_HP_RATE = 180                      # ValuePropertyComponent::GetHpRate
M_GET_SINGLE = 181                       # VFactor::get_single
M_SKILL_DAMAGE = 190                     # SkillSlot::GetCurrentSkillDamageValue(int)

F_0_1377 = 1041039675                    # float 0.1377

BACKUP = os.path.join(ROOT, "Resources", "LQFull.pre-fix.bytes")


def call_extern(method: int, argc: int) -> int:
    return (argc << 16) | method


def split_container(blob: bytes):
    """LQ2\x00 | u32 count | [u8 namelen][name][u32 size][data]"""
    if blob[:4] != b"LQ2\x00":
        raise SystemExit("không phải container LQ2")
    off = 4
    count = struct.unpack_from("<I", blob, off)[0]
    off += 4
    entries = []
    for _ in range(count):
        nlen = blob[off]
        off += 1
        name = blob[off:off + nlen].decode()
        off += nlen
        size = struct.unpack_from("<I", blob, off)[0]
        off += 4
        entries.append([name, blob[off:off + size]])
        off += size
    if off != len(blob):
        raise SystemExit("container còn byte thừa: %d" % (len(blob) - off))
    return entries


def join_container(entries):
    out = bytearray(b"LQ2\x00")
    out += struct.pack("<I", len(entries))
    for name, data in entries:
        nb = name.encode()
        out += bytes([len(nb)])
        out += nb
        out += struct.pack("<I", len(data))
        out += data
    return bytes(out)


def show(pf, ins, pcs, label):
    print("  %s" % label)
    for pc in pcs:
        print("    %4d  %02x %-10d" % (pc, ins[pc * 2], ins[pc * 2 + 1]))


def patch_block3(pf):
    ins = pf["blocks"][3]["instrs"]

    # ---------- P1 : AutoBP ----------
    # 464..479  (16 lệnh)
    bp = [
        OP_LDLOC, 21,
        OP_LDFLD, 38,                       # ValueComponent
        OP_BRFALSE, 488 - 466,              # null -> skip
        OP_LDLOC, 21,
        OP_LDFLD, 38,
        OP_CALL_M, call_extern(M_GET_ACTOR_HP, 1),
        OP_BRFALSE, 488 - 470,              # hp == 0 -> skip
        OP_LDLOC, 21,
        OP_LDFLD, 38,
        OP_CALL_M, call_extern(M_GET_HP_RATE, 1),
        OP_STLOC, 46,
        OP_LDLOCA, 46,
        OP_CALL_M, call_extern(M_GET_SINGLE, 1),
        OP_LDC_R4, F_0_1377,
        OP_NOP, 0,
        OP_BGT_UN, 488 - 479,               # rate > 0.1377 -> skip
    ]
    assert len(bp) == 32, len(bp)
    show(pf, ins, range(464, 480), "TRUOC  AutoBP")
    for i, v in enumerate(bp):
        ins[464 * 2 + i] = v
    show(pf, ins, range(464, 480), "SAU    AutoBP")

    # ---------- P0 : AutoSmite ----------
    # 849..883  (35 lệnh)
    sm = [
        OP_LDLOC, 14,                       # skill slot
        OP_LDLOC, 25,                       # target ActorLinker
        OP_CALL_M, call_extern(M_SKILL_DAMAGE, 2),
        OP_STLOC, 42,                       # l42 = dmg
        OP_LDLOC, 41,                       # l41 = actorHp (đã set ở 841)
        OP_STLOC, 43,                       # l43 = hp
        OP_LDLOC, 42,
        OP_LDC_I4, 0,
        OP_CGT, 0,                          # dmg > 0 ?
        OP_BRFALSE, 917 - 858,              # dmg <= 0 -> skip
        OP_LDLOC, 42,
        OP_LDLOC, 43,
        OP_BLT, 917 - 861,                  # dmg < hp -> skip (không giết được)
    ]
    sm += [OP_NOP, 0] * (883 - 861)         # 862..883
    assert len(sm) == 70, len(sm)
    show(pf, ins, list(range(849, 860)) + [883, 884, 885, 886], "TRUOC  AutoSmite")
    for i, v in enumerate(sm):
        ins[849 * 2 + i] = v
    show(pf, ins, list(range(849, 860)) + [883, 884, 885, 886], "SAU    AutoSmite")

    # ---------- P2 : TargetMode default ----------
    assert ins[632 * 2] == 0x27, "pc632 phải là Ldstr"
    assert ins[633 * 2] == OP_LDC_I4 and ins[633 * 2 + 1] == 1, \
        "pc633 phải là Ldc_I4 1, nhận %02x %d" % (ins[633 * 2], ins[633 * 2 + 1])
    ins[633 * 2 + 1] = 0
    print("  TargetMode default: 1 -> 0 (0 = tất cả, giống bản gốc)")


def main():
    dry = "--dry" in sys.argv
    blob = open(RES, "rb").read()
    entries = split_container(blob)

    idx = next(i for i, (n, _) in enumerate(entries) if n.startswith("HeroSkin_2"))
    name, data = entries[idx]
    tag, orig, body, enc = resd_decrypt(data, "HeroSkin_2")
    pf = lqmb_parse(body)
    print("HeroSkin_2: %d block, %d hook, tag=%d enc=%s" %
          (len(pf["blocks"]), len(pf["interpret"]), tag, enc))

    patch_block3(pf)

    new_body = lqmb_serialize(pf)
    assert len(new_body) == len(body), "serialize đổi kích thước: %d -> %d" % (
        len(body), len(new_body))
    back = lqmb_parse(new_body)
    assert [len(b["instrs"]) for b in back["blocks"]] == \
           [len(b["instrs"]) for b in pf["blocks"]], "block size lệch"

    new_data = resd_encrypt(new_body, "HeroSkin_2", tag, encrypt=enc)
    entries[idx][1] = new_data
    out = join_container(entries)

    if dry:
        print("\n--dry: không ghi. Kích thước %d -> %d B" % (len(blob), len(out)))
        return

    if not os.path.exists(BACKUP):
        open(BACKUP, "wb").write(blob)
        print("backup -> %s" % BACKUP)
    open(OUT, "wb").write(out)
    print("\nghi %s  (%d -> %d B)" % (OUT, len(blob), len(out)))

    # verify đọc lại
    chk = split_container(open(OUT, "rb").read())
    _, d2 = next((n, d) for n, d in chk if n.startswith("HeroSkin_2"))
    _t, _o, b2, _e = resd_decrypt(d2, "HeroSkin_2")
    p2 = lqmb_parse(b2)
    i2 = p2["blocks"][3]["instrs"]
    ok_bp = i2[464 * 2:480 * 2] == pf["blocks"][3]["instrs"][464 * 2:480 * 2]
    ok_sm = i2[849 * 2:887 * 2] == pf["blocks"][3]["instrs"][849 * 2:887 * 2]
    print("round-trip AutoBP  :", "OK" if ok_bp else "FAIL")
    print("round-trip AutoSmite:", "OK" if ok_sm else "FAIL")


if __name__ == "__main__":
    main()
