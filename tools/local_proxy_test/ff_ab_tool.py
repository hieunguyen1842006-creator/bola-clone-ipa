#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ff_ab_tool.py — soi / bung / đóng gói lại bundle `assembly-csharp-patch` của FF.

Bundle FF (UnityFS, engine ghi "2018.4.12f1") thực chất KHÔNG mã hoá: bit 0x200
trong header là "blocksInfo cần padding" (flag kiểu mới), nhưng vì chuỗi engine
< 2020 nên UnityPy chọn bộ flag cũ và hiểu nhầm 0x200 = mã hoá.

Cách xử lý: tạm đổi chuỗi engine thành "2022.3.47f1" (cùng 11 ký tự) để UnityPy
đọc đúng, làm việc, rồi đổi lại "2018.4.12f1" trước khi ghi ra.

Lệnh:
    python ff_ab_tool.py inspect <bundle> [out_textasset.bin]
    python ff_ab_tool.py build   <bundle> <patch.bytes> [out.bundle]

Ghi chú:
    - Bundle tải từ CDN có thể là gzip; tool tự giải nén trước.
    - `build` xuất bundle UnityFS không mã hoá, TextAsset giữ tên
      "Assembly-CSharp-patch" để IFix load đúng.
"""
from __future__ import annotations

import gzip
import hashlib
import os
import sys

import UnityPy
from UnityPy.files import BundleFile

OLD = b"2018.4.12f1"
NEW = b"2022.3.47f1"
TMP = os.path.join(os.environ.get("TEMP", "."), "_ff_ab_tool.bundle")


def read_maybe_gzip(path: str) -> bytes:
    d = open(path, "rb").read()
    return gzip.decompress(d) if d[:2] == b"\x1f\x8b" else d


def swap_engine(buf: bytearray, old: bytes, new: bytes) -> int:
    i = buf.find(old)
    if i < 0:
        raise SystemExit("không thấy chuỗi engine %r" % old)
    if len(old) != len(new):
        raise SystemExit("độ dài chuỗi engine phải bằng nhau")
    buf[i:i + len(old)] = new
    return i


def open_env(raw: bytes):
    buf = bytearray(raw)
    swap_engine(buf, OLD, NEW)
    open(TMP, "wb").write(buf)
    return UnityPy.load(TMP)


def textasset_bytes(ob) -> bytes:
    s = ob.m_Script
    return s.encode("utf-8", "surrogateescape") if isinstance(s, str) else bytes(s)


def cmd_inspect(bundle: str, out: str | None) -> int:
    env = open_env(read_maybe_gzip(bundle))
    for o in env.objects:
        ob = o.read()
        name = getattr(ob, "m_Name", "")
        print("  %-16s %r" % (o.type.name, name))
        if o.type.name == "TextAsset":
            raw = textasset_bytes(ob)
            print("     %d B  sha1=%s  head=%s" % (len(raw), hashlib.sha1(raw).hexdigest()[:16], raw[:8].hex()))
            if out:
                open(out, "wb").write(raw)
                print("     ->", out)
    return 0


def cmd_build(bundle: str, patch: str, out: str | None) -> int:
    env = open_env(read_maybe_gzip(bundle))
    payload = read_maybe_gzip(patch)

    touched = 0
    for o in env.objects:
        if o.type.name != "TextAsset":
            continue
        ob = o.read()
        name = getattr(ob, "m_Name", "")
        if name and "patch" not in name.lower():
            continue
        ob.m_Script = payload.decode("utf-8", "surrogateescape")
        ob.save()
        touched += 1
        print("  thay TextAsset %r -> %d B" % (name, len(payload)))
    if not touched:
        raise SystemExit("không có TextAsset nào để thay")

    data = next(v for v in env.files.values() if isinstance(v, BundleFile)).save(packer="original")
    if isinstance(data, dict):
        data = next(iter(data.values()))
    data = bytearray(data)
    swap_engine(data, NEW, OLD)

    out = out or (os.path.splitext(os.path.basename(bundle))[0] + ".rebuild.bundle")
    open(out, "wb").write(data)
    gz = gzip.compress(bytes(data), 9, mtime=0)
    print("[+] %s  raw=%d B  gzip=%d B" % (out, len(data), len(gz)))
    print("    sha1 raw  =", hashlib.sha1(bytes(data)).digest().hex()[:16], "(hash1)")
    print("    sha1 gzip =", hashlib.sha1(gz).digest().hex()[:16], "(hash2 / dùng trong URL)")
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    cmd, bundle = sys.argv[1], sys.argv[2]
    if cmd == "inspect":
        return cmd_inspect(bundle, sys.argv[3] if len(sys.argv) > 3 else None)
    if cmd == "build":
        if len(sys.argv) < 4:
            print("thiếu <patch.bytes>")
            return 1
        return cmd_build(bundle, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    print("lệnh lạ:", cmd)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
