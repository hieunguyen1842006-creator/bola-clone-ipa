#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vmtest_menu.py — chạy khối menu trong interpreter IFix cục bộ (PC).

Dùng parser + VM từ toolkit "LQ NS" (verify cùng format LQMB): parse payload
ResD của mình, chạy hook block CTimerManager::Update với stub Unity API.
Mục đích: bắt lỗi điều khiển (branch/stack/kiểu) trước khi lên thiết bị.

  python tools/vmtest_menu.py [open|closed]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
TOOLKIT = r"D:/FileChuaHack/FF DATA IOS/LQ/LQ NS/THÔNG BÁO HẠ NÚT BẤM/THÔNG BÁO HẠ NÚT BẤM/work"
sys.path.insert(0, TOOLKIT)

import merge_menu as mm  # noqa: E402
from _ifix_vm import Obj, execute  # noqa: E402

try:
    from HeroSkin_DumpRepack import parse_patch  # noqa: E402
except ImportError:
    print("SKIP: không có toolkit LQ NS trên máy này — bỏ qua VM test")
    raise SystemExit(0)

VOID = {
    "SetParent", "set_anchoredPosition", "set_sizeDelta", "set_anchorMin",
    "set_anchorMax", "set_pivot", "set_color", "set_raycastTarget", "set_font",
    "set_fontSize", "set_alignment", "set_horizontalOverflow",
    "set_verticalOverflow", "set_supportRichText", "set_text", "set_enabled",
    "set_localScale", "set_renderMode", "set_sortingOrder", "set_uiScaleMode",
    "SetInt", "SetFloat", "Save", "WriteAllText",
    "DontDestroyOnLoad", "SetActive", "Update",
}


class MenuNative:
    def __init__(self, mode):
        self.mode = mode            # "open" | "closed"
        self.writes = []
        self.finds = []

    def isinst(self, type_name, obj):
        return obj

    def box(self, type_name, value):
        return value

    def static_field(self, field):
        name = field.get("name", "")
        if name == "wrapperArray":
            return [Obj()]
        if name.endswith("-Update0"):
            return 0
        return Obj()

    def call(self, d, args):
        n = d["method_name"]
        if n == "Find":
            key = args[0]
            self.finds.append(key)
            if key == "__nvhMenuCanvas":
                return None          # buộc dựng canvas
            if key == "__nvhPanel":
                return None          # buộc dựng panel
            return Obj()
        if n == "GetInt":
            if args[0] == "__nvhMenuOpen2":
                return 1 if self.mode == "open" else 0
            return 0
        if n == "GetFloat":
            return 0.0
        if n == "WriteAllText":
            self.writes.append((args[0], args[1]))
            return None
        if n == "GetEnvironmentVariable":
            return "/home"
        if n == "get_touchCount":
            return 0
        if n == "get_frameCount":
            return 1
        if n == "get_width":
            return 1920
        if n == "get_height":
            return 1080
        if n in ("op_Inequality",):
            return 1 if args[0] is not args[1] else 0
        if n in ("op_Equality",):
            return 1 if args[0] is args[1] else 0
        if n == "GetComponent" or n == "AddComponent":
            return Obj()
        if n == "GetBuiltinResource":
            return Obj()
        if n == "GetTouch":
            return Obj(position=Obj(x=0, y=0), phase=0)
        if n == "get_position" or n == "get_transform" or n == "get_parent":
            return Obj(x=0, y=0)
        if n == "get_Length":
            return len(args[0]) if isinstance(args[0], str) else 0
        if n == "Concat":
            return "".join(str(a) for a in args if a is not None)
        if n == "get_activeSelf" or n == "get_activeInHierarchy":
            return 1
        if n == "get_childCount":
            return 4
        if n == "get_sizeDelta" or n == "get_anchoredPosition":
            return Obj(x=0.0, y=0.0)
        return Obj() if n not in VOID else None


def arities(patch):
    out = {}
    for m in patch["methods"]:
        for ins in m["instructions"]:
            if ins["op"] == "CallExtern":
                idx = ins["operand"] & 0xFFFF
                name = patch["extern_methods"][idx]["method_name"]
                out[idx] = 0 if name in VOID else 1
    return out


def run(mode, calls=21):
    blob = open(os.path.join(HERE, "..", "Resources", "LQFullMenu34.bytes"), "rb").read()
    import struct
    ent = {}
    off = 8
    for _ in range(struct.unpack_from("<I", blob, 4)[0]):
        nl = blob[off]; off += 1
        name = blob[off:off + nl].decode(); off += nl
        sz = struct.unpack_from("<I", blob, off)[0]; off += 4
        ent[name] = blob[off:off + sz]; off += sz
    _, _, body, _ = mm.resd_decrypt(ent["HeroSkin_2.bytes"], "HeroSkin_2")
    patch = parse_patch(body)
    # hook cuối = interpret cuối; parser của họ đọc fix registry cuối file
    hook_method = patch["fixes"][-1]["method_id"]
    native = MenuNative(mode)
    ar = arities(patch)
    this = Obj()
    for i in range(calls):
        execute(patch, hook_method, [this], native, ar)
    return native, this


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "closed"
    native, this = run(mode)
    print(f"PASS [{mode}]: {21} calls, no VM fault; "
          f"__mMenuCalls={this.get('__mMenuCalls')}, "
          f"finds={len(native.finds)}, writes={len(native.writes)}")