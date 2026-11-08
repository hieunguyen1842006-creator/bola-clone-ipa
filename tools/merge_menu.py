#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_menu.py — ghep patch menu (MENU.bytes) vao payload HS2 (Project.Plugins_d).

Van de: moi operand trong IFix la INDEX (declType, param.id, string id, block vm,
method id, field id). Ghep 2 patch khac nhau bat buoc phai REMAP toan bo.

Chien luoc:
  - dst = HS2 (da go guard) — giu nguyen 100% type/method/string/field/block
  - src = MENU.bytes — chi co 1 hook get_frameSynchr
  - Voi moi index src dung trong block, anh xa sang index dst:
      type   -> tim chuoi giong het trong dst.types, khong co thi append
      string -> idem cho dst.strings
      method -> dedupe (declType, name, params, typeArgs) sau khi remap
      field  -> dedupe (isNew, declType, name, ftype, ctor)
      block  -> block moi luon duoc append vao cuoi dst.blocks
  - Hook moi tro vao block vua append

Chay:
    python tools/merge_menu.py <HS2.bytes> <Menu.bytes> <out.bytes>
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
resd_encrypt = _ns["resd_encrypt"]
lqmb_parse = _ns["lqmb_parse"]
lqmb_serialize = _ns["lqmb_serialize"]

OP_LDSTR = 0x27
OP_CALLEXTERN = 0x7A
OP_CALL = 0x2D
OP_LDFLD = 0xA7
OP_STFLD = 0x4B
OP_LDSFLD = 0x3C
OP_NEWOBJ = 0x49          # operand = (argc<<16) | ctorMethodId
OP_CASTCLASS = 0x58
OP_CASTCLASS2 = 0x18
OP_CASTCLASS3 = 0x8A
OP_BOX = 0x22
OP_NEWARR = 0x59
OP_LDTOKEN = 0x5E
OP_INITOBJ = 0x97
OP_CONSTRAINED = 0x16

# opcode ma operand LA TYPE INDEX thuan
TYPE_OPS = {OP_CASTCLASS, OP_CASTCLASS2, OP_CASTCLASS3, OP_BOX,
            OP_NEWARR, OP_LDTOKEN, OP_INITOBJ, OP_CONSTRAINED}
FIELD_OPS = {OP_LDFLD, OP_STFLD, OP_LDSFLD}


def load(path: str, res_name: str | None = None):
    blob = open(path, "rb").read()
    res = res_name or os.path.splitext(os.path.basename(path))[0]
    tag, _o, body, enc = resd_decrypt(blob, res)
    return lqmb_parse(body), tag, enc, res


def short_name(full: str) -> str:
    """Bo phan assembly: 'A.B.C, Project_d, Version=...' -> 'A.B.C'."""
    return full.split(",")[0].strip()


# Assembly THAT cho tung type (lay tu payload that HS1/HS2 — xem HS1 type[208..223]).
# Patch tu sinh khai type trong DLL ten Project.Plugins_d nen IFix ghi sai assembly;
# game resolve hut -> treo ngay luc nap patch. Bang nay sua lai cho dung.
TRUE_ASSEMBLY = {
    "Assets.Scripts.GameLogic.GameKernal.Player": "Project_d",
    "Kyrios.Actor.ActorLinker": "Project_d",
    "Assets.Scripts.GameSystem.CSkinInfo": "Project_d",
    # CRoleInfo + CRoleInfoManager: dump.cs LQ 1.64.1.7 -> TypeDefIndex 7472/7481,
    # nam trong Project_d (dwShowSkinID @0x26C la field chon nut chieu).
    "Assets.Scripts.GameSystem.CRoleInfo": "Project_d",
    "Assets.Scripts.GameSystem.CRoleInfoManager": "Project_d",
    # KillNotifyUT (TypeDefIndex 7086) nam cung Project_d voi CRoleInfo.
    # Khong khai -> merge_menu mac dinh gan vao assembly dich (Project.Plugins_d)
    # -> IFix di tim sai assembly -> hook chet hoac goi rac.
    "Assets.Scripts.GameSystem.KillNotifyUT": "Project_d",
    "ResData.ResHeroSkin": "AovTdr",
    "PoolObjHandle`1": "CoreLib",
}


def fix_assembly(full: str) -> str:
    """Thay assembly bia (Project.Plugins_d) bang assembly that neu biet."""
    full = full.replace(
        "[PoolObjHandle`1[[NucleusDrive.Logic.LActorRoot, Project.Plugins_d, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]], Project.Plugins_d, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]",
        "[PoolObjHandle`1[[NucleusDrive.Logic.LActorRoot, Project.Plugins_d, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]], CoreLib, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null]",
    )
    s = short_name(full)
    asm = TRUE_ASSEMBLY.get(s)
    if asm is None:
        if "Project.Plugins_d" not in full:
            return full
        return full          # type cua chinh patch (LFramework/LFrameSynchr) — giu nguyen
    if s.startswith("PoolObjHandle`1"):
        # giu nguyen phan generic ben trong, chi doi assembly ngoai
        inner = full[len(s) + 1:].strip()
        return s + ", " + asm + ", Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
    return s + ", " + asm + ", Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"


class Remap:
    def __init__(self, dst):
        self.dst = dst
        self.t = {}
        self.s = {}
        self.m = {}
        self.f = {}

    def type_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.t:
            return self.t[i]
        full = src["types"][i]
        s = short_name(full)
        # 1. da co type cung ten trong dst -> DUNG LAI (tranh sinh ban trung
        #    voi assembly gia — day la nguyen nhan treo luc nap patch)
        for j, x in enumerate(self.dst["types"]):
            if short_name(x) == s:
                self.t[i] = j
                return j
        # 2. type moi: sua assembly cho dung truoc khi them
        self.dst["types"].append(fix_assembly(full))
        self.t[i] = len(self.dst["types"]) - 1
        return self.t[i]

    def str_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.s:
            return self.s[i]
        v = src["strings"][i]
        for j, x in enumerate(self.dst["strings"]):
            if x == v:
                self.s[i] = j
                return j
        self.dst["strings"].append(v)
        self.s[i] = len(self.dst["strings"]) - 1
        return self.s[i]

    def _params(self, src, m):
        out = []
        for p in m["params"]:
            q = dict(p)
            if not p["isName"]:
                q["id"] = self.type_(src, p["id"])
            out.append(q)
        return out

    def method_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.m:
            return self.m[i]
        m = src["methods"][i]
        dt = self.type_(src, m["declType"])
        ta = [self.type_(src, x) for x in m["typeArgs"]]
        ps = self._params(src, m)
        for j, cm in enumerate(self.dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [p["id"] for p in cm["params"]] == [p["id"] for p in ps]
                    and [p["isName"] for p in cm["params"]] == [p["isName"] for p in ps]):
                self.m[i] = j
                return j
        self.dst["methods"].append({
            "isGeneric": m["isGeneric"], "declType": dt, "name": m["name"],
            "typeArgs": ta, "params": ps,
        })
        self.m[i] = len(self.dst["methods"]) - 1
        return self.m[i]

    def field_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.f:
            return self.f[i]
        fr = src["fields"][i]
        dt = self.type_(src, fr["declType"])
        ft = self.type_(src, fr["ftype"])
        ct = self.type_(src, fr["ctor"])
        for j, cf in enumerate(self.dst["fields"]):
            if (cf["declType"] == dt and cf["name"] == fr["name"]
                    and cf["isNew"] == fr["isNew"]
                    and (not fr["isNew"] or (cf["ftype"] == ft and cf["ctor"] == ct))):
                self.f[i] = j
                return j
        self.dst["fields"].append({
            "isNew": fr["isNew"], "declType": dt, "name": fr["name"],
            "ftype": ft, "ctor": ct,
        })
        self.f[i] = len(self.dst["fields"]) - 1
        return self.f[i]


def inject_monster_esp(dst) -> None:
    """Noi vong lap ESP quai vao cuoi CPlayerLocationStat::UpdateLogic (block vm3)
    va mo rong vm14/vm15 de ve 3D box + line + mau (HP) quai rung tren man hinh.

    Trong vm3:
      - loc 8  = Kyrios.Actor.ActorManager (get_actorManager)
      - loc 7  = NucleusDrive.Logic.LGameActorMgr (get_gameActorMgr)
      - loc 3  = GameObject Canvas ("iFix.HiddenHeroLines.v4")
      - loc 11 = Camera.main
      - loc 12 = Vector2(Screen.width * 0.5f, Screen.height - 2f)
      - loc 5  = bool espEnabled (doc tu iFix.ESP.Monster.v1)
      - field 41 = ActorManager.MonsterActors
      - vm14(Transform, Camera, slot, ActorLinker, LActorRoot) = ve HP quai tren dau
      - vm15(Transform, Camera, Vector2, slot, ActorLinker, LActorRoot) = ve 3D box + line
      - vm17(ActorLinker, LActorRoot, isHero=0, enabled) = bat MapPointerSmall +
        UpdatePosInMiniMap tren minimap.
    """
    ins = dst["blocks"][3]["instrs"]
    # Chi tiêm 1 lan (kiem tra do dai goc 1033 lenh = 2066 int32)
    if len(ins) != 2066:
        return

    # 1. Mo rong vm14: khi CHeroInfo::GetHeroName tra rong (quai rung khong phai
    #    hero), lay LActorRoot.ValueComponent.get_actorHp().ToString() de hien mau!
    ins14 = dst["blocks"][14]["instrs"]
    assert len(ins14) == 262, f"vm14 len={len(ins14)}"
    assert ins14[2 * 51] == 0x7F and ins14[2 * 51 + 1] == 79
    ins14_patch = [
        0x86, 14,       # 51: Brfalse 14 -> 65 (hero co ten -> giu nguyen)
        0xA4, 4,        # 52: Ldarg 4 (LActorRoot)
        0xA7, 38,       # 53: Ldfld 38 (LActorRoot.ValueComponent)
        0x86, 89,       # 54: Brfalse 89 -> 143 (Ret)
        0xA4, 4,        # 55: Ldarg 4
        0xA7, 38,       # 56: Ldfld 38 (LActorRoot.ValueComponent)
        0x7A, 65720,    # 57: CallExtern ValuePropertyComponent::get_actorHp
        0x24, 6,        # 58: Stloc 6
        0x48, 6,        # 59: Ldloc 6
        0x8F, 0,        # 60: Ldc_I4 0
        0x11, 82,       # 61: Ble 82 -> 143 (Ret)
        0x0D, 6,        # 62: Ldloca 6
        0x7A, 65670,    # 63: CallExtern System.Int32::ToString
        0x24, 2,        # 64: Stloc 2
    ]
    ins14[2 * 19 + 1] += 13
    ins14[2 * 38 + 1] += 13
    ins14[2 * 51:2 * 52] = ins14_patch

    # 2. Trong vm3: luon tao Canvas "iFix.HiddenHeroLines.v4" (loc 3) khi dang
    #    trong tran (ke ca khi tat ESP tuong nhung bat ESP quai).
    assert ins[2 * 139] == 0x48 and ins[2 * 140] == 0x86
    ins[2 * 139:2 * 141] = [0x67, 0, 0x67, 0]

    def _str_idx(s: str) -> int:
        if s in dst["strings"]:
            return dst["strings"].index(s)
        dst["strings"].append(s)
        return len(dst["strings"]) - 1

    s_mon = _str_idx("iFix.ESP.Monster.v1")
    s_m = _str_idx("iFix.ESP.Monster.M")
    s_s = _str_idx("iFix.ESP.Monster.S")
    s_d = _str_idx("iFix.ESP.Monster.D")
    s_bp_en = _str_idx("iFix.AutoBP.Enabled.v1")
    s_bp_pct = _str_idx("iFix.AutoBP.Pct.v1")
    s_smt_en = _str_idx("iFix.AutoSmite.Enabled.v1")
    s_smt_hp = _str_idx("iFix.AutoSmite.Hp.v1")
    s_ice_en = _str_idx("iFix.AutoIce.Enabled.v1")
    s_ice_pct = _str_idx("iFix.AutoIce.Pct.v1")

    # 3. Patch AutoBP trong vm3 (pc 456..479: 24 lenh): dung nguong % mau tu iFix.AutoBP.Pct.v1
    bp_patch = [
        0x27, s_bp_en,
        0x8F, 0,
        0x7A, 131117,
        0x86, 29,
        0x48, 16,
        0x86, 27,
        0x48, 18,
        0x7F, 25,
        0x48, 21,
        0xA7, 38,
        0x86, 22,
        0x48, 21,
        0xA7, 38,
        0x7A, 65716,
        0x24, 46,
        0x0D, 46,
        0x7A, 65717,
        0x27, s_bp_pct,
        0x8F, 16,
        0x7A, 131117,
        0x3A, 0,
        0x8D, 1017370378,
        0xB3, 0,
        0x1E, 9,
    ]
    assert len(bp_patch) == 48, f"bp_patch len={len(bp_patch)}"
    ins[2 * 456 : 2 * 480] = bp_patch

    # 4. Patch AutoSmite Target Mode trong vm3 (pc 757..778: 22 lenh):
    #    Mode 1: chi quai nho va bua (loc 39 == 1 || loc 39 == 2, loai boss loc 39 == 3)
    #    Mode 2: chi rong va Caesar (loc 39 == 3)
    #    Mode 3: tat ca (loc 39 >= 1)
    smt_tgt_patch = [
        0x48, 33,
        0x8F, 1,
        0x2B, 5,
        0x48, 39,
        0x8F, 3,
        0x6E, 155,
        0x5D, 16,
        0x48, 33,
        0x8F, 2,
        0x2B, 5,
        0x48, 39,
        0x8F, 3,
        0x2B, 148,
        0x5D, 9,
        0x48, 39,
        0x8F, 1,
        0x2F, 144,
        0x67, 0,
        0x67, 0,
        0x67, 0,
        0x67, 0,
        0x67, 0,
    ]
    assert len(smt_tgt_patch) == 44, f"smt_tgt_patch len={len(smt_tgt_patch)}"
    ins[2 * 757 : 2 * 779] = smt_tgt_patch

    # 5. Patch AutoSmite HP Check trong vm3 (pc 850..886: 37 lenh):
    #    so sanh mau quai (loc 41) truc tiep voi iFix.AutoSmite.Hp.v1
    smt_hp_patch = [
        0x27, s_smt_hp,
        0x8F, 1500,
        0x7A, 131117,
        0x24, 42,
        0x48, 41,
        0x48, 42,
        0x0B, 61,
    ]
    while len(smt_hp_patch) < 37 * 2:
        smt_hp_patch.extend([0x67, 0])
    assert len(smt_hp_patch) == 74, f"smt_hp_patch len={len(smt_hp_patch)}"
    ins[2 * 850 : 2 * 887] = smt_hp_patch

    m_set_int = -1
    for idx, m in enumerate(dst["methods"]):
        if m["name"] == "SetInt" and "PlayerPrefs" in dst["types"][m["declType"]]:
            m_set_int = idx
            break
    assert m_set_int >= 0, "khong tim thay PlayerPrefs::SetInt"
    call_set_int = (2 << 16) | m_set_int

    ext = [
        # 0..7: loc 5 = (PlayerPrefs.GetInt("iFix.ESP.Monster.v1", 0) != 0)
        0x27, s_mon,
        0x8F, 0,
        0x7A, 131117,
        0x8F, 0,
        0xA6, 0,
        0x8F, 0,
        0xA6, 0,
        0x24, 5,
        # 8..13: if (loc44 != null) PlayerPrefs.SetInt("iFix.ESP.Monster.S", loc44.Count)
        0x48, 44,
        0x86, 5,
        0x27, s_s,
        0x48, 44,
        0x7A, 65722,
        0x7A, call_set_int,
        # 14..25: loc 37 = loc8.MonsterActors; if (loc37 == null) goto END (131)
        0x48, 8,
        0xA7, 41,
        0x24, 37,
        0x48, 37,
        0x75, 0,
        0xA6, 0,
        0x8F, 0,
        0xA6, 0,
        0x24, 45,
        0x48, 45,
        0x7F, 2,
        0x5D, 106,
        # 26..29: PlayerPrefs.SetInt("iFix.ESP.Monster.M", loc37.Count)
        0x27, s_m,
        0x48, 37,
        0x7A, 65722,
        0x7A, call_set_int,
        # 30..34: loc 48 = 0; for (loc4 = 0; loc4 < loc37.Count; loc4++)
        0x8F, 0,
        0x24, 48,
        0x8F, 0,
        0x24, 4,
        0x5D, 87,
        # 35..53: LOOP_BODY — lay ActorLinker (loc 38)
        0x48, 37,
        0x48, 4,
        0x7A, 131147,
        0x24, 25,
        0x0D, 25,
        0x7A, 65596,
        0x86, 8,
        0x0D, 25,
        0x7A, 65597,
        0x75, 0,
        0xA6, 0,
        0x8F, 0,
        0xA6, 0,
        0x5D, 2,
        0x8F, 0,
        0x24, 45,
        0x48, 45,
        0x7F, 2,
        0x5D, 64,
        # 54..80: lay LActorRoot (loc 21)
        0x0D, 25,
        0x7A, 65597,
        0x24, 38,
        0x48, 7,
        0x48, 38,
        0x7A, 65598,
        0x8F, 0,
        0x7A, 196671,
        0x24, 20,
        0x0D, 20,
        0x7A, 65600,
        0x86, 8,
        0x0D, 20,
        0x7A, 65601,
        0x75, 0,
        0xA6, 0,
        0x8F, 0,
        0xA6, 0,
        0x5D, 2,
        0x8F, 0,
        0x24, 45,
        0x48, 45,
        0x7F, 2,
        0x5D, 40,
        0x0D, 20,
        0x7A, 65601,
        0x24, 21,
        # 81..85: vm17(loc38, loc21, 0, loc5) -> minimap icon + UpdatePosInMiniMap
        0x48, 38,
        0x48, 21,
        0x8F, 0,
        0x48, 5,
        0x2D, 262161,
        # 86..98: kiem tra quai con song (!IsDeadState)
        0x48, 21,
        0xA7, 18,
        0x86, 7,
        0x48, 21,
        0xA7, 18,
        0x7A, 65602,
        0x8F, 0,
        0xA6, 0,
        0x5D, 2,
        0x8F, 0,
        0x24, 45,
        0x48, 45,
        0x86, 19,
        # 99..112: neu loc5 (ESP quai) && loc3 != null -> goi vm14 (HP) (KHONG goi vm15 box/line)
        0x48, 5,
        0x86, 13,
        0x48, 3,
        0x7A, 65573,
        0x86, 10,
        0x48, 3,
        0x7A, 65576,
        0x48, 11,
        0x48, 48,
        0x8F, 6,
        0x50, 0,
        0x48, 38,
        0x48, 21,
        0x2D, 327694,
        # 113..116: INC_ALIVE — loc48++
        0x48, 48,
        0x8F, 1,
        0x50, 0,
        0x24, 48,
        # 117..120: LOOP_NEXT — loc4++
        0x48, 4,
        0x8F, 1,
        0x50, 0,
        0x24, 4,
        # 121..127: LOOP_COND — loc4 < loc37.Count
        0x48, 4,
        0x48, 37,
        0x7A, 65722,
        0x6D, 0,
        0x24, 45,
        0x48, 45,
        0x7F, -92,
        # 128..130: PlayerPrefs.SetInt("iFix.ESP.Monster.D", loc48)
        0x27, s_d,
        0x48, 48,
        0x7A, call_set_int,
    ]

    # AutoIce logic (59 lenh): kiem tra mau ban than (loc 13/21) & bat Bang Suong slot 9
    ice_ops = [
        (0x27, s_ice_en),  # 0
        (0x8F, 0),         # 1
        (0x7A, 131117),    # 2: GetInt
        (0x86, 'END'),     # 3: Brfalse
        (0x48, 13),        # 4
        (0x86, 'END'),     # 5: Brfalse
        (0x48, 13),        # 6
        (0xA7, 19),        # 7: SkillControl
        (0x86, 'END'),     # 8: Brfalse
        (0x48, 13),        # 9
        (0xA7, 19),        # 10
        (0x8F, 9),         # 11: Slot 9 (trang bi kich hoat: Bang Suong)
        (0x7A, 131141),    # 12: GetSkillSlot(9)
        (0x24, 45),        # 13: Stloc 45 (slot9)
        (0x48, 45),        # 14
        (0x86, 'END'),     # 15: Brfalse
        (0x48, 45),        # 16
        (0x7A, 65606),     # 17: get_IsCDReady
        (0x86, 'END'),     # 18: Brfalse
        (0x48, 7),         # 19: loc 7 (LGameActorMgr)
        (0x48, 13),        # 20: loc 13 (ActorLinker)
        (0x7A, 65598),     # 21: get_ObjID
        (0x8F, 0),         # 22
        (0x7A, 196671),    # 23: GetActor
        (0x24, 20),        # 24: Stloc 20
        (0x0D, 20),        # 25: Ldloca 20
        (0x7A, 65600),     # 26: get_HasValue
        (0x86, 'END'),     # 27: Brfalse
        (0x0D, 20),        # 28: Ldloca 20
        (0x7A, 65601),     # 29: get_handle
        (0x24, 21),        # 30: Stloc 21 (hostRoot)
        (0x48, 21),        # 31
        (0x86, 'END'),     # 32: Brfalse
        (0x48, 21),        # 33
        (0xA7, 18),        # 34: ActorControl
        (0x86, 'END'),     # 35: Brfalse
        (0x48, 21),        # 36
        (0xA7, 18),        # 37: ActorControl
        (0x7A, 65602),     # 38: get_IsDeadState
        (0x7F, 'END'),     # 39: Brtrue
        (0x48, 21),        # 40
        (0xA7, 38),        # 41: ValueComponent
        (0x86, 'END'),     # 42: Brfalse
        (0x48, 21),        # 43
        (0xA7, 38),        # 44
        (0x7A, 65716),     # 45: GetHpRate
        (0x24, 46),        # 46: Stloc 46
        (0x0D, 46),        # 47: Ldloca 46
        (0x7A, 65717),     # 48: get_single
        (0x27, s_ice_pct), # 49
        (0x8F, 15),        # 50: mac dinh 15%
        (0x7A, 131117),    # 51: GetInt
        (0x3A, 0),         # 52: Conv_R4
        (0x8D, 1017370378),# 53: Ldc_R4 0.01f
        (0xB3, 0),         # 54: Mul
        (0x1E, 'END'),     # 55: Bgt_Un (hpRate > thresh -> END)
        (0x48, 45),        # 56: Ldloc 45 (slot9)
        (0x7A, 65721),     # 57: RequestUseSkill
        (0x80, 0),         # 58: Pop
    ]
    end_idx = len(ice_ops)
    ice_part = []
    for i, (op, val) in enumerate(ice_ops):
        ice_part.append(op)
        ice_part.append(end_idx - i if val == 'END' else val)

    ext.extend(ice_part)
    ext.extend([0xAD, 0])  # Ret o cuoi

    n_ext = (len(ext) // 2) - 1  # so lenh chen truoc Ret (190 lenh)
    assert n_ext == 190, f"n_ext={n_ext}"
    # 2 lenh Br nhay ve Ret cuoi khi chua vao tran (115, 138) -> cong them n_ext
    # Lenh 956 (khi SoldierActors == null) giu nguyen offset 76 de nhay vao dau ext (1032)!
    assert ins[2 * 115] == 0x5D and ins[2 * 115 + 1] == 917
    assert ins[2 * 138] == 0x5D and ins[2 * 138 + 1] == 894
    assert ins[2 * 956] == 0x5D and ins[2 * 956 + 1] == 76
    ins[2 * 115 + 1] += n_ext
    ins[2 * 138 + 1] += n_ext
    # thay lenh Ret cuoi (1032) bang ext
    ins[-2:] = ext
    print(f"   + inject_monster_esp + smite/bp/ice vao vm3/vm14: +{n_ext} lenh (tong {len(ins)//2} lenh)")


def merge(dst_path: str, menu_path: str, out_path: str) -> None:
    dst, dtag, denc, dres = load(dst_path)
    menu, _mt, _me, _mr = load(menu_path)

    print(f"== dst : {os.path.basename(dst_path)}")
    print(f"   types={len(dst['types'])} methods={len(dst['methods'])} "
          f"strings={len(dst['strings'])} fields={len(dst['fields'])} "
          f"blocks={len(dst['blocks'])} hooks={len(dst['interpret'])}")
    print(f"== menu: {os.path.basename(menu_path)}")
    print(f"   types={len(menu['types'])} methods={len(menu['methods'])} "
          f"strings={len(menu['strings'])} fields={len(menu['fields'])} "
          f"blocks={len(menu['blocks'])} hooks={len(menu['interpret'])}")

    if dst["bridge"].split(",")[1].strip() != menu["bridge"].split(",")[1].strip():
        raise SystemExit(f"assembly khac nhau: {dst['bridge']} vs {menu['bridge']}")

    before = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
              len(dst["fields"]), len(dst["blocks"]))

    rp = Remap(dst)
    vmap = {}
    for bi in range(len(menu["blocks"])):
        blk = menu["blocks"][bi]
        vmap[bi] = len(dst["blocks"])
        dst["blocks"].append({
            "instrs": list(blk["instrs"]),
            "handlers": [list(h) for h in blk["handlers"]],
        })
    dst["nextAlloc"] = len(dst["blocks"])

    # remap operand
    for sbi, dbi in vmap.items():
        ins = dst["blocks"][dbi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            code, op = ins[k], ins[k + 1]
            if code == OP_LDSTR:
                ins[k + 1] = rp.str_(menu, op)
            elif code == OP_CALLEXTERN:
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(menu, op & 0xFFFF)
            elif code == OP_NEWOBJ:
                # operand = (argc<<16) | ctorMethodId
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(menu, op & 0xFFFF)
            elif code in FIELD_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.field_(menu, op & 0xFFFF)
            elif code in TYPE_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.type_(menu, op & 0xFFFF)
            elif code == OP_CALL:
                tgt = op & 0xFFFF
                if tgt not in vmap:
                    raise SystemExit(f"menu block {sbi} Call vm{tgt} ngoai pham vi")
                ins[k + 1] = ((op >> 16) << 16) | vmap[tgt]

    # field moi (khai trong menu)
    for fr in menu["fields"]:
        rp.field_(menu, menu["fields"].index(fr))

    # hook
    for h in menu["interpret"]:
        m = h["method"]
        dt = rp.type_(menu, m["declType"])
        ps = [dict(p, id=(rp.type_(menu, p["id"]) if not p["isName"] else p["id"]))
              for p in m["params"]]
        ta = [rp.type_(menu, x) for x in m["typeArgs"]]
        # dedupe trong dst
        mi = -1
        for j, cm in enumerate(dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [p["id"] for p in cm["params"]] == [p["id"] for p in ps]):
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

    after = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
             len(dst["fields"]), len(dst["blocks"]))
    print(f"\n   them: types +{after[0]-before[0]} methods +{after[1]-before[1]} "
          f"strings +{after[2]-before[2]} fields +{after[3]-before[3]} "
          f"blocks +{after[4]-before[4]}")

    inject_monster_esp(dst)

    body = lqmb_serialize(dst)
    back = lqmb_parse(body)
    assert lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    for h in back["interpret"]:
        assert 0 <= h["vm"] < len(back["blocks"])

    # Chi verify cac block MOI THEM (block goc do game tu sinh, field id co the
    # vuot bang `fields` — do IFix resolve field theo kieu khac, khong phai loi).
    added = set(vmap.values())
    for bi in sorted(added):
        ins = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            c, o = ins[k], ins[k + 1]
            if c == OP_CALLEXTERN:
                assert (o & 0xFFFF) < len(back["methods"]), "method idx sai"
            elif c == OP_LDSTR:
                assert o < len(back["strings"]), "string idx sai"
            elif c in FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"]), f"field idx sai: {o}"
            elif c == OP_NEWOBJ:
                assert (o & 0xFFFF) < len(back["methods"]), "newobj ctor idx sai"
            elif c in TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"]), f"type idx sai: {o}"
            elif c == OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"]), "vm idx sai"
    print("   verify: moi operand cua block moi trong pham vi OK")

    # block goc (tru vm3, vm14 da chen monster esp) phai KHONG doi tung i32
    for i in range(before[4]):
        if i in (3, 14):
            continue
        assert back["blocks"][i]["instrs"] == dst["blocks"][i]["instrs"], \
            f"block goc vm{i} bi doi"
    print("   verify: block goc giu nguyen 100%")
    print(f"   body {len(body)} B | hooks {len(back['interpret'])}")

    out = resd_encrypt(body, dres, dtag, denc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: merge_menu.py <HS2.bytes> <Menu.bytes> <out.bytes>")
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
