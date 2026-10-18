#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audit_core.py -- kiem tra "phan loi" con thieu cua BolaClone: primitive container.

Khong tao exploit. Chi doc source, doi chieu hop dong KernelPrimitive, va in ra:
  - duong nao da chay duoc KHONG can primitive
  - duong nao dang phu thuoc primitive (va no se lam gi khi thieu)
  - primitive nao da co implementation that
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    files = {p.relative_to(ROOT).as_posix(): read(p) for p in SRC.rglob("*.swift")}
    blob = "\n".join(files.values())

    print("== 1. Hop dong KernelPrimitive ==")
    kp = files.get("Sources/Core/KernelPrimitive.swift", "")
    req = re.findall(r"^\s{4}func (\w+)\(", kp, re.M)
    print(f"   methods bat buoc : {', '.join(req) or '(khong doc duoc)'}")

    print("\n== 2. Ai implement protocol ==")
    impls = []
    for name, text in files.items():
        for m in re.finditer(r"class (\w+)\s*:\s*[^{]*KernelPrimitive", text):
            impls.append((m.group(1), name))
    for cls, f in impls:
        body = read(ROOT / f)
        start = body.find(f"class {cls}")
        seg = body[start:start + 4000]
        has_kernel = "prepareKernelRW" in seg and "throw" not in seg.split("prepareKernelRW")[1][:120]
        print(f"   {cls:28} {f}")
        print(f"      prepareKernelRW co code that? {'CO' if has_kernel else 'KHONG (mock/throw)'}")

    print("\n== 3. Duong truy cap container ==")
    for label in ("DirectContainerAccess", "AppGroupContainerAccess",
                  "MobileHouseArrestProbe", "PathContainerAccess",
                  "PrimitiveContainerAccess"):
        hit = [f for f, t in files.items() if label in t]
        print(f"   {label:26} {'co' if hit else 'KHONG':5}  {', '.join(hit)}")

    print("\n== 4. Hanh vi khi thieu primitive ==")
    checks = {
        "notPlugged": "chua cam primitive -> khong ghi gi",
        "grantUnusable": "grant rong -> dung, teardown",
        "kernelStageFailed": "tang 1 loi -> khong sang tang 2, teardown",
        "writeVerifyFailed": "ghi xong doc lai lech -> bao loi",
    }
    for key, note in checks.items():
        print(f"   {key:20} {'co' if key in blob else 'THIEU':4}  {note}")

    print("\n== 5. Ket luan ==")
    print("   Phan con thieu KHONG phai UI/logic: do la 2 tang primitive")
    print("   (kernel r/w + sandbox escape). Khong co no thi app dung o buoc")
    print("   'chua cam primitive' va khong ghi file nao vao container game.")
    print("   Duong 1-3 (jailbreak / app-group / MHA) van chay doc lap.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
