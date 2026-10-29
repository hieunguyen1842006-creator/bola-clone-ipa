#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""prefs_default.py — bat/tat tinh nang bang cach sua GIA TRI MAC DINH cua
PlayerPrefs.GetInt/GetFloat trong IL. Chi doi 1 i32 operand -> khong lech index,
khong dung Br/handler.

Pattern trong IL:
    Ldstr "iFix.ESP.Enabled.v1"
    Ldc_I4 0                       <-- doi operand nay
    CallExtern PlayerPrefs::GetInt(String, int)

Vi sao hieu qua: lan dau chay game, key chua ton tai -> game dung default.
Mac dinh 1 = tinh nang BAT ngay, khong can menu.

Chay:
    python tools/prefs_default.py <in.bytes>                  # liet ke
    python tools/prefs_default.py <in.bytes> <out.bytes> KEY=VAL ...
"""
from __future__ import annotations

import os
import struct
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
OP_LDC_I4 = 0x8F
OP_LDC_R4 = 0x8D
OP_CALLEXTERN = 0x7A


def find_sites(pf):
    """Tra ve [(blockIdx, key, kind, vi tri instr cua const, gia tri hien tai)]."""
    out = []
    prefs_types = {}
    for mi, m in enumerate(pf["methods"]):
        if m["name"] in ("GetInt", "GetFloat", "SetInt", "SetFloat"):
            decl = pf["types"][m["declType"]].split(",")[0]
            if decl == "UnityEngine.PlayerPrefs":
                prefs_types[mi] = m["name"]
    if not prefs_types:
        return out

    for bi, blk in enumerate(pf["blocks"]):
        ins = blk["instrs"]
        n = len(ins) // 2
        for k in range(n):
            i = k * 2
            if ins[i] != OP_LDSTR:
                continue
            sid = ins[i + 1]
            if not (0 <= sid < len(pf["strings"])):
                continue
            key = pf["strings"][sid]
            # tim CallExtern GetInt/GetFloat trong 6 lenh ke tiep
            for j in range(k + 1, min(k + 7, n)):
                jj = j * 2
                if ins[jj] == OP_CALLEXTERN:
                    mi = ins[jj + 1] & 0xFFFF
                    if mi in prefs_types and prefs_types[mi] in ("GetInt", "GetFloat"):
                        kind = prefs_types[mi]
                        # tim const ngay truoc call (bo qua Ldstr/Ldloc khac)
                        const_at = None
                        cur = None
                        for q in range(j - 1, k, -1):
                            qq = q * 2
                            if ins[qq] == (OP_LDC_I4 if kind == "GetInt" else OP_LDC_R4):
                                const_at = q
                                cur = ins[qq + 1]
                                break
                        out.append((bi, key, kind, const_at, cur))
                        break
    return out


def report(path: str) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    _t, _o, body, _e = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    sites = find_sites(pf)
    print(f"== {os.path.basename(path)}  ({len(pf['blocks'])} block, "
          f"{len(pf['strings'])} string)")
    print(f"   tim thay {len(sites)} cho doc PlayerPrefs co hang so mac dinh:\n")
    for bi, key, kind, const_at, cur in sites:
        if kind == "GetInt":
            val = cur
        else:
            val = struct.unpack("<f", struct.pack("<i", cur))[0]
        at = f"instr#{const_at}" if const_at is not None else "khong thay const"
        print(f"     vm{bi:<4} {kind:9s} {key:34s} default={val!r:12s} ({at})")


def apply(path: str, out_path: str, wanted: dict[str, str]) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    tag, _o, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    if lqmb_serialize(pf) != body:
        raise SystemExit("round-trip goc khong byte-exact")

    sites = find_sites(pf)
    changed = 0
    for bi, key, kind, const_at, cur in sites:
        if key not in wanted or const_at is None:
            continue
        want = wanted[key]
        k = const_at * 2
        if kind == "GetInt":
            new = int(want)
            if pf["blocks"][bi]["instrs"][k + 1] != new:
                pf["blocks"][bi]["instrs"][k + 1] = new
                changed += 1
                print(f"     vm{bi} {key}: {cur} -> {new}")
        else:
            new = struct.unpack("<i", struct.pack("<f", float(want)))[0]
            if pf["blocks"][bi]["instrs"][k + 1] != new:
                pf["blocks"][bi]["instrs"][k + 1] = new
                changed += 1
                print(f"     vm{bi} {key}: {struct.unpack('<f', struct.pack('<i', cur))[0]} "
                      f"-> {float(want)}")

    print(f"   da doi {changed} hang so")
    if changed == 0:
        print("   khong doi gi -> khong ghi file")
        return

    new_body = lqmb_serialize(pf)
    back = lqmb_parse(new_body)
    assert lqmb_serialize(back) == new_body
    assert len(back["blocks"]) == len(pf["blocks"])
    assert len(back["interpret"]) == len(pf["interpret"])
    # moi block phai cung do dai (chi doi operand)
    for a, b in zip(pf["blocks"], back["blocks"]):
        assert len(a["instrs"]) == len(b["instrs"])
        assert a["handlers"] == b["handlers"]
    print(f"   verify OK: chi operand doi, index/handler nguyen ven")

    out = resd_encrypt(new_body, res, tag, enc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: prefs_default.py <in.bytes> [out.bytes KEY=VAL ...]")
    if len(sys.argv) == 2:
        report(sys.argv[1])
    else:
        want = {}
        for a in sys.argv[3:]:
            if "=" in a:
                k, v = a.split("=", 1)
                want[k] = v
        apply(sys.argv[1], sys.argv[2], want)
