#!/usr/bin/env python3
"""Run: python -I tools/test_menu_vm22.py [menu-pack.bytes]"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402
from build_menu34_pack import parse_lq2  # noqa: E402

ROOT = os.path.dirname(HERE)


def hs2(path):
    entries = dict(parse_lq2(open(path, "rb").read()))
    _, _, body, _ = mm.resd_decrypt(entries["HeroSkin_2.bytes"], "HeroSkin_2")
    return mm.lqmb_parse(body)


def check_hooks(original, merged, menu):
    """Hook table: 6 classic + CTimerManager::Update; trampoline IL present."""
    inter = merged["interpret"]
    assert len(inter) == 7, f"hooks phai 7, thay {len(inter)}"
    assert all(h["method"]["name"] != "UpdateFrame" for h in inter), \
        "khong duoc con hook UpdateFrame (thay than goc = treo load)"
    upd = [h for h in inter if h["method"]["name"] == "Update"]
    assert len(upd) == 1, "phai dung 1 hook CTimerManager::Update"
    decl = merged["types"][upd[0]["method"]["declType"]].split(",")[0]
    assert decl == "CTimerManager", f"hook decl phai CTimerManager, thay {decl}"

    # Classic blocks + tables must be byte-identical prefixes.
    for table in ("types", "methods", "strings", "fields"):
        assert merged[table][:len(original[table])] == original[table], \
            f"{table} prefix changed"
    for vm in range(len(original["blocks"])):
        assert merged["blocks"][vm] == original["blocks"][vm], \
            f"Classic vm{vm} changed"

    # Trampoline IL inside the hook block (pattern proven by menuesp vm42).
    blk = merged["blocks"][upd[0]["vm"]]
    i2 = blk["instrs"]
    fld_of = lambda idx: (merged["fields"][idx]["name"]
                          if 0 <= idx < len(merged["fields"]) else "?")
    assert any(i2[2 * k] == 60 and fld_of(i2[2 * k + 1]) == "wrapperArray"
               for k in range(len(i2) // 2)), "thieu Ldsfld wrapperArray"
    assert any(i2[2 * k] == 122 and merged["methods"][i2[2 * k + 1] & 0xFFFF]["name"] == "Update"
               and (i2[2 * k + 1] >> 16) == 1
               for k in range(len(i2) // 2)), "thieu CallExtern host::Update argc1"
    assert any(i2[2 * k] == 175 for k in range(len(i2) // 2)), "thieu Stelem_Ref"

    counters = {f["name"] for f in merged["fields"] if f["isNew"]}
    assert {"__mCalls", "__mMenuCalls"} <= counters, "menu counter aliases Classic counter"


TOKEN_TABLES = {
    mm.OP_LDSTR: "strings",
    mm.OP_CALLEXTERN: "methods",
    mm.OP_NEWOBJ: "methods",
    **{op: "fields" for op in mm.FIELD_OPS},
    **{op: "types" for op in mm.TYPE_OPS},
}


def label(table, entry):
    if table == "types":
        return entry.split(",")[0].strip()
    if table == "methods":
        return entry["name"]
    if table == "fields":
        return entry["name"]
    return entry


def check_tokens(source, destination, src_vm, dst_vm):
    """Every token operand must still point at the same named entry.

    A wrong opcode id silently skips remapping and leaves a source index in the
    destination table: `box System.Int32` then boxes CSProtocol.CSPkg, the menu
    throws inside its own try, its catch swallows it, and nothing is drawn.
    """
    s = source["blocks"][src_vm]["instrs"]
    d = destination["blocks"][dst_vm]["instrs"]
    assert len(s) == len(d), f"block size changed: {len(s) // 2} -> {len(d) // 2}"
    checked = 0
    for k in range(0, len(s) - 1, 2):
        table = TOKEN_TABLES.get(s[k])
        if table is None:
            continue
        want = label(table, source[table][s[k + 1] & 0xFFFF])
        got = label(table, destination[table][d[k + 1] & 0xFFFF])
        assert want == got, (
            f"pc{k // 2} opcode {s[k]}: {table}[{s[k + 1] & 0xFFFF}] is "
            f"{want!r} in source but {got!r} in payload")
        checked += 1
    assert checked > 1000, f"token audit covered only {checked} operands"


if __name__ == "__main__":
    original = hs2(os.path.join(ROOT, "Resources", "LQFull.bytes"))
    merged = hs2(sys.argv[1] if len(sys.argv) > 1 else
                 os.path.join(ROOT, "Resources", "LQFullMenu34.bytes"))
    # nguồn so token = bản sau dispatcher (m290) nếu có, ngược lại MenuT
    m290 = os.path.join(ROOT, "_lqmenu", "work", "HeroSkin_2_m290.bytes")
    if os.path.exists(m290):
        srcp, _, _, _ = mm.load(m290, "HeroSkin_2")
        svm = merged["interpret"][-1]["vm"]
        check_hooks(original, merged, None)
        check_tokens(srcp, merged, svm, svm)
    else:
        menut = os.path.join(ROOT, "_lqmenu", "MenuT.bytes")
        menu, _, _, _ = mm.load(menut if os.path.exists(menut)
                                else os.path.join(ROOT, "_lqmenu", "Menu.bytes"))
        check_hooks(original, merged, menu)
        check_tokens(menu, merged, 0, merged["interpret"][-1]["vm"])
    print("PASS: 7 hooks (6 classic + CTimerManager::Update); trampoline IL present; "
          "Classic unchanged; token audit OK")
