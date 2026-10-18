#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_vault.py — đóng gói patch IFix thành blob mã hoá (.vault).

IPA chỉ mang blob; lúc inject app giải mã rồi mới ghi file thật vào container game.

Format:
    "NVHV1" (5) | length u32 LE (4) | sha256(plain) (32) | ciphertext
Keystream: sha256(key || counter_u32_le), XOR từng block 32 byte.

Đóng gói:
    NVHMenu.bytes      -> NVHMenu.vault
    NeutralPatch.bytes -> NeutralPatch.vault
"""
from __future__ import annotations

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = hashlib.sha256(b"NVH-MOD-2026:vault:v1").digest()
MAGIC = b"NVHV1"

TARGETS = [
    ("NVHMenu.bytes", "NVHMenu.vault"),
    ("NeutralPatch.bytes", "NeutralPatch.vault"),
    ("LQHud.bytes", "LQHud.vault"),
    ("LQUnlock.bytes", "LQUnlock.vault"),
]


def encrypt(data: bytes) -> bytes:
    blocks = (len(data) + 31) // 32
    ks = b"".join(hashlib.sha256(KEY + i.to_bytes(4, "little")).digest()
                  for i in range(blocks))
    ct = bytes(a ^ b for a, b in zip(data, ks))
    return MAGIC + len(data).to_bytes(4, "little") + hashlib.sha256(data).digest() + ct


def decrypt(blob: bytes) -> bytes:
    if not blob.startswith(MAGIC):
        raise ValueError("magic sai")
    n = int.from_bytes(blob[5:9], "little")
    digest = blob[9:41]
    ct = blob[41:]
    blocks = (n + 31) // 32
    ks = b"".join(hashlib.sha256(KEY + i.to_bytes(4, "little")).digest()
                  for i in range(blocks))
    pt = bytes(a ^ b for a, b in zip(ct[:n], ks[:n]))
    if len(pt) != n or hashlib.sha256(pt).digest() != digest:
        raise ValueError("hash sai")
    return pt


def main() -> int:
    for src_name, dst_name in TARGETS:
        src = os.path.join(ROOT, "Resources", src_name)
        dst = os.path.join(ROOT, "Resources", dst_name)
        plain = open(src, "rb").read()
        blob = encrypt(plain)
        open(dst, "wb").write(blob)
        assert decrypt(blob) == plain
        print("%-20s %6d B -> %-20s %6d B" % (src_name, len(plain), dst_name, len(blob)))
        print("   IFix magic: %s | bolaminhduc: %s"
              % (b"\xcb\xa2\xb4\x0d" in blob[:64], b"bolaminhduc" in blob.lower()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
