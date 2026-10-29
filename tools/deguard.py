#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""deguard.py — vo hieu guard anti-tamper cua patch IFix LQMB, KHONG doi index.

Guard cua payload that ("Arena Of Valor" / "CamXa-FullSkin-Esp Liqi"):
  - moi block hook bat dau bang `Call <guardVm>` (vm38 o HS1, vm20 o HS2)
  - guard block lam: Monitor.Enter -> doc ifix.bundle.manifest -> RSA verify
    -> hash HeroSkin_*.bytes -> lech thi throw
    "IFix integrity check failed; restore the complete matching bundle and restart"

Vi sao KHONG xoa lenh `Call guard`:
  - exception handler luu TryStart/TryEnd/HandlerStart/HandlerEnd la index
    TUYET DOI -> xoa lenh se lam lech, phai sua tay tung handler
  - Br la offset tuong doi -> cung phai sua neu biet chac semantics
  => rui ro cao, de hong game

Chien luoc: thay NOI DUNG block guard thanh `BlockHeader(0,0) / Ret 0` va xoa
handler cua no. Moi `Call guardVm` tro thanh loi goi ham rong -> no-op.
Toan bo type/method/string/field/block index giu nguyen 100%.

Chay:
    python tools/deguard.py <in.bytes>              # chi bao cao
    python tools/deguard.py <in.bytes> <out.bytes>  # ghi ban da go guard
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

OP_CALL = 0x2D
OP_BLOCKHEADER = 0x92
OP_RET = 0xAD
GUARD_MARK = "aUZpeC5idW5kbGUuZ3VhcmQ"   # base64 cua "iFix.bundle.guard"


def find_guards(pf) -> list[int]:
    """Block chua guard marker (doc manifest/signature) => block guard."""
    out = []
    for i, blk in enumerate(pf["blocks"]):
        ins = blk["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] == 0x27 and 0 <= ins[k + 1] < len(pf["strings"]):
                if pf["strings"][ins[k + 1]].startswith(GUARD_MARK):
                    out.append(i)
                    break
    return out


def report(path: str) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    tag, _ol, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)
    guards = find_guards(pf)

    print(f"== {os.path.basename(path)}  {len(blob)} B  tag={tag} enc={enc}")
    print(f"   types={len(pf['types'])} methods={len(pf['methods'])} "
          f"strings={len(pf['strings'])} fields={len(pf['fields'])}")
    print(f"   blocks={len(pf['blocks'])} nextAlloc={pf['nextAlloc']} "
          f"hooks={len(pf['interpret'])} fsvm={pf['fsvm']}")
    print(f"   guard blocks: {guards}")
    if guards:
        for g in guards:
            print(f"     vm{g}: {len(pf['blocks'][g]['instrs'])//2} lenh, "
                  f"{len(pf['blocks'][g]['handlers'])} handler, "
                  f"Ret operand={pf['blocks'][g]['instrs'][-1]}")
    n_call = sum(
        1 for blk in pf["blocks"]
        if any(blk["instrs"][k] == OP_CALL and blk["instrs"][k + 1] in guards
               for k in range(0, len(blk["instrs"]) - 1, 2)))
    print(f"   block goi guard: {n_call}/{len(pf['blocks'])}")

    print("\n   Hook (vm, so lenh, ten):")
    for h in pf["interpret"]:
        m = h["method"]
        d = pf["types"][m["declType"]].split(",")[0]
        print(f"     vm{h['vm']:<4} {len(pf['blocks'][h['vm']]['instrs'])//2:>5} "
              f"{d}::{m['name']}")


def deguard(path: str, out_path: str) -> None:
    blob = open(path, "rb").read()
    res = os.path.splitext(os.path.basename(path))[0]
    tag, _ol, body, enc = resd_decrypt(blob, res)
    pf = lqmb_parse(body)

    if lqmb_serialize(pf) != body:
        raise SystemExit("round-trip goc KHONG byte-exact -> dung lai")

    guards = find_guards(pf)
    if not guards:
        print("   khong co guard -> khong can go")
        return

    n_hooks = 0
    for g in guards:
        blk = pf["blocks"][g]
        old_n = len(blk["instrs"]) // 2
        old_h = len(blk["handlers"])
        # thanh ham rong: BlockHeader(locals=0, maxstack=0) + Ret 0
        blk["instrs"] = [OP_BLOCKHEADER, 0, OP_RET, 0]
        blk["handlers"] = []
        n_hooks += sum(
            1 for b in pf["blocks"]
            if any(b["instrs"][k] == OP_CALL and b["instrs"][k + 1] == g
                   for k in range(0, len(b["instrs"]) - 1, 2)))
        print(f"   vm{g}: {old_n} lenh / {old_h} handler -> rong (4 i32)")

    new_body = lqmb_serialize(pf)
    back = lqmb_parse(new_body)

    # ---- verify khong doi cau truc ----
    assert lqmb_serialize(back) == new_body, "round-trip sau deguard loi"
    assert len(back["types"]) == len(pf["types"])
    assert len(back["methods"]) == len(pf["methods"])
    assert len(back["strings"]) == len(pf["strings"])
    assert len(back["fields"]) == len(pf["fields"])
    assert len(back["blocks"]) == len(pf["blocks"])
    assert back["nextAlloc"] == pf["nextAlloc"]
    assert len(back["interpret"]) == len(pf["interpret"])

    # moi block khac guard phai GIONG HET tung i32
    diff = 0
    for i, (a, b) in enumerate(zip(pf["blocks"], back["blocks"])):
        if i in guards:
            continue
        if a["instrs"] != b["instrs"] or a["handlers"] != b["handlers"]:
            diff += 1
            print(f"   ! vm{i} bi doi (khong mong muon)")
    assert diff == 0, f"{diff} block ngoai guard bi doi"

    # guard da rong
    for g in guards:
        assert back["blocks"][g]["instrs"] == [OP_BLOCKHEADER, 0, OP_RET, 0]
        assert back["blocks"][g]["handlers"] == []

    print(f"   verify OK: index giu nguyen, {n_hooks} Call guard -> no-op")
    print(f"   body {len(body)} B -> {len(new_body)} B "
          f"(giam {len(body) - len(new_body)} B)")

    out = resd_encrypt(new_body, res, tag, enc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: deguard.py <in.bytes> [out.bytes]")
    if len(sys.argv) == 2:
        report(sys.argv[1])
    else:
        deguard(sys.argv[1], sys.argv[2])
