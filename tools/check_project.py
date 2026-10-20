#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_project.py — kiểm tra tĩnh cả project clone (chạy được trên Windows, không cần Xcode):

  1. project.pbxproj : id duy nhất, mọi fileRef trỏ tới file CÓ THẬT,
                       mọi .swift trong Sources có mặt ở build phase Sources,
                       phase Resources trỏ đúng asset/wav
  2. Info.plist      : parse được + các key bắt buộc (NVHOfflineMaxDays, LSApplicationQueriesSchemes…)
  3. Assets.xcassets : JSON hợp lệ, app icon có file 1024
  4. nvh_silence.wav: header WAV hợp lệ
  5. project.yml     : mọi path khai báo đều tồn tại
  6. nguồn Swift     : cân bằng {}, (), [] ngoài chuỗi/comment (bắt lỗi gõ tay)

Dùng: python tools/check_project.py
"""
from __future__ import annotations

import json
import hashlib
import os
import plistlib
import re
import struct
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAULT_KEY = hashlib.sha256(b"NVH-MOD-2026:vault:v1").digest()


def vault_decode(blob: bytes):
    """Giải mã blob NVHV1; trả None nếu sai format/hash."""
    if not blob.startswith(b"NVHV1") or len(blob) < 41:
        return None
    n = int.from_bytes(blob[5:9], "little")
    digest = blob[9:41]
    ct = blob[41:]
    ks = b"".join(hashlib.sha256(VAULT_KEY + i.to_bytes(4, "little")).digest()
                  for i in range((n + 31) // 32))
    pt = bytes(a ^ b for a, b in zip(ct[:n], ks[:n]))
    return pt if hashlib.sha256(pt).digest() == digest else None
fails: list[str] = []
warns: list[str] = []
checks = 0
BS = chr(92)


def check(name: str, ok: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if ok:
        print("  [ok]   %s" % name)
    else:
        fails.append(name)
        print("  [FAIL] %s %s" % (name, detail))


def warn(name: str, detail: str = "") -> None:
    warns.append(name)
    print("  [warn] %s %s" % (name, detail))


print("== 1. project.pbxproj ==")
pbx_path = os.path.join(ROOT, "BolaClone.xcodeproj", "project.pbxproj")
check("pbxproj tồn tại", os.path.isfile(pbx_path))
pbx = open(pbx_path, encoding="utf-8").read()

ids = re.findall(r"^\t\t([0-9A-F]{24}) ", pbx, re.M)
check("object id duy nhất (%d object)" % len(ids), len(ids) == len(set(ids)),
      "trùng: %d" % (len(ids) - len(set(ids))))

# fileRef -> path
ref_by_id = {}
for line in pbx.splitlines():
    if "isa = PBXFileReference;" not in line:
        continue
    m = re.search(r"([0-9A-F]{24}) /\* ([^*]+) \*/", line)
    mp = re.search(r"path = ([^;]+);", line)
    if m and mp:
        ref_by_id[m.group(1)] = (m.group(2).strip(), mp.group(1).strip().strip('"'))

# tim group path de ghep duong dan day du
group_of_id = {}
for m in re.finditer(r"([0-9A-F]{24}) /\* ([^*]+) \*/ = \{\s*isa = PBXGroup;\s*children = \(([^)]*)\);\s*path = ([^;]+);", pbx):
    kids = re.findall(r"([0-9A-F]{24})", m.group(3))
    for k in kids:
        group_of_id[k] = m.group(4).strip().strip('"')

swift_on_disk = []
for base in ("Sources", "Vendor3105"):
    for root, _d, files in os.walk(os.path.join(ROOT, base)):
        for f in files:
            if f.endswith(".swift"):
                swift_on_disk.append(os.path.relpath(os.path.join(root, f), ROOT).replace(BS, "/"))
swift_on_disk.sort()

missing = []
for oid, (name, path) in ref_by_id.items():
    if not path.endswith(".swift"):
        continue
    sub = group_of_id.get(oid, "")
    if sub == "Vendor3105":
        cand = os.path.join(ROOT, "Vendor3105", path)
        if not os.path.isfile(cand):
            missing.append("Vendor3105/%s" % path)
        continue
    cand = os.path.join(ROOT, "Sources", sub, path)
    if not os.path.isfile(cand):
        # thu truc tiep Sources/
        cand2 = os.path.join(ROOT, "Sources", path)
        if not os.path.isfile(cand2):
            missing.append("%s/%s" % (sub, path))
check("mọi fileRef .swift trỏ tới file thật", not missing, str(missing))

src_phase = re.search(r"isa = PBXSourcesBuildPhase;.*?files = \(([^)]*)\);", pbx, re.S)
src_ids = set(re.findall(r"([0-9A-F]{24}) /\*", src_phase.group(1))) if src_phase else set()
buildfile_to_ref = dict(re.findall(r"([0-9A-F]{24}) /\* [^*]+ \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", pbx))
in_phase = {ref_by_id.get(buildfile_to_ref.get(i), ("?", "?"))[1] for i in src_ids}
check("Sources phase có đủ %d file .swift" % len(swift_on_disk),
      set(os.path.basename(p) for p in swift_on_disk) <= in_phase,
      "thiếu: %s" % (set(os.path.basename(p) for p in swift_on_disk) - in_phase))

res_phase = re.search(r"isa = PBXResourcesBuildPhase;.*?files = \(([^)]*)\);", pbx, re.S)
res_ids = set(re.findall(r"([0-9A-F]{24}) /\*", res_phase.group(1))) if res_phase else set()
res_names = {ref_by_id.get(buildfile_to_ref.get(i), ("?", "?"))[1] for i in res_ids}
check("Resources phase có Assets.xcassets + wav + 5 vault",
      {"Assets.xcassets", "nvh_silence.wav", "NVHMenu.vault", "NeutralPatch.vault",
       "LQHud.vault", "LQUnlock.vault", "NVHLQ.vault"} <= res_names,
      str(res_names))
check("target/project có PBXProject + PBXNativeTarget",
      "isa = PBXProject;" in pbx and "isa = PBXNativeTarget;" in pbx)
check("INFOPLIST_FILE = Resources/Info.plist", "INFOPLIST_FILE = Resources/Info.plist;" in pbx)
check("bundle id + deployment target",
      "PRODUCT_BUNDLE_IDENTIFIER = com.apple.mobile.MobileHouseArrest;" in pbx
      and "IPHONEOS_DEPLOYMENT_TARGET = 16.0;" in pbx)
check("app icon được actool biên dịch (ASSETCATALOG_COMPILER_APPICON_NAME)",
      "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" in pbx)

print("\n== 2. Info.plist ==")
info_path = os.path.join(ROOT, "Resources", "Info.plist")
pl = plistlib.load(open(info_path, "rb"))
for k in ("NVHOfflineMaxDays", "NVHProduct", "NVHTelegram", "NVHAuthor",
          "LSApplicationQueriesSchemes",
          "UIBackgroundModes", "UIFileSharingEnabled", "CFBundleShortVersionString"):
    check("key %s" % k, k in pl)
check("offline days == 3", pl.get("NVHOfflineMaxDays") == 3)
check("query schemes gồm freefire*",
      set(pl.get("LSApplicationQueriesSchemes", [])) >= {"freefire", "freefiremax"})
check("background mode audio", "audio" in pl.get("UIBackgroundModes", []))
check("CFBundleShortVersionString == 1.0.0", pl.get("CFBundleShortVersionString") == "1.0.0")

print("\n== 3. Assets.xcassets ==")
cat = os.path.join(ROOT, "Resources", "Assets.xcassets")
check("Assets.xcassets/Contents.json", os.path.isfile(os.path.join(cat, "Contents.json")))
appicon = json.load(open(os.path.join(cat, "AppIcon.appiconset", "Contents.json"), encoding="utf-8"))
icon_file = os.path.join(cat, "AppIcon.appiconset", appicon["images"][0]["filename"])
check("app icon 1024 tồn tại (%s)" % os.path.basename(icon_file), os.path.isfile(icon_file))
with open(icon_file, "rb") as fh:
    head = fh.read(8)
check("app icon là PNG", head[:8] == b"\x89PNG\r\n\x1a\n")

print("\n== 4. nvh_silence.wav ==")
wav = os.path.join(ROOT, "Resources", "nvh_silence.wav")
with wave.open(wav, "rb") as wf:
    check("wav hợp lệ (%d Hz, %d kênh, %d frames)" % (wf.getframerate(), wf.getnchannels(), wf.getnframes()),
          wf.getnchannels() == 1 and wf.getframerate() == 8000 and wf.getnframes() == 8000)

print("\n== 5. project.yml ==")
yml = open(os.path.join(ROOT, "project.yml"), encoding="utf-8").read()
for p in ("Sources", "Resources", "Resources/Info.plist", "Resources/Assets.xcassets",
          "Resources/nvh_silence.wav", "Resources/NVHMenu.vault",
          "Resources/NeutralPatch.vault", "Resources/LQHud.vault",
          "Resources/LQUnlock.vault", "Resources/NVHLQ.vault"):
    check("project.yml path %s tồn tại" % p, os.path.exists(os.path.join(ROOT, p)))
check("project.yml có target BolaClone", "BolaClone:" in yml)

print("\n== 5b. Patch đóng gói ==")
patch_path = os.path.join(ROOT, "Resources", "NVHMenu.bytes")
pdata = open(patch_path, "rb").read() if os.path.isfile(patch_path) else b""
if pdata:
    check("patch có magic IFix cba2b40db219a366",
          pdata[:8] == bytes.fromhex("cba2b40db219a366"), pdata[:8].hex())
    check("patch > 10 KB (%d B)" % len(pdata), len(pdata) > 10_000)
    check("patch không phải rỗng/placeholder", len(set(pdata)) > 32)
    check("patch đã repack — không còn bolaminhduc/|BOLATK1|",
          b"bolaminhduc" not in pdata.lower() and b"|BOLATK1|" not in pdata)
    check("patch dùng marker mới |NVHTK01|", b"|NVHTK01|" in pdata)
    check("patch trỏ nvhcfg.bin/.nvhtok",
          b"/nvhcfg.bin" in pdata and b"/.nvhtok" in pdata)

neutral_path = os.path.join(ROOT, "Resources", "NeutralPatch.bytes")
if os.path.isfile(neutral_path):
    ndata = open(neutral_path, "rb").read()
    check("neutral seed có magic IFix",
          ndata[:8] == bytes.fromhex("cba2b40db219a366"), ndata[:8].hex())
    check("neutral seed nhỏ hơn patch thật (%d < %d B)" % (len(ndata), len(pdata)),
          len(ndata) < len(pdata))

# Vault: bundle chỉ mang blob mã hoá, không mang patch plaintext.
vault_path = os.path.join(ROOT, "Resources", "NVHMenu.vault")
if os.path.isfile(vault_path):
    vdata = open(vault_path, "rb").read()
    check("vault chính có magic NVHV1", vdata[:5] == b"NVHV1")
    check("vault chính không chứa magic IFix", b"\xcb\xa2\xb4\x0d" not in vdata[:64])
    check("vault chính không lộ chữ bolaminhduc", b"bolaminhduc" not in vdata.lower())
    check("vault chính giải mã ra đúng NVHMenu.bytes", vault_decode(vdata) == pdata)

neutral_vault = os.path.join(ROOT, "Resources", "NeutralPatch.vault")
if os.path.isfile(neutral_vault):
    nv = open(neutral_vault, "rb").read()
    check("vault neutral có magic NVHV1", nv[:5] == b"NVHV1")
    check("vault neutral không chứa magic IFix", b"\xcb\xa2\xb4\x0d" not in nv[:64])
    check("vault neutral giải mã ra đúng NeutralPatch.bytes",
          vault_decode(nv) == ndata)

LQ_MAGIC = bytes.fromhex("d0db2c0e465fd41f")


def lq2_names(raw):
    """Ten file trong bundle LQ2 ('LQ2\\0' + u32 so file + [u8 len][ten][u32 size][data]...)."""
    if len(raw) < 9 or raw[:4] != b"LQ2\x00":
        return None
    n = int.from_bytes(raw[4:8], "little")
    if not 0 < n <= 8:
        return None
    o, out = 8, []
    for _ in range(n):
        if o >= len(raw):
            return None
        ln = raw[o]
        o += 1
        if not 0 < ln <= 64 or o + ln + 4 > len(raw):
            return None
        out.append(raw[o:o + ln].decode("utf-8", "replace"))
        o += ln
        sz = int.from_bytes(raw[o:o + 4], "little")
        o += 4
        if not 0 < sz <= len(raw) - o:
            return None
        o += sz
    return out


def lq_kind(raw):
    if lq2_names(raw) is not None:
        return "bundle LQ2"
    if raw[:2] == b"\x22\x4a" and raw[8:16] == LQ_MAGIC:
        return "LQMB 0x4A22"
    return None


# Liên Quân: payload LQMB hoặc bundle LQ2, chỉ nằm trong vault.
for name in ("LQHud", "LQUnlock"):
    src = os.path.join(ROOT, "Resources", name + ".bytes")
    vp = os.path.join(ROOT, "Resources", name + ".vault")
    if os.path.isfile(src):
        raw = open(src, "rb").read()
        check("%s là payload LQ (%s)" % (name, lq_kind(raw) or "?"),
              lq_kind(raw) is not None, raw[:16].hex())
        min_size = 100_000 if name == "LQHud" else 900
        check("%s > %d B (%d B)" % (name, min_size, len(raw)), len(raw) > min_size)
    if os.path.isfile(vp):
        blob = open(vp, "rb").read()
        check("%s.vault có magic NVHV1" % name, blob[:5] == b"NVHV1")
        check("%s.vault không lộ magic LQ" % name,
              LQ_MAGIC not in blob[:64] and b"LQ2\x00" not in blob[:64])
        check("%s.vault giải mã đúng payload" % name,
              os.path.isfile(src) and vault_decode(blob) == open(src, "rb").read())

# NVH Beta: payload nguyên gói vendor (bundle LQ2: HeroSkin_1 + HeroSkin_2).
src = os.path.join(ROOT, "Resources", "NVHLQ.bytes")
vp = os.path.join(ROOT, "Resources", "NVHLQ.vault")
if os.path.isfile(src):
    raw = open(src, "rb").read()
    names = lq2_names(raw)
    check("NVHLQ là payload LQ (%s)" % (lq_kind(raw) or "?"), lq_kind(raw) is not None,
          raw[:16].hex())
    check("NVHLQ > 4 KB (%d B)" % len(raw), len(raw) > 4_000)
    if names is not None:
        check("NVHLQ bundle có HeroSkin_1 + HeroSkin_2 (%s)" % ",".join(names),
              "HeroSkin_1.bytes" in names and "HeroSkin_2.bytes" in names)
if os.path.isfile(vp):
    blob = open(vp, "rb").read()
    check("NVHLQ.vault có magic NVHV1", blob[:5] == b"NVHV1")
    check("NVHLQ.vault không lộ magic LQ",
          LQ_MAGIC not in blob[:64] and b"LQ2\x00" not in blob[:64])
    check("NVHLQ.vault giải mã đúng payload",
          os.path.isfile(src) and vault_decode(blob) == open(src, "rb").read())

print("\n== 6. Cân bằng ngoặc trong nguồn Swift ==")
PAIRS = {"{": "}", "(": ")", "[": "]"}
bad = []
for rel in swift_on_disk:
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    depth = {k: 0 for k in PAIRS}
    i, n = 0, len(src)
    in_str = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 1
        elif in_str:
            if c == BS:
                i += 1
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block = True
                i += 1
            elif c == '"':
                in_str = True
            elif c in PAIRS:
                depth[c] += 1
            elif c in PAIRS.values():
                for k, v in PAIRS.items():
                    if v == c:
                        depth[k] -= 1
        i += 1
    if any(v != 0 for v in depth.values()) or in_block or in_str:
        bad.append("%s %s" % (rel, depth))
check("mọi file .swift cân bằng ngoặc/chuỗi", not bad, str(bad))

print("\n== 7. Không còn TODO/placeholder ==")
bad2 = []
for rel in swift_on_disk:
    txt = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    for pat in ("FIXME", "XXX", "AppModel_serverStub", "stubCompare"):
        if pat in txt:
            bad2.append("%s: %s" % (rel, pat))
check("nguồn sạch placeholder", not bad2, str(bad2))

print()
print("checks: %d | fail: %d | warn: %d" % (checks, len(fails), len(warns)))
if fails:
    print("FAIL:", ", ".join(fails))
sys.exit(1 if fails else 0)
