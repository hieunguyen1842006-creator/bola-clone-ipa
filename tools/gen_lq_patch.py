#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_lq_patch.py v2 — SINH PATCH IFix LQMB TU ZERO (khong can payload nguoi khac).

Tao file `HeroSkin_1.bytes` chua cac hook tu chon:
  --zoom 2.0      CameraSystem.GetZoomRate        -> get_ZoomRateFromAge() * zoom
  --privacy       CRoleInfoManager.IsPrivaceOn    -> return false  (ca 2 overload)
  --host          CPlayerProfile.get_IsHostProfile-> return true

Khong can dump IL goc: toan bo IL duoc viet tay bang opcode LQMB da neo, operand
tra theo TEN type/method trong file. IFix resolve bang reflection luc game chay.

Cau truc sinh ra doi chieu HeroSkin_4.bytes that (patch toi gian cua game):
  magic | bridge | types[] | next_alloc | blocks[] | methods[] | strings[] |
  fields[] | fsvm[] | anon[] | wrapper | idmap | interpret[] | newClasses[] | trailer

Dung:
  python gen_lq_patch.py -o out/HeroSkin_1.bytes --zoom 2.0 --privacy --host
  python gen_lq_patch.py -o out/x.bytes --zoom 3.0 --raw      # blob tran
  python gen_lq_patch.py -o out/x.bytes --zoom 2.0 --tag 0    # body plain
"""
from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

# --- nap transcription cua Swift (da verify byte-exact tren file that) -----
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)

lqmb_parse = _ns["lqmb_parse"]
lqmb_serialize = _ns["lqmb_serialize"]
resd_encrypt = _ns["resd_encrypt"]
resd_decrypt = _ns["resd_decrypt"]

MAGIC_LQMB = bytes.fromhex("d0db2c0e465fd41f")

# --- opcode LQMB (bang v2.2, da neo bang stack solver) --------------------
OP = {
    "BlockHeader": 0x92, "Ldarg": 0xA4, "CallExtern": 0x7A, "Call": 0x2D,
    "Ldstr": 0x27, "Ldc_R4": 0x8D, "Ldc_I4": 0x8F, "Mul": 0xB3, "Div": 0x54,
    "Stloc": 0x24, "Ldloc": 0x48, "Br": 0x5D, "Ret": 0xAD, "Pop": 0x80,
}
NAMES = {v: k for k, v in OP.items()}

# --- assembly qualified names (khop dump.cs cua LQ 1.64.1) ----------------
A_PROJECT = "Project_d, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
A_MSCORLIB = "mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
A_UNITY_CORE = "UnityEngine.CoreModule, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
# COM_USER_PRIVACY_MASK nam o AovTdr (namespace CSProtocol), KHONG phai Project_d
A_AOVTDR = "AovTdr, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"

T_BRIDGE = f"IFix.ILFixInterfaceBridge, {A_PROJECT}"
T_BOOL = f"System.Boolean, {A_MSCORLIB}"
T_SINGLE = f"System.Single, {A_MSCORLIB}"
T_INT32 = f"System.Int32, {A_MSCORLIB}"
T_UINT64 = f"System.UInt64, {A_MSCORLIB}"
T_STRING = f"System.String, {A_MSCORLIB}"
T_CAMSYS = f"CameraSystem, {A_PROJECT}"
T_PREFS = f"UnityEngine.PlayerPrefs, {A_UNITY_CORE}"
T_ROLEMGR = f"Assets.Scripts.GameSystem.CRoleInfoManager, {A_PROJECT}"
T_PRIVMASK = f"CSProtocol.COM_USER_PRIVACY_MASK, {A_AOVTDR}"
T_PROFILE = f"Assets.Scripts.GameSystem.CPlayerProfile, {A_PROJECT}"

WRAPPER = f"IFix.WrappersManagerImpl, {A_PROJECT}"
IDMAP = f", {A_PROJECT}"


def f32bits(x: float) -> int:
    u = struct.unpack("<I", struct.pack("<f", x))[0]
    return u - 0x100000000 if u > 0x7FFFFFFF else u


class Builder:
    """Gom type/method/string theo nhu cau, tra index on dinh."""

    def __init__(self) -> None:
        self.types: list[str] = [T_BRIDGE]
        self.methods: list[dict] = []
        self.strings: list[str] = []
        self.blocks: list[dict] = []
        self.hooks: list[dict] = []

    # -- bang tra cuu ------------------------------------------------------
    def type_id(self, full: str) -> int:
        try:
            return self.types.index(full)
        except ValueError:
            self.types.append(full)
            return len(self.types) - 1

    def str_id(self, s: str) -> int:
        try:
            return self.strings.index(s)
        except ValueError:
            self.strings.append(s)
            return len(self.strings) - 1

    def method_id(self, decl_type: int, name: str, params: list[int]) -> int:
        for i, m in enumerate(self.methods):
            if m["declType"] == decl_type and m["name"] == name and \
                    [p["id"] for p in m["params"]] == params:
                return i
        self.methods.append({
            "isGeneric": False, "declType": decl_type, "name": name,
            "typeArgs": [],
            "params": [{"isName": False, "id": p, "name": ""} for p in params],
        })
        return len(self.methods) - 1

    def method(self, type_full: str, name: str, param_types: list[str]) -> int:
        return self.method_id(self.type_id(type_full), name,
                              [self.type_id(t) for t in param_types])

    # -- them block + hook -------------------------------------------------
    def add_hook(self, type_full: str, name: str, param_types: list[str],
                 body_builder, locals_n: int = 1, maxstack: int = 3) -> int:
        """body_builder(self) -> list[(code, operand)] (chua co BlockHeader/Ret).

        `locals_n` / `maxstack` phai khop voi IL that su dung, neu khong IFix
        se cap phat sai frame (xem HeroSkin_4: locals=2 maxstack=2,
        vm28: locals=1 maxstack=3, vm29: locals=1 maxstack=1).
        """
        vm = len(self.blocks)
        mid = self.method(type_full, name, param_types)
        decl = self.types[self.methods[mid]["declType"]]

        body = body_builder(self)
        instrs = [OP["BlockHeader"], (locals_n << 16) | maxstack]
        for c, o in body:
            instrs += [c, o]
        # Ret: operand = so gia tri tra ve
        ret_n = 0 if decl.startswith("System.Void") else 1
        instrs += [OP["Ret"], ret_n]

        self.blocks.append({"instrs": instrs, "handlers": []})
        rec = self.methods[mid]
        self.hooks.append({
            "method": {
                "isGeneric": rec["isGeneric"],
                "declType": rec["declType"],
                "name": rec["name"],
                "typeArgs": list(rec["typeArgs"]),
                "params": [dict(p) for p in rec["params"]],
            },
            "vm": vm,
        })
        return vm

    def build(self) -> dict:
        return {
            "magic": MAGIC_LQMB,
            "bridge": T_BRIDGE,
            "types": list(self.types),
            "nextAlloc": len(self.blocks),
            "blocks": self.blocks,
            "methods": self.methods,
            "strings": self.strings,
            "fields": [],
            "fsvm": [],
            "anon": [],
            "wrapper": WRAPPER,
            "idmap": IDMAP,
            "pad": 0,
            "interpret": self.hooks,
            "newClasses": [],
            "trailer": b"",
        }


# ══════════════════════════════════════════════════════════════════════════
# Cac ham sinh IL
# ══════════════════════════════════════════════════════════════════════════

def il_zoom(b: Builder, zoom: float, key: str):
    """float GetZoomRate() => this.get_ZoomRateFromAge() * PlayerPrefs.GetFloat(key, zoom)"""
    m_age = b.method(T_CAMSYS, "get_ZoomRateFromAge", [])
    m_getf = b.method(T_PREFS, "GetFloat", [T_STRING, T_SINGLE])
    s_key = b.str_id(key)
    return lambda self_: [
        (OP["Ldarg"], 0),                                   # this
        (OP["CallExtern"], (1 << 16) | m_age),              # get_ZoomRateFromAge()
        (OP["Ldstr"], s_key),
        (OP["Ldc_R4"], f32bits(zoom)),
        (OP["CallExtern"], (2 << 16) | m_getf),             # GetFloat(key, zoom)
        (OP["Mul"], 0),
        (OP["Stloc"], 0),
        (OP["Ldloc"], 0),
    ]


def il_const_bool(b: Builder, value: bool):
    """bool XXX() => <value>  (khong dung tham so nao)."""
    return lambda self_: [
        (OP["Ldc_I4"], 1 if value else 0),
        (OP["Stloc"], 0),
        (OP["Ldloc"], 0),
    ]


def describe(pf: dict) -> None:
    def short(t: str) -> str:
        return t.split(",")[0]

    print("  bridge   =", short(pf["bridge"]))
    print("  wrapper  =", short(pf["wrapper"]))
    print("  types=%d methods=%d strings=%d blocks=%d hooks=%d"
          % (len(pf["types"]), len(pf["methods"]), len(pf["strings"]),
             len(pf["blocks"]), len(pf["interpret"])))
    print("  --- hooks ---")
    for h in pf["interpret"]:
        m = h["method"]
        ps = ", ".join(short(pf["types"][p["id"]]) for p in m["params"])
        n = len(pf["blocks"][h["vm"]]["instrs"]) // 2
        print("    vm%-3d %-42s (%s)  %d lenh"
              % (h["vm"], short(pf["types"][m["declType"]]) + "::" + m["name"], ps, n))
    print("  --- IL ---")
    for bi, blk in enumerate(pf["blocks"]):
        ins = blk["instrs"]
        print("    block %d (%d lenh):" % (bi, len(ins) // 2))
        for i in range(0, len(ins), 2):
            c, o = ins[i], ins[i + 1]
            nm = NAMES.get(c, "0x%02X" % c)
            extra = ""
            if c == OP["CallExtern"]:
                mi, ac = o & 0xFFFF, (o >> 16) & 0xFFFF
                m = pf["methods"][mi]
                extra = "argc=%d %s::%s" % (ac, short(pf["types"][m["declType"]]), m["name"])
            elif c == OP["Ldstr"]:
                extra = "%r" % pf["strings"][o]
            elif c == OP["Ldc_R4"]:
                extra = "float %r" % struct.unpack("<f", struct.pack("<I", o & 0xFFFFFFFF))[0]
            elif c == OP["Ldc_I4"]:
                extra = str(o)
            elif c in (OP["Ldarg"], OP["Stloc"], OP["Ldloc"]):
                extra = "slot %d" % o
            elif c == OP["BlockHeader"]:
                extra = "locals=%d maxstack=%d" % ((o >> 16) & 0xFFFF, o & 0xFFFF)
            elif c == OP["Ret"]:
                extra = "n=%d" % o
            print("      %2d  0x%02X %-12s %-14s %s" % (i // 2, c, nm, o, extra))


def verify(pf: dict, blob: bytes) -> None:
    back = lqmb_parse(blob)
    assert lqmb_serialize(back) == blob, "round-trip KHONG byte-exact"
    assert back["nextAlloc"] == len(back["blocks"]), "next_alloc lech"
    assert len(back["blocks"]) == len(pf["blocks"]), "so block lech"
    assert len(back["interpret"]) == len(pf["interpret"]), "so hook lech"
    for a, b in zip(pf["blocks"], back["blocks"]):
        assert a["instrs"] == b["instrs"], "IL bi doi sau round-trip"
    for a, b in zip(pf["interpret"], back["interpret"]):
        assert a["vm"] == b["vm"], "vm id lech"
        assert a["method"]["name"] == b["method"]["name"], "ten hook lech"
    assert back["strings"] == pf["strings"], "strings lech"
    # moi hook phai tro toi block ton tai
    for h in back["interpret"]:
        assert 0 <= h["vm"] < len(back["blocks"]), "vm ngoai pham vi"
    # moi operand method/type phai nam trong bang
    for blk in back["blocks"]:
        ins = blk["instrs"]
        for i in range(0, len(ins), 2):
            c, o = ins[i], ins[i + 1]
            if c == OP["CallExtern"] or c == OP["Call"]:
                assert (o & 0xFFFF) < len(back["methods"]), "method idx ngoai pham vi"
            elif c == OP["Ldstr"]:
                assert o < len(back["strings"]), "string idx ngoai pham vi"
    print("[ok ] round-trip byte-exact, hook/operand deu hop le")


def main() -> int:
    ap = argparse.ArgumentParser(description="Sinh patch IFix LQMB tu zero")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--zoom", type=float, default=0.0, help="0 = khong hook zoom")
    ap.add_argument("--key", default="iFix.Camera.Zoom.v1")
    ap.add_argument("--privacy", action="store_true")
    ap.add_argument("--host", action="store_true")
    ap.add_argument("--tag", type=int, default=103)
    ap.add_argument("--raw", action="store_true", help="blob LQMB tran, khong boc ResD")
    ap.add_argument("--no-encrypt", action="store_true", help="boc ResD nhung body plain")
    a = ap.parse_args()

    if a.zoom <= 0 and not a.privacy and not a.host:
        print("[!] khong co tinh nang nao duoc chon (--zoom/--privacy/--host)")
        return 2

    b = Builder()

    if a.zoom > 0:
        # stack dinh: this(1) -> float(1) -> key(1)+zoom(1)=2 -> mul=1 -> 1
        b.add_hook(T_CAMSYS, "GetZoomRate", [], il_zoom(b, a.zoom, a.key),
                   locals_n=1, maxstack=3)
    if a.privacy:
        # 2 overload: (ulong, COM_USER_PRIVACY_MASK) va (ulong, int)
        b.add_hook(T_ROLEMGR, "IsPrivaceOn", [T_UINT64, T_PRIVMASK],
                   il_const_bool(b, False), locals_n=1, maxstack=1)
        b.add_hook(T_ROLEMGR, "IsPrivaceOn", [T_UINT64, T_INT32],
                   il_const_bool(b, False), locals_n=1, maxstack=1)
    if a.host:
        b.add_hook(T_PROFILE, "get_IsHostProfile", [],
                   il_const_bool(b, True), locals_n=1, maxstack=1)

    pf = b.build()

    feats = []
    if a.zoom > 0:
        feats.append("zoom=%s" % a.zoom)
    if a.privacy:
        feats.append("privacy=off")
    if a.host:
        feats.append("host=fake")
    print("[gen] patch tu zero: %s" % ", ".join(feats))
    describe(pf)

    blob = lqmb_serialize(pf)
    print("\n[gen] blob LQMB %d byte | sha256 %s"
          % (len(blob), hashlib.sha256(blob).hexdigest()[:32]))
    verify(pf, blob)

    if a.raw:
        out = blob
    else:
        res_name = os.path.splitext(os.path.basename(a.out))[0]
        out = resd_encrypt(blob, res_name, a.tag, not a.no_encrypt)
        tag2, olen2, plain2, enc2 = resd_decrypt(out, res_name)
        assert plain2 == blob and tag2 == a.tag, "container round-trip loi"
        print("[ok ] ResD tag=%d %s, decrypt lai khop"
              % (tag2, "AES" if enc2 else "plain"))

    d = os.path.dirname(os.path.abspath(a.out))
    if d:
        os.makedirs(d, exist_ok=True)
    open(a.out, "wb").write(out)
    print("[gen] -> %s : %d byte | sha256 %s"
          % (a.out, len(out), hashlib.sha256(out).hexdigest()[:32]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
