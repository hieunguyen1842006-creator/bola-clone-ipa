#!/usr/bin/env python3
"""Run: python -I tools/test_menu_vm22.py [menu-pack.bytes]"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm
from build_menu34_pack import parse_lq2

ROOT = os.path.dirname(HERE)
BRANCHES = {93, 134, 127, 110, 125, 11, 17, 47, 43, 33, 30, 176, 111, 153}


def hs2(path):
    entries = dict(parse_lq2(open(path, "rb").read()))
    _, _, body, _ = mm.resd_decrypt(entries["HeroSkin_2.bytes"], "HeroSkin_2")
    return mm.lqmb_parse(body)


def check(original, merged):
    old = original["blocks"][22]["instrs"]
    new = merged["blocks"][22]["instrs"]
    boundary = len(old) // 2 - 2
    menu_vm = len(original["blocks"])
    inserted = [(164, 0), (45, (1 << 16) | menu_vm)]
    assert list(zip(new[2 * boundary::2], new[2 * boundary + 1::2])) == (
        inserted + [(72, 16), (173, 1)]
    ), "menu exit must push this, Call argc1, then preserve original return"
    seen = 0
    for pc in range(boundary):
        opcode, operand = old[2 * pc:2 * pc + 2]
        if opcode in BRANCHES:
            target = pc + operand
            expected = target if target <= boundary else target + len(inserted)
            assert new[2 * pc] == opcode and pc + new[2 * pc + 1] == expected, (
                f"branch pc{pc} skips menu: expected target {expected}"
            )
            seen += target == boundary
        else:
            assert new[2 * pc:2 * pc + 2] == [opcode, operand], f"vm22 pc{pc} changed"
    assert seen == 6, f"expected all 6 original return branches, got {seen}"
    assert merged["blocks"][22]["handlers"] == original["blocks"][22]["handlers"]
    assert merged["interpret"] == original["interpret"], "hook table changed"
    for vm in range(menu_vm):
        if vm != 22:
            assert merged["blocks"][vm] == original["blocks"][vm], f"original vm{vm} changed"
    for table in ("types", "methods", "strings", "fields"):
        assert merged[table][:len(original[table])] == original[table], f"{table} prefix changed"
    menu = merged["blocks"][menu_vm]
    returns = [menu["instrs"][i + 1] for i in range(0, len(menu["instrs"]), 2)
               if menu["instrs"][i] == 173]
    assert returns and set(returns) == {0}, "menu must return void"
    assert all(h[0] != 0 or (0 <= h[1] < len(merged["types"]) and
               "System.Exception," in merged["types"][h[1]])
               for h in menu["handlers"]), "catch type not remapped to System.Exception"
    counters = {f["name"] for f in merged["fields"] if f["isNew"]}
    assert {"__mCalls", "__mMenuCalls"} <= counters, "menu counter aliases Classic counter"


if __name__ == "__main__":
    original = hs2(os.path.join(ROOT, "Resources", "LQFull.bytes"))
    merged = hs2(sys.argv[1] if len(sys.argv) > 1 else
                 os.path.join(ROOT, "Resources", "LQFullMenu34.bytes"))
    check(original, merged)
    print("PASS: 6 return branches reach menu; this/void/catch types valid; Classic unchanged")
