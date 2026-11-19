#!/usr/bin/env python3
"""Liet ke moi overload GetComponent/AddComponent trong cac payload da chay tren may."""
import os
import sys
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_menu as mm  # noqa: E402

RES = os.path.join(os.path.dirname(HERE), "Resources")


def lq2_entries(blob):
    out = []
    off = 8
    cnt = struct.unpack_from("<I", blob, 4)[0]
    for _ in range(cnt):
        nl = blob[off]
        off += 1
        name = blob[off:off + nl].decode()
        off += nl
        sz = struct.unpack_from("<I", blob, off)[0]
        off += 4
        out.append((name, blob[off:off + sz]))
        off += sz
    return out


def scan(payload):
    hits = []
    for blk in payload["blocks"]:
        ins = blk["instrs"]
        for k in range(0, len(ins) - 1, 2):
            if ins[k] != mm.OP_CALLEXTERN:
                continue
            midx = ins[k + 1] & 0xFFFF
            if midx >= len(payload["methods"]):
                continue
            m = payload["methods"][midx]
            if m["name"] in ("GetComponent", "AddComponent", "GetComponentInChildren"):
                t = payload["types"][m["declType"]].split(",")[0]
                args = "".join(payload["types"][p["id"]].split(",")[0] + ";"
                               for p in m["params"] if not p["isName"])
                targs = "".join(payload["types"][x].split(",")[0] + ";"
                                for x in m["typeArgs"])
                hits.append((t, m["name"], args, targs, ins[k + 1] >> 16,
                             m["isGeneric"]))
    return hits


if __name__ == "__main__":
    for fn in sorted(os.listdir(RES)):
        if not fn.endswith(".bytes"):
            continue
        path = os.path.join(RES, fn)
        try:
            blob = open(path, "rb").read()
            if blob[:4] == b"LQ2\x00":
                for name, data in lq2_entries(blob):
                    res = name[:-6]
                    _, _, body, _ = mm.resd_decrypt(data, res)
                    p = mm.lqmb_parse(body)
                    h = scan(p)
                    if h:
                        print(f"--- {fn} :: {name} ({len(h)} hits)")
                        for x in h[:12]:
                            print("   ", x)
            else:
                _, _, body, _ = mm.resd_decrypt(blob, fn[:-6])
                p = mm.lqmb_parse(body)
                h = scan(p)
                if h:
                    print(f"--- {fn} ({len(h)} hits)")
                    for x in h[:12]:
                        print("   ", x)
        except Exception as exc:
            print(f"--- {fn}: SKIP {exc}")
