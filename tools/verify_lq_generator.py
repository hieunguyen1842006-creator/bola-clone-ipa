#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_lq_generator.py — transcribe Y NGUYEN LqGenerator.swift sang Python va
so sanh byte-by-byte voi `gen_lq_patch.py`.

Muc dich: dam bao ban Swift va ban Python sinh ra CUNG mot patch (neu khac thi
CI se fail o buoc BolaSelfTest, hoac te hon la game doc sai).

Chay: python tools/verify_lq_generator.py
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))

# --- nap transcription cua Swift (AES/ResD/Lqmb) --------------------------
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)

lqmb_parse = _ns["lqmb_parse"]
lqmb_serialize = _ns["lqmb_serialize"]
resd_encrypt = _ns["resd_encrypt"]

MAGIC_LQMB = bytes.fromhex("d0db2c0e465fd41f")

# ── transcription cua LqGenerator.swift ───────────────────────────────────
OP_BLOCKHEADER = 0x92
OP_LDARG = 0xA4
OP_CALLEXTERN = 0x7A
OP_LDSTR = 0x27
OP_LDCR4 = 0x8D
OP_LDCI4 = 0x8F
OP_MUL = 0xB3
OP_STLOC = 0x24
OP_LDLOC = 0x48
OP_RET = 0xAD

ASM_PROJECT = "Project_d, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
ASM_MSCORLIB = "mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
ASM_UNITY_CORE = "UnityEngine.CoreModule, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
# COM_USER_PRIVACY_MASK nam o AovTdr (namespace CSProtocol)
ASM_AOVTDR = "AovTdr, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"

T_BRIDGE = f"IFix.ILFixInterfaceBridge, {ASM_PROJECT}"
T_BOOL = f"System.Boolean, {ASM_MSCORLIB}"
T_SINGLE = f"System.Single, {ASM_MSCORLIB}"
T_INT32 = f"System.Int32, {ASM_MSCORLIB}"
T_UINT64 = f"System.UInt64, {ASM_MSCORLIB}"
T_STRING = f"System.String, {ASM_MSCORLIB}"
T_CAMSYS = f"CameraSystem, {ASM_PROJECT}"
T_PREFS = f"UnityEngine.PlayerPrefs, {ASM_UNITY_CORE}"
T_ROLEMGR = f"Assets.Scripts.GameSystem.CRoleInfoManager, {ASM_PROJECT}"
T_PRIVMASK = f"CSProtocol.COM_USER_PRIVACY_MASK, {ASM_AOVTDR}"
T_PROFILE = f"Assets.Scripts.GameSystem.CPlayerProfile, {ASM_PROJECT}"
WRAPPER_IMPL = f"IFix.WrappersManagerImpl, {ASM_PROJECT}"
IDMAP_IMPL = f", {ASM_PROJECT}"
ZOOM_PREF_KEY = "iFix.Camera.Zoom.v1"


def f32bits(x: float) -> int:
    u = struct.unpack("<I", struct.pack("<f", x))[0]
    return u - 0x100000000 if u > 0x7FFFFFFF else u


class Builder:
    """Ban Swift doc lap: dung list rieng, tra index on dinh."""

    def __init__(self):
        self.types = [T_BRIDGE]
        self.methods = []
        self.strings = []
        self.blocks = []
        self.hooks = []

    def type_id(self, full):
        for i, t in enumerate(self.types):
            if t == full:
                return i
        self.types.append(full)
        return len(self.types) - 1

    def str_id(self, s):
        for i, v in enumerate(self.strings):
            if v == s:
                return i
        self.strings.append(s)
        return len(self.strings) - 1

    def method_id(self, decl_type, name, params):
        for i, m in enumerate(self.methods):
            if m["declType"] != decl_type or m["name"] != name:
                continue
            if len(m["params"]) != len(params):
                continue
            if all(a["id"] == b for a, b in zip(m["params"], params)):
                return i
        self.methods.append({
            "isGeneric": False, "declType": decl_type, "name": name,
            "typeArgs": [],
            "params": [{"isName": False, "id": p, "name": ""} for p in params],
        })
        return len(self.methods) - 1

    def method(self, type_full, name, param_types):
        return self.method_id(self.type_id(type_full), name,
                              [self.type_id(t) for t in param_types])

    def add_hook(self, type_full, name, param_types, locals_n, maxstack, body):
        vm = len(self.blocks)
        # transcription cua LqGenerator.addHook: deps trong body dang ky TRUOC
        body_ins = body(self)
        mid = self.method(type_full, name, param_types)
        decl = self.types[self.methods[mid]["declType"]]

        instrs = [OP_BLOCKHEADER, (locals_n << 16) | maxstack]
        for c, o in body_ins:
            instrs += [c, o]
        ret_n = 0 if decl.startswith("System.Void") else 1
        instrs += [OP_RET, ret_n]

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

    def build(self):
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
            "wrapper": WRAPPER_IMPL,
            "idmap": IDMAP_IMPL,
            "pad": 0,
            "interpret": self.hooks,
            "newClasses": [],
            "trailer": b"",
        }


def make_patch(zoom=None, privacy_off=None, fake_host=None):
    """Transcription cua LqGenerator.makePatch."""
    has_zoom = zoom is not None and zoom > 0
    if not has_zoom and privacy_off is None and fake_host is None:
        return None
    b = Builder()

    if has_zoom:
        def body_zoom(bb):
            m_age = bb.method(T_CAMSYS, "get_ZoomRateFromAge", [])
            m_getf = bb.method(T_PREFS, "GetFloat", [T_STRING, T_SINGLE])
            s_key = bb.str_id(ZOOM_PREF_KEY)
            return [
                (OP_LDARG, 0),
                (OP_CALLEXTERN, (1 << 16) | m_age),
                (OP_LDSTR, s_key),
                (OP_LDCR4, f32bits(zoom)),
                (OP_CALLEXTERN, (2 << 16) | m_getf),
                (OP_MUL, 0),
                (OP_STLOC, 0),
                (OP_LDLOC, 0),
            ]
        b.add_hook(T_CAMSYS, "GetZoomRate", [], 1, 3, body_zoom)

    if privacy_off:
        for mask in (T_PRIVMASK, T_INT32):
            def body_priv(bb):
                return [(OP_LDCI4, 0), (OP_STLOC, 0), (OP_LDLOC, 0)]
            b.add_hook(T_ROLEMGR, "IsPrivaceOn", [T_UINT64, mask], 1, 1, body_priv)

    if fake_host is not None:
        def body_host(bb):
            return [(OP_LDCI4, 1 if fake_host else 0), (OP_STLOC, 0), (OP_LDLOC, 0)]
        b.add_hook(T_PROFILE, "get_IsHostProfile", [], 1, 1, body_host)

    return b.build()


def run_python_gen(args, out_path):
    """Chay gen_lq_patch.py that de lay output tham chieu."""
    cmd = [sys.executable, os.path.join(ROOT, "gen_lq_patch.py"), "-o", out_path] + args
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit("gen_lq_patch.py that bai")
    return open(out_path, "rb").read()


def check(name, cond, extra=""):
    global failures
    print(("  OK   " if cond else "  FAIL ") + name + (("  " + extra) if extra else ""))
    if not cond:
        failures += 1


failures = 0

print("=== LqGenerator Swift vs gen_lq_patch.py Python ===")
cases = [
    ("zoom=2.0", ["--zoom", "2.0"], dict(zoom=2.0)),
    ("zoom=3.5", ["--zoom", "3.5"], dict(zoom=3.5)),
    ("privacy", ["--privacy"], dict(privacy_off=True)),
    ("host", ["--host"], dict(fake_host=True)),
    ("all", ["--zoom", "2.0", "--privacy", "--host"],
     dict(zoom=2.0, privacy_off=True, fake_host=True)),
]

tmpdir = tempfile.mkdtemp()
for label, args, kwargs in cases:
    ref_path = os.path.join(tmpdir, "ref_%s.bytes" % label.replace("=", "_").replace(".", ""))
    ref = run_python_gen(args, ref_path)

    mine = make_patch(**kwargs)
    if mine is None:
        check(label + ": ca hai deu nil/rong", False)
        continue
    my_blob = lqmb_serialize(mine)
    my_container = resd_encrypt(my_blob, "HeroSkin_1", 103, True)

    # ref la container ResD -> giai ma bang dung resName cua no (ten file output)
    ref_name = os.path.splitext(os.path.basename(ref_path))[0]
    _t, _ol, ref_blob, _e = _ns["resd_decrypt"](ref, ref_name)
    same_blob = my_blob == ref_blob

    check("%-10s blob LQMB giong het (%d B)" % (label, len(my_blob)), same_blob,
          "" if same_blob else "ref=%d mine=%d" % (len(ref_blob), len(my_blob)))
    if not same_blob:
        n = min(len(ref_blob), len(my_blob))
        for i in range(n):
            if ref_blob[i] != my_blob[i]:
                print("         lech @0x%X: ref=%02x mine=%02x"
                      % (i, ref_blob[i], my_blob[i]))
                print("         ref :", ref_blob[max(0, i - 20):i + 40].hex(" "))
                print("         mine:", my_blob[max(0, i - 20):i + 40].hex(" "))
                print("         ref  ascii:", ref_blob[max(0, i - 20):i + 40])
                print("         mine ascii:", my_blob[max(0, i - 20):i + 40])
                break

print()
print("=== Cau truc patch sinh ra ===")
for label, args, kwargs in cases:
    pf = make_patch(**kwargs)
    if pf is None:
        continue
    ok = True
    blob = lqmb_serialize(pf)
    back = lqmb_parse(blob)
    if lqmb_serialize(back) != blob:
        ok = False
    if back["nextAlloc"] != len(back["blocks"]):
        ok = False
    for h in back["interpret"]:
        if not (0 <= h["vm"] < len(back["blocks"])):
            ok = False
    names = [back["types"][h["method"]["declType"]].split(",")[0] + "::" + h["method"]["name"]
             for h in back["interpret"]]
    check("%-10s verify OK | %s" % (label, ", ".join(names)), ok)

print()
print("RESULT:", "PASS" if failures == 0 else "FAIL (%d)" % failures)
sys.exit(0 if failures == 0 else 1)
