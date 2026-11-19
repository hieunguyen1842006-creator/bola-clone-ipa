#!/usr/bin/env python3
"""So sanh tap lenh CallExtern cua mot payload voi payload da chay duoc tren may."""
import os
import sys
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

RES = os.path.join(os.path.dirname(HERE), "Resources")


def calls(path, res):
    p, _, _, _ = mm.load(path, res)
    out = collections.Counter()
    for blk in p["blocks"]:
        ins = blk["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] == mm.OP_CALLEXTERN:
                midx = ins[k + 1] & 0xFFFF
                if midx < len(p["methods"]):
                    m = p["methods"][midx]
                    out[(p["types"][m["declType"]].split(",")[0], m["name"],
                         ins[k + 1] >> 16)] += 1
    return out, p


if __name__ == "__main__":
    from test_menu_vm22 import hs2
    proven, _ = calls(os.path.join(RES, "LQHud.bytes"), "LQHud")
    menu = {}
    mp = hs2(sys.argv[1] if len(sys.argv) > 1 else
             os.path.join(RES, "LQFullMenu34.bytes"))
    for blk in mp["blocks"]:
        ins = blk["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] == mm.OP_CALLEXTERN:
                midx = ins[k + 1] & 0xFFFF
                if midx < len(mp["methods"]):
                    m = mp["methods"][midx]
                    menu[(mp["types"][m["declType"]].split(",")[0], m["name"],
                          ins[k + 1] >> 16)] = menu.get(
                              (mp["types"][m["declType"]].split(",")[0], m["name"],
                               ins[k + 1] >> 16), 0) + 1
    print("=== menu calls NOT proven by LQHud ===")
    for key in sorted(menu, key=lambda k: -menu[k]):
        if key not in proven:
            print(f"{menu[key]:5d}  {key[0]}.{key[1]} argc={key[2]}")
