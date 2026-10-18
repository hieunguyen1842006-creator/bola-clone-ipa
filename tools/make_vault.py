#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_vault.py — đóng gói NVHMenu.bytes thành NVHMenu.vault (blob mã hoá).

IPA chỉ mang blob này; lúc inject app giải mã rồi mới ghi
Assembly-CSharp-patch.bytes vào container game.

Format:
    "NVHV1" (5) | length u32 LE (4) | sha256(plain) (32) | ciphertext
Keystream: sha256(key || counter_u32_le), XOR từng block 32 byte.
"""
from __future__ import annotations

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Resources", "NVHMenu.bytes")
DST = os.path.join(ROOT, "Resources", "NVHMenu.vault")
KEY = hashlib.sha256(b"NVH-MOD-2026:vault:v1").digest()
MAGIC = b"NVHV1"


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
    plain = open(SRC, "rb").read()
    blob = encrypt(plain)
    open(DST, "wb").write(blob)
    assert decrypt(blob) == plain
    print("vault: %d B plain -> %d B blob" % (len(plain), len(blob)))
    print("Magic IFix trong blob:", b"\xcb\xa2\xb4\x0d" in blob[:64])
    print("Chuoi 'bolaminhduc' trong blob:", b"bolaminhduc" in blob.lower())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
