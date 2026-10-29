#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pack_lq2.py — dong goi nhieu file .bytes thanh bundle "LQ2\0" de app cai.

Format (khop LienQuanDeployer.parseBundle):
    "LQ2\\0" | u32 soFile | [u8 lenTen][ten][u32 size][data]...

Chay: python tools/pack_lq2.py <out.bytes> <ten1:duongDan1> [ten2:duongDan2 ...]

Vi du:
    python tools/pack_lq2.py Resources/LQFull.bytes \
        HeroSkin_1.bytes:_lqharvest/out/HS1_on.bytes \
        HeroSkin_2.bytes:_lqharvest/out/HS2_on.bytes
"""
from __future__ import annotations

import os
import sys


def build(files: list[tuple[str, bytes]]) -> bytes:
    out = bytearray(b"LQ2\x00")
    out += len(files).to_bytes(4, "little")
    for name, data in files:
        nb = name.encode("utf-8")
        assert 0 < len(nb) <= 64, f"ten file sai do dai: {name}"
        out.append(len(nb))
        out += nb
        out += len(data).to_bytes(4, "little")
        out += data
    return bytes(out)


def main(out_path: str, specs: list[str]) -> None:
    files = []
    for spec in specs:
        name, path = spec.split(":", 1)
        data = open(path, "rb").read()
        files.append((name, data))
        print(f"  + {name:22s} {len(data):>8} B  <- {path}")
    blob = build(files)
    open(out_path, "wb").write(blob)
    print(f"\n  ghi {out_path} ({len(blob)} B, {len(files)} file)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: pack_lq2.py <out.bytes> <ten:path> ...")
    main(sys.argv[1], sys.argv[2:])
