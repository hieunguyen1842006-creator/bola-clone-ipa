#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""strip_hs1_menu.py — gỡ hook ESP/aim CLASSIC khỏi HeroSkin_1 cho MENU pack.

MENU mode = bộ tính năng RIÊNG: menu UI + port MODULE290. Không dùng chung
ESP/aim classic (yêu cầu: "mỗi cái là 1 kiểu"). Classic pack (LQFull.bytes)
giữ nguyên 42 hook.

Gỡ interpret: ChangeMeshCallBack (ESP box), UpdateUseSkillDirection,
SelectSkillDirection ×2, SelectSkillPos ×2. Blocks giữ nguyên (không dùng).
Giữ: GetZoomRate (consumer của switch Cam xa), skin/banner/lobby hooks.

Chạy: python tools/strip_hs1_menu.py <HS1.bytes> <out.bytes>
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

STRIP_NAMES = {
    "ChangeMeshCallBack",          # ESP box classic
    "UpdateUseSkillDirection",     # aim vẽ hướng skill classic
    "SelectSkillDirection",        # DefaultAttackMode + LockTargetAttackMode
    "SelectSkillPos",              # cả 2 attack mode
}


def strip(hs1_path: str, out_path: str) -> int:
    p, tag, enc, res = mm.load(hs1_path)
    before = len(p["interpret"])
    kept = []
    removed = []
    for h in p["interpret"]:
        name = h["method"]["name"]
        if name in STRIP_NAMES:
            removed.append(f"vm{h['vm']}:{name}")
        else:
            kept.append(h)
    p["interpret"] = kept
    body = mm.lqmb_serialize(p)
    back = mm.lqmb_parse(body)
    assert mm.lqmb_serialize(back) == body, "roundtrip loi"
    assert len(back["interpret"]) == before - len(removed)
    out = mm.resd_encrypt(body, res, tag, enc)
    open(out_path, "wb").write(out)
    print(f"strip HS1: {before} -> {len(kept)} hook (bỏ {len(removed)}: "
          f"{', '.join(removed)})")
    return len(kept)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: strip_hs1_menu.py <HS1.bytes> <out.bytes>")
    strip(sys.argv[1], sys.argv[2])
