#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scan_3105.py — quet moi file .3105/.3105.dat trong cac thu muc cho truoc:
  - doc duoc envelope + bplist khong
  - co password khong
  - neu khong password -> decrypt -> liet ke file ben trong + hook IFix (neu la .bytes)

Muc dich: tim dung file 3105 chua du chuc nang (ESP/xray/aim/fullskin/fakehost/zoom)
cua Lien Quan.

Chay: python tools/scan_3105.py <dir> [dir2 ...]
"""
from __future__ import annotations

import hashlib
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
lqmb_parse = _ns["lqmb_parse"]

try:
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    HAVE_CRYPTO = True
except Exception:
    HAVE_CRYPTO = False

SKIP = {"pnpm-store", "node_modules", "apk_asset", ".git", "__pycache__",
        "ipa_work", "CFM Mobile"}


def find_bplist(d: bytes) -> int:
    return d.index(b"bplist00")


def walk(dirs, exts=(".3105", ".3105.dat")):
    for d in dirs:
        for base, subdirs, files in os.walk(d):
            subdirs[:] = [s for s in subdirs if s not in SKIP]
            for f in files:
                if any(f.lower().endswith(e) for e in exts):
                    yield os.path.join(base, f)


def try_bytes(name: str, data: bytes) -> None:
    """Neu data la container ResD -> liet ke hook."""
    res = os.path.splitext(os.path.basename(name))[0]
    try:
        _t, _ol, body, _e = resd_decrypt(data, res)
    except Exception:
        return
    try:
        pf = lqmb_parse(body)
    except Exception:
        return
    hooks = []
    for h in pf["interpret"]:
        m = h["method"]
        decl = pf["types"][m["declType"]].split(",")[0]
        hooks.append(decl.split(".")[-1] + "::" + m["name"])
    if hooks:
        print(f"      IFix: {len(hooks)} hook types={len(pf['types'])} "
              f"blocks={len(pf['blocks'])} -> {', '.join(hooks[:8])}"
              + (" ..." if len(hooks) > 8 else ""))


def scan(path: str, password: str | None) -> None:
    data = open(path, "rb").read()
    print(f"\n== {os.path.basename(path)}  ({len(data)} B)")
    try:
        i = find_bplist(data)
    except ValueError:
        print("   khong phai envelope 3105 (khong co bplist)")
        try_bytes(os.path.basename(path), data)
        return
    try:
        p = plistlib.loads(data[i:])
    except Exception as e:
        print(f"   bplist loi: {e}")
        return

    pid = p.get("packageID", "")
    sv = p.get("schemaVersion", 1)
    print(f"   packageID={pid} schema={sv} pw={p.get('isPasswordProtected')}")

    ck = None
    if p.get("isPasswordProtected"):
        if not password or not HAVE_CRYPTO:
            print("   -> can password / thieu cryptography, bo qua")
            return
        kek = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32,
                         salt=p["kdfSalt"], iterations=p["kdfIterations"]).derive(password.encode())
        w = p["wrappedContentKey"]
        aad = f"3105PATCH/v{p.get('keyAADVersion') or sv}/key/{pid}".encode()
        try:
            ck = AESGCM(kek).decrypt(w[:12], w[12:44] + w[44:60], aad)
        except Exception as e:
            print(f"   -> sai password ({e})")
            return
        print("   -> password OK")
    else:
        ck = p.get("publicContentKey")
        if ck is None:
            print("   -> khong co key")
            return

    pay = p.get("encryptedPayload", b"")
    aad = f"3105PATCH/v{sv}/payload/{pid}".encode()
    try:
        pt = AESGCM(ck).decrypt(pay[:12], pay[12:], aad)
    except Exception as e:
        print(f"   -> payload decrypt loi: {e}")
        return

    try:
        inner = plistlib.loads(pt)
    except Exception:
        print(f"   -> payload {len(pt)} B (khong phai plist)")
        return

    proj = inner.get("project", {}) if isinstance(inner, dict) else {}
    print(f"   project={proj.get('name')!r} author={proj.get('author')!r}")
    for r in proj.get("rules", []):
        fn = r.get("replacementFilename", "?")
        d = r.get("replacementData", b"")
        print(f"     rule: {fn}  {len(d)} B  path={r.get('relativePath','')}")
        try_bytes(fn, d)


def main(dirs, password=None) -> None:
    files = list(walk(dirs))
    print(f"tim thay {len(files)} file 3105")
    for f in files:
        try:
            scan(f, password)
        except Exception as e:
            print(f"\n== {os.path.basename(f)}: loi {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("dung: scan_3105.py <dir> [dir2 ...]")
    main(sys.argv[1:], os.environ.get("P3105"))
