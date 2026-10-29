#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_menu.py — ghep patch menu (MENU.bytes) vao payload HS2 (Project.Plugins_d).

Van de: moi operand trong IFix la INDEX (declType, param.id, string id, block vm,
method id, field id). Ghep 2 patch khac nhau bat buoc phai REMAP toan bo.

Chien luoc:
  - dst = HS2 (da go guard) — giu nguyen 100% type/method/string/field/block
  - src = MENU.bytes — chi co 1 hook get_frameSynchr
  - Voi moi index src dung trong block, anh xa sang index dst:
      type   -> tim chuoi giong het trong dst.types, khong co thi append
      string -> idem cho dst.strings
      method -> dedupe (declType, name, params, typeArgs) sau khi remap
      field  -> dedupe (isNew, declType, name, ftype, ctor)
      block  -> block moi luon duoc append vao cuoi dst.blocks
  - Hook moi tro vao block vua append

Chay:
    python tools/merge_menu.py <HS2.bytes> <Menu.bytes> <out.bytes>
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(ROOT, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
resd_decrypt = _ns["resd_decrypt"]
resd_encrypt = _ns["resd_encrypt"]
lqmb_parse = _ns["lqmb_parse"]
lqmb_serialize = _ns["lqmb_serialize"]

OP_LDSTR = 0x27
OP_CALLEXTERN = 0x7A
OP_CALL = 0x2D
OP_LDFLD = 0xA7
OP_STFLD = 0x4B
OP_LDSFLD = 0x3C
OP_NEWOBJ = 0x49          # operand = (argc<<16) | ctorMethodId
OP_CASTCLASS = 0x58
OP_CASTCLASS2 = 0x18
OP_CASTCLASS3 = 0x8A
OP_BOX = 0x22
OP_NEWARR = 0x59
OP_LDTOKEN = 0x5E
OP_INITOBJ = 0x97
OP_CONSTRAINED = 0x16

# opcode ma operand LA TYPE INDEX thuan
TYPE_OPS = {OP_CASTCLASS, OP_CASTCLASS2, OP_CASTCLASS3, OP_BOX,
            OP_NEWARR, OP_LDTOKEN, OP_INITOBJ, OP_CONSTRAINED}
FIELD_OPS = {OP_LDFLD, OP_STFLD, OP_LDSFLD}


def load(path: str, res_name: str | None = None):
    blob = open(path, "rb").read()
    res = res_name or os.path.splitext(os.path.basename(path))[0]
    tag, _o, body, enc = resd_decrypt(blob, res)
    return lqmb_parse(body), tag, enc, res


class Remap:
    def __init__(self, dst):
        self.dst = dst
        self.t = {}
        self.s = {}
        self.m = {}
        self.f = {}

    def type_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.t:
            return self.t[i]
        full = src["types"][i]
        for j, x in enumerate(self.dst["types"]):
            if x == full:
                self.t[i] = j
                return j
        self.dst["types"].append(full)
        self.t[i] = len(self.dst["types"]) - 1
        return self.t[i]

    def str_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.s:
            return self.s[i]
        v = src["strings"][i]
        for j, x in enumerate(self.dst["strings"]):
            if x == v:
                self.s[i] = j
                return j
        self.dst["strings"].append(v)
        self.s[i] = len(self.dst["strings"]) - 1
        return self.s[i]

    def _params(self, src, m):
        out = []
        for p in m["params"]:
            q = dict(p)
            if not p["isName"]:
                q["id"] = self.type_(src, p["id"])
            out.append(q)
        return out

    def method_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.m:
            return self.m[i]
        m = src["methods"][i]
        dt = self.type_(src, m["declType"])
        ta = [self.type_(src, x) for x in m["typeArgs"]]
        ps = self._params(src, m)
        for j, cm in enumerate(self.dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [p["id"] for p in cm["params"]] == [p["id"] for p in ps]
                    and [p["isName"] for p in cm["params"]] == [p["isName"] for p in ps]):
                self.m[i] = j
                return j
        self.dst["methods"].append({
            "isGeneric": m["isGeneric"], "declType": dt, "name": m["name"],
            "typeArgs": ta, "params": ps,
        })
        self.m[i] = len(self.dst["methods"]) - 1
        return self.m[i]

    def field_(self, src, i: int) -> int:
        if i < 0:
            return i
        if i in self.f:
            return self.f[i]
        fr = src["fields"][i]
        dt = self.type_(src, fr["declType"])
        ft = self.type_(src, fr["ftype"])
        ct = self.type_(src, fr["ctor"])
        for j, cf in enumerate(self.dst["fields"]):
            if (cf["declType"] == dt and cf["name"] == fr["name"]
                    and cf["isNew"] == fr["isNew"]
                    and (not fr["isNew"] or (cf["ftype"] == ft and cf["ctor"] == ct))):
                self.f[i] = j
                return j
        self.dst["fields"].append({
            "isNew": fr["isNew"], "declType": dt, "name": fr["name"],
            "ftype": ft, "ctor": ct,
        })
        self.f[i] = len(self.dst["fields"]) - 1
        return self.f[i]


def merge(dst_path: str, menu_path: str, out_path: str) -> None:
    dst, dtag, denc, dres = load(dst_path)
    menu, _mt, _me, _mr = load(menu_path)

    print(f"== dst : {os.path.basename(dst_path)}")
    print(f"   types={len(dst['types'])} methods={len(dst['methods'])} "
          f"strings={len(dst['strings'])} fields={len(dst['fields'])} "
          f"blocks={len(dst['blocks'])} hooks={len(dst['interpret'])}")
    print(f"== menu: {os.path.basename(menu_path)}")
    print(f"   types={len(menu['types'])} methods={len(menu['methods'])} "
          f"strings={len(menu['strings'])} fields={len(menu['fields'])} "
          f"blocks={len(menu['blocks'])} hooks={len(menu['interpret'])}")

    if dst["bridge"].split(",")[1].strip() != menu["bridge"].split(",")[1].strip():
        raise SystemExit(f"assembly khac nhau: {dst['bridge']} vs {menu['bridge']}")

    before = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
              len(dst["fields"]), len(dst["blocks"]))

    rp = Remap(dst)
    vmap = {}
    for bi in range(len(menu["blocks"])):
        blk = menu["blocks"][bi]
        vmap[bi] = len(dst["blocks"])
        dst["blocks"].append({
            "instrs": list(blk["instrs"]),
            "handlers": [list(h) for h in blk["handlers"]],
        })
    dst["nextAlloc"] = len(dst["blocks"])

    # remap operand
    for sbi, dbi in vmap.items():
        ins = dst["blocks"][dbi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            code, op = ins[k], ins[k + 1]
            if code == OP_LDSTR:
                ins[k + 1] = rp.str_(menu, op)
            elif code == OP_CALLEXTERN:
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(menu, op & 0xFFFF)
            elif code == OP_NEWOBJ:
                # operand = (argc<<16) | ctorMethodId
                ins[k + 1] = ((op >> 16) << 16) | rp.method_(menu, op & 0xFFFF)
            elif code in FIELD_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.field_(menu, op & 0xFFFF)
            elif code in TYPE_OPS:
                ins[k + 1] = ((op >> 16) << 16) | rp.type_(menu, op & 0xFFFF)
            elif code == OP_CALL:
                tgt = op & 0xFFFF
                if tgt not in vmap:
                    raise SystemExit(f"menu block {sbi} Call vm{tgt} ngoai pham vi")
                ins[k + 1] = ((op >> 16) << 16) | vmap[tgt]

    # field moi (khai trong menu)
    for fr in menu["fields"]:
        rp.field_(menu, menu["fields"].index(fr))

    # hook
    for h in menu["interpret"]:
        m = h["method"]
        dt = rp.type_(menu, m["declType"])
        ps = [dict(p, id=(rp.type_(menu, p["id"]) if not p["isName"] else p["id"]))
              for p in m["params"]]
        ta = [rp.type_(menu, x) for x in m["typeArgs"]]
        # dedupe trong dst
        mi = -1
        for j, cm in enumerate(dst["methods"]):
            if (cm["declType"] == dt and cm["name"] == m["name"]
                    and cm["isGeneric"] == m["isGeneric"]
                    and cm["typeArgs"] == ta
                    and [p["id"] for p in cm["params"]] == [p["id"] for p in ps]):
                mi = j
                break
        if mi < 0:
            dst["methods"].append({
                "isGeneric": m["isGeneric"], "declType": dt, "name": m["name"],
                "typeArgs": ta, "params": ps,
            })
            mi = len(dst["methods"]) - 1
        rec = dst["methods"][mi]
        dst["interpret"].append({
            "method": {
                "isGeneric": rec["isGeneric"], "declType": rec["declType"],
                "name": rec["name"], "typeArgs": list(rec["typeArgs"]),
                "params": [dict(p) for p in rec["params"]],
            },
            "vm": vmap[h["vm"]],
        })
        print(f"   + hook {dst['types'][rec['declType']].split(',')[0]}"
              f"::{rec['name']} -> vm{vmap[h['vm']]}")

    after = (len(dst["types"]), len(dst["methods"]), len(dst["strings"]),
             len(dst["fields"]), len(dst["blocks"]))
    print(f"\n   them: types +{after[0]-before[0]} methods +{after[1]-before[1]} "
          f"strings +{after[2]-before[2]} fields +{after[3]-before[3]} "
          f"blocks +{after[4]-before[4]}")

    body = lqmb_serialize(dst)
    back = lqmb_parse(body)
    assert lqmb_serialize(back) == body, "roundtrip loi"
    assert back["nextAlloc"] == len(back["blocks"])
    for h in back["interpret"]:
        assert 0 <= h["vm"] < len(back["blocks"])

    # Chi verify cac block MOI THEM (block goc do game tu sinh, field id co the
    # vuot bang `fields` — do IFix resolve field theo kieu khac, khong phai loi).
    added = set(vmap.values())
    for bi in sorted(added):
        ins = back["blocks"][bi]["instrs"]
        for k in range(0, len(ins) - 1, 2):
            c, o = ins[k], ins[k + 1]
            if c == OP_CALLEXTERN:
                assert (o & 0xFFFF) < len(back["methods"]), "method idx sai"
            elif c == OP_LDSTR:
                assert o < len(back["strings"]), "string idx sai"
            elif c in FIELD_OPS:
                assert (o & 0xFFFF) < len(back["fields"]), f"field idx sai: {o}"
            elif c == OP_NEWOBJ:
                assert (o & 0xFFFF) < len(back["methods"]), "newobj ctor idx sai"
            elif c in TYPE_OPS:
                assert (o & 0xFFFF) < len(back["types"]), f"type idx sai: {o}"
            elif c == OP_CALL:
                assert (o & 0xFFFF) < len(back["blocks"]), "vm idx sai"
    print("   verify: moi operand cua block moi trong pham vi OK")

    # block goc phai KHONG doi tung i32
    for i in range(before[4]):
        assert back["blocks"][i]["instrs"] == dst["blocks"][i]["instrs"], \
            f"block goc vm{i} bi doi"
    print("   verify: block goc giu nguyen 100%")
    print(f"   body {len(body)} B | hooks {len(back['interpret'])}")

    out = resd_encrypt(body, dres, dtag, denc)
    open(out_path, "wb").write(out)
    print(f"   ghi {out_path} ({len(out)} B)")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("dung: merge_menu.py <HS2.bytes> <Menu.bytes> <out.bytes>")
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
