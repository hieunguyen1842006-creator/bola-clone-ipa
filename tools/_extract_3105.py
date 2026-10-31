#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_extract_3105.py — giai nen mot file .3105 ra thu muc (tam thoi)."""
from __future__ import annotations

import os
import plistlib
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC


def main(path: str, outdir: str, password: str) -> None:
    data = open(path, "rb").read()
    i = data.index(b"bplist00")
    p = plistlib.loads(data[i:])
    pid = p["packageID"]
    sv = p.get("schemaVersion", 1)

    if p.get("isPasswordProtected"):
        kek = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32,
                         salt=p["kdfSalt"], iterations=p["kdfIterations"]
                         ).derive(password.encode())
        w = p["wrappedContentKey"]
        aad = f"3105PATCH/v{p.get('keyAADVersion') or sv}/key/{pid}".encode()
        ck = AESGCM(kek).decrypt(w[:12], w[12:44] + w[44:60], aad)
    else:
        ck = p["publicContentKey"]

    aad = f"3105PATCH/v{sv}/payload/{pid}".encode()
    pt = AESGCM(ck).decrypt(p["encryptedPayload"][:12], p["encryptedPayload"][12:], aad)
    inner = plistlib.loads(pt)
    proj = inner.get("project", {})
    os.makedirs(outdir, exist_ok=True)
    for r in proj.get("rules", []):
        fn = r.get("replacementFilename", "?")
        d = r.get("replacementData", b"")
        out = os.path.join(outdir, os.path.basename(fn))
        open(out, "wb").write(d)
        print(f"  -> {out}  ({len(d)} B)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
