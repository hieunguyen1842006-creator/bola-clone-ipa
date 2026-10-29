#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build_menu.py — build menu cam ung trong game (IFix patch) cho Lien Quan.

Pipeline (tai dung toolchain cua build_v4.py da chay duoc):
    csc  MenuPatch.cs     -> Patch.dll
    IFix -patch           -> STEP1.bytes  (opcode chuan new-2019)
    pack                  -> Menu.bytes   (opcode LQMB + wrapper ResD tag 0)

Chay: python tools/build_menu.py
"""
from __future__ import annotations

import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC_DIR = os.path.join(REPO, "_lqmenu")

ROOT = os.path.abspath(os.path.join(REPO, "..", ".."))
HARNESS = os.path.join(ROOT, "LQ IOS DEEPSEEEK HARNESS", "NEWW XỬ LÍ THEO DẠNG MỚI")
DUMP = os.path.join(ROOT, "LQ IOS DATA", "com.garena.game.kgvn_1.64.1.7_und3fined",
                    "com.garena.game.kgvn_1.64.1.7_und3fined", "DummyDll")

CSC = r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
IFIX = os.path.join(HARNESS, "ifix_bin", "IFix_noshuffle.exe")
IFIX_CORE = os.path.join(HARNESS, "ifix_bin", "IFix.Core.dll")
SRC = os.path.join(SRC_DIR, "MenuPatch.cs")
# Ten DLL PHAI trung assembly chua type bi hook: NucleusDrive.Logic.LFramework
# nam trong Project.Plugins_d -> HeroSkin_2. IFix lay assembly name tu ten DLL
# de ghi vao `bridge`, nen dat sai ten la game khong resolve duoc.
DLL_NAME = "Project.Plugins_d.dll"
DLL = os.path.join(SRC_DIR, DLL_NAME)
TABLE = os.path.join(ROOT, "LQ IOS DATA", "nvh_lq_hud", "opcode_table_lqmb_full.json")
OUT = os.path.join(SRC_DIR, "Menu.bytes")

WRAP_MAGIC = 0x4A22
TAG = 0

sys.path.insert(0, HARNESS)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# ten thu muc goc co ky tu Unicode -> import theo duong dan tuyet doi
import importlib.util as _ilu  # noqa: E402


def _load(name, path):
    spec = _ilu.spec_from_file_location(name, path)
    mod = _ilu.module_from_spec(spec)
    sys.modules[name] = mod        # dataclass can module co trong sys.modules
    spec.loader.exec_module(mod)
    return mod


ix = _load("ifixbytes", os.path.join(HARNESS, "ifixbytes.py"))


def s(v: str) -> bytes:
    b = v.encode("utf-8")
    return bytes([len(b)]) + b


def write_cfg(path: str) -> None:
    """Hook 1 method + khai field moi cho LFramework.

    QUAN TRONG: danh sach field PHAI khop CHINH XAC voi field khai trong
    MenuPatch.cs. Neu lech ten, IFix se coi field do la field CO SAN cua game
    -> tro vao index rac -> game doc bo nho sai -> TREO.
    Vi vay doc truc tiep tu source thay vi viet tay.
    """
    src = open(SRC, encoding="utf-8").read()
    # bat: public <type> __m<Ten>;
    raw = re.findall(r"public\s+([\w\.\<\>\[\]]+)\s+(__m\w+)\s*;", src)
    if not raw:
        raise SystemExit("khong doc duoc field __m* tu MenuPatch.cs")

    # IFix can TEN DAY DU cua kieu (khong nhan alias C# bool/float/int/object)
    ALIAS = {
        "bool": "System.Boolean",
        "float": "System.Single",
        "int": "System.Int32",
        "long": "System.Int64",
        "double": "System.Double",
        "string": "System.String",
        "object": "System.Object",
        "byte": "System.Byte",
        "uint": "System.UInt32",
        "ulong": "System.UInt64",
    }
    fields = [(ALIAS.get(ft, ft), name) for ft, name in raw]
    print(f"    cfg fields: {len(fields)}")
    for ft, name in fields:
        print(f"      {name}: {ft}")

    out = bytearray()
    # 1 nhom class
    out += struct.pack("<i", 1)
    out += s("NucleusDrive.Logic.LFramework")
    # CHI 1 method: get_frameSynchr.
    # KHONG khai method nao khac: khai trong danh sach patch -> IFix THAY THE
    # method that bang than ham trong file nay (get_IsGameLogicStarted tro
    # thanh `return false` -> menu khong hien). Khai trong newMethodInfo ->
    # IFix bien no thanh block VM `return null` thay vi method that cua game
    # (get_mainBattleLogic luon null). Vi vay KHONG goi method nao cua
    # LFramework trong patch, chi dung field _frameSynchr va Unity API.
    out += struct.pack("<i", 1)
    out += s("get_frameSynchr") + s("NucleusDrive.Logic.LFrameSynchr")
    out += struct.pack("<i", 0)                       # 0 param
    # newMethodInfo: rong — khong them method moi vao assembly
    out += struct.pack("<i", 0)
    # field moi
    out += struct.pack("<i", 1)                       # 1 class co field moi
    out += s("NucleusDrive.Logic.LFramework")
    out += struct.pack("<i", len(fields))
    for ft, name in fields:
        out += s(name) + s(ft)
    out += struct.pack("<i", 0)                       # newPropertiesInfo
    out += struct.pack("<i", 0)                       # newClassInfo
    open(path, "wb").write(bytes(out))


def run(cmd, cwd, label):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    print(f"--- {label} (exit {p.returncode})")
    for line in out.splitlines():
        low = line.lower()
        if "error" in low or "patched" in low:
            print("   ", line.strip()[:200])
    return p.returncode, out


def compile_dll() -> None:
    cmd = [CSC, "/nologo", "/target:library", "/out:" + DLL,
           "/r:" + IFIX_CORE,
           "/r:" + os.path.join(DUMP, "UnityEngine.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.CoreModule.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.UI.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.UIModule.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.TextRenderingModule.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.IMGUIModule.dll"),
           "/r:" + os.path.join(DUMP, "UnityEngine.InputLegacyModule.dll"),
           SRC]
    rc, out = run(cmd, SRC_DIR, "csc")
    if rc != 0:
        print(out[-6000:])
        raise SystemExit("compile failed")
    print("    dll:", os.path.getsize(DLL), "byte")


def ifix_patch() -> str:
    work = os.path.join(SRC_DIR, "ifix_work")
    os.makedirs(work, exist_ok=True)
    shutil.copy(IFIX_CORE, os.path.join(work, "IFix.Core.dll"))
    shutil.copy(DLL, os.path.join(work, DLL_NAME))
    cfg = os.path.join(work, "process_cfg")
    write_cfg(cfg)
    cmd = [IFIX, "-patch", "IFix.Core.dll", DLL_NAME,
           "unused", "process_cfg", "STEP1.bytes", ".", DUMP]
    rc, out = run(cmd, work, "IFix")
    prod = os.path.join(work, "STEP1.bytes")
    if not os.path.exists(prod):
        print(out[-6000:])
        raise SystemExit("IFix khong sinh STEP1")
    dst = os.path.join(SRC_DIR, "STEP1.bytes")
    shutil.copy(prod, dst)
    print("    step1:", os.path.getsize(dst), "byte")
    return dst


def pack(step1: str) -> None:
    ix.format_by_id("new-2019").field_has_ctor_flag = False
    pf = ix.parse_bytes(open(step1, "rb").read())
    table = ix.OpcodeMap.load(TABLE)
    rep = ix.remap_instructions(pf, table, to_std=False, strict=True)
    total = sum(len(b.instrs) for b in pf.blocks)
    print(f"    parse: {pf.format_id} hook {len(pf.interpret)} instr {total} "
          f"| remap {rep.changed}/{total} unmapped {sum(rep.unmapped.values())}")
    pf.magic = ix.MAGIC_LQMB
    pf.format_id = "lqmb"
    pf.pad = None

    def strip(t):
        for k in ("Version", "Culture", "PublicKeyToken"):
            t = re.sub(r",\s*" + k + r"=[^,\]]*", "", t)
        return t

    for attr in ("bridge", "wrapper", "idmap"):
        setattr(pf, attr, strip(getattr(pf, attr, "") or ""))

    data = ix.serialize(pf)
    if ix.serialize(ix.parse_bytes(data)) != data:
        raise SystemExit("roundtrip that bai")
    wrapped = struct.pack("<HHI", WRAP_MAGIC, TAG, len(data)) + data
    open(OUT, "wb").write(wrapped)
    print(f"    out: {OUT} {len(wrapped)} byte | hook {len(pf.interpret)} "
          f"| instr {sum(len(b.instrs) for b in pf.blocks)}")


if __name__ == "__main__":
    compile_dll()
    step = ifix_patch()
    pack(step)
