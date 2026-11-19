#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ifix_decompile.py — decompile IFix LQMB patch ra C# đọc được.

Không phải decompiler thật (không rebuild C# hợp lệ 100%), mục tiêu là
ĐỌC ĐƯỢC: chia biểu thức theo stack, đặt tên biến, dựng if/while/return,
và chú thích mọi call extern bằng tên method thật.

Dùng:
    python tools/ifix_decompile.py <module.bin> <outdir>
    python tools/ifix_decompile.py <module.bin> <outdir> --only 10,84,1583

Sinh ra:
    <outdir>/index.md            bảng hook + block + độ phức tạp
    <outdir>/block_00010.cs      mỗi hook một file
    <outdir>/all_blocks/         mỗi block 1 file (nếu --all)
    <outdir>/types.txt           bảng type index
    <outdir>/methods.txt         bảng method index
    <outdir>/fields.txt          bảng field index
    <outdir>/strings.txt         bảng string index
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

_src = open(os.path.join(HERE, "verify_swift_logic.py"), encoding="utf-8").read()
_src = _src.split("def main()")[0]
_ns: dict = {}
exec(_src, _ns)
lqmb_parse = _ns["lqmb_parse"]

TABLE = r"D:\FileChuaHack\LQ IOS DATA\opcode_table_lqmb_full.json"
_tbl = json.load(open(TABLE, encoding="utf-8"))
G2N = {int(v): _tbl["names"][int(k)] for k, v in _tbl["std_to_game"].items()}

BRANCH = {"Br", "Brfalse", "Brtrue", "Beq", "Bne_Un", "Bge", "Bgt", "Ble", "Blt",
          "Bge_Un", "Bgt_Un", "Ble_Un", "Blt_Un", "Leave"}
CMP = {"Ceq", "Cgt", "Clt", "Cgt_Un", "Clt_Un", "Cge", "Cle"}
BINOP = {
    "Add": "+", "Sub": "-", "Mul": "*", "Div": "/", "Rem": "%",
    "And": "&", "Or": "|", "Xor": "^", "Shl": "<<", "Shr": ">>",
    "Add_Ovf": "+", "Sub_Ovf": "-", "Mul_Ovf": "*",
    "Add_Ovf_Un": "+", "Sub_Ovf_Un": "-", "Mul_Ovf_Un": "*",
}


class Sym:
    """Một giá trị trên stack."""

    __slots__ = ("expr", "kind")

    def __init__(self, expr: str, kind: str = "val"):
        self.expr = expr
        self.kind = kind        # val | addr | stmt

    def __repr__(self):
        return self.expr


def q(s: str, n: int = 90) -> str:
    if s is None:
        return '""'
    s = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "")
    if len(s) > n:
        s = s[:n] + "…"
    return '"' + s + '"'


class Decomp:
    def __init__(self, pf):
        self.pf = pf
        self.M = pf["methods"]
        self.F = pf["fields"]
        self.S = pf["strings"]
        self.T = pf["types"]
        self.blocks = pf["blocks"]

    # ---------- name resolution ----------
    def tyname(self, idx: int) -> str:
        if 0 <= idx < len(self.T):
            t = self.T[idx].split(",")[0].strip()
            return t
        return "T[%d]" % idx

    def short_ty(self, idx: int) -> str:
        t = self.tyname(idx)
        return t.rsplit(".", 1)[-1] if "." in t else t

    def mname(self, idx: int) -> str:
        if idx >= len(self.M):
            return "BAD_M%d" % idx
        m = self.M[idx]
        return "%s.%s" % (self.short_ty(m["declType"]), m["name"])

    def fname(self, idx: int) -> str:
        if idx >= len(self.F):
            return "BAD_F%d" % idx
        f = self.F[idx]
        return f["name"]

    def sval(self, idx: int):
        return self.S[idx] if idx < len(self.S) else None

    def f32(self, bits: int) -> str:
        import struct
        v = struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]
        if v == int(v) and abs(v) < 1e9:
            return "%df" % int(v)
        return ("%.6g" % v) + "f"

    # ---------- block ----------
    def block(self, bi: int, header_comment: bool = True) -> str:
        blk = self.blocks[bi]
        I = blk["instrs"]
        n = len(I) // 2
        out = []
        stack: list[Sym] = []
        locals_seen = set()
        labels = self.jump_targets(I, n)

        if header_comment:
            out.append("// ──────────────────────────────────────────────────────────")
            out.append("// block %d · %d instructions · handlers=%s" %
                       (bi, n, blk["handlers"] if blk["handlers"] else "none"))
            out.append("// ──────────────────────────────────────────────────────────")

        def emit(line, ind=1):
            out.append("    " * ind + line)

        def pop(kind=None):
            if not stack:
                return Sym("/*stack-underflow*/null")
            return stack.pop()

        def popv():
            s = pop()
            return s.expr if s.expr else "null"

        for i in range(n):
            code, arg = I[i * 2], I[i * 2 + 1]
            nm = G2N.get(code, "op_0x%02x" % code)

            if i in labels:
                emit("L%d:" % i, 0)

            # ---- load ----
            if nm == "Ldloc":
                stack.append(Sym("v%d" % arg))
                locals_seen.add(arg)
            elif nm == "Ldarg":
                stack.append(Sym("a%d" % arg))
            elif nm == "Ldloca":
                stack.append(Sym("&v%d" % arg, "addr"))
                locals_seen.add(arg)
            elif nm == "Ldarga":
                stack.append(Sym("&a%d" % arg, "addr"))
            elif nm == "Ldc_I4":
                stack.append(Sym(str(arg)))
            elif nm == "Ldc_R4":
                stack.append(Sym(self.f32(arg)))
            elif nm == "Ldc_I8":
                stack.append(Sym("%dL" % arg))
            elif nm == "Ldstr":
                stack.append(Sym(q(self.sval(arg))))
            elif nm == "Ldnull":
                stack.append(Sym("null"))
            elif nm == "Ldtype":
                stack.append(Sym("typeof(%s)" % self.tyname(arg)))
            elif nm in ("Ldfld", "Ldsfld"):
                o = popv()
                if nm == "Ldfld":
                    stack.append(Sym("%s.%s" % (o, self.fname(arg))))
                else:
                    stack.append(Sym(self.fname(arg) + "/*static*/"))
            elif nm == "Ldflda":
                o = popv()
                stack.append(Sym("&%s.%s" % (o, self.fname(arg)), "addr"))

            # ---- store ----
            elif nm == "Stloc":
                v = popv()
                emit("v%d = %s;" % (arg, v))
                locals_seen.add(arg)
            elif nm == "Starg":
                v = popv()
                emit("a%d = %s;" % (arg, v))
            elif nm in ("Stfld",):
                val = popv()
                obj = popv()
                emit("%s.%s = %s;" % (obj, self.fname(arg), val))
            elif nm == "Stsfld":
                val = popv()
                emit("%s = %s;  /*static*/" % (self.fname(arg), val))

            # ---- arithmetic ----
            elif nm in BINOP:
                b = popv()
                a = popv()
                stack.append(Sym("(%s %s %s)" % (a, BINOP[nm], b)))
            elif nm == "Neg":
                stack.append(Sym("(-%s)" % popv()))
            elif nm == "Not":
                stack.append(Sym("(~%s)" % popv()))
            elif nm in CMP:
                b = popv()
                a = popv()
                op = {"Ceq": "==", "Cgt": ">", "Clt": "<",
                      "Cgt_Un": ">u", "Clt_Un": "<u",
                      "Cge": ">=", "Cle": "<="}.get(nm, nm)
                stack.append(Sym("(%s %s %s)" % (a, op, b)))

            # ---- conv ----
            elif nm.startswith("Conv_"):
                stack.append(Sym("((%s)%s)" % (nm[5:], popv())))

            # ---- calls ----
            elif nm == "Call":
                vm = arg & 0xFFFF
                argc = arg >> 16
                args = [popv() for _ in range(argc)][::-1]
                res = "/*vm#%d*/(%s)" % (vm, ", ".join(args))
                stack.append(Sym(res))
            elif nm == "CallExtern":
                mi = arg & 0xFFFF
                argc = arg >> 16
                args = [popv() for _ in range(argc)][::-1]
                res = "%s(%s)" % (self.mname(mi), ", ".join(args))
                stack.append(Sym(res))
            elif nm == "Newobj":
                mi = arg & 0xFFFF
                argc = arg >> 16
                args = [popv() for _ in range(argc)][::-1]
                stack.append(Sym("new %s(%s)" % (self.mname(mi), ", ".join(args))))
            elif nm == "Newarr":
                cnt = popv()
                stack.append(Sym("new %s[%s]" % (self.tyname(arg), cnt)))
            elif nm == "Box":
                stack.append(Sym("(object)%s" % popv()))
            elif nm == "Unbox_Any":
                stack.append(Sym("(%s)%s" % (self.tyname(arg), popv())))
            elif nm == "Castclass":
                stack.append(Sym("(%s)%s" % (self.tyname(arg), popv())))
            elif nm == "Isinst":
                stack.append(Sym("(%s as %s)" % (popv(), self.tyname(arg))))

            # ---- array ----
            elif nm == "Ldelem_Ref":
                idx = popv()
                arr = popv()
                stack.append(Sym("%s[%s]" % (arr, idx)))
            elif nm in ("Ldelem_I4", "Ldelem_R4", "Ldelem_U1", "Ldelem_I1"):
                idx = popv()
                arr = popv()
                stack.append(Sym("%s[%s]" % (arr, idx)))
            elif nm == "Stelem_Ref":
                val = popv()
                idx = popv()
                arr = popv()
                emit("%s[%s] = %s;" % (arr, idx, val))
            elif nm in ("Stelem_I4", "Stelem_R4", "Stelem_I1"):
                val = popv()
                idx = popv()
                arr = popv()
                emit("%s[%s] = %s;" % (arr, idx, val))
            elif nm == "Ldlen":
                stack.append(Sym("%s.Length" % popv()))

            # ---- control ----
            elif nm == "Br":
                tgt = i + arg
                emit("goto L%d;   // %d" % (tgt, tgt))
            elif nm in ("Brtrue", "Brfalse"):
                tgt = i + arg
                c = popv()
                emit("if (%s%s) goto L%d;" % ("" if nm == "Brtrue" else "!", c, tgt))
            elif nm in ("Beq", "Bne_Un", "Bge", "Bgt", "Ble", "Blt",
                        "Bge_Un", "Bgt_Un", "Ble_Un", "Blt_Un"):
                tgt = i + arg
                b = popv()
                a = popv()
                op = nm.split("_")[0]
                sym = {"Beq": "==", "Bne": "!=", "Bge": ">=", "Bgt": ">",
                       "Ble": "<=", "Blt": "<"}[op]
                if nm.endswith("_Un"):
                    sym += "u"
                emit("if (%s %s %s) goto L%d;" % (a, sym, b, tgt))
            elif nm == "Switch":
                emit("switch (%s) { /* %d targets */ }" % (popv(), arg))

            # ---- ret ----
            elif nm == "Ret":
                if arg == 1 and stack:
                    emit("return %s;" % popv(), 0)
                else:
                    emit("return;", 0)

            # ---- misc ----
            elif nm == "Pop":
                v = popv()
                if v and v not in ("null",):
                    emit("/*pop*/ %s;" % v)
            elif nm == "Dup":
                if stack:
                    stack.append(Sym(stack[-1].expr))
            elif nm == "Nop":
                pass
            elif nm == "Throw":
                emit("throw %s;" % popv(), 0)
            elif nm == "Rethrow":
                emit("throw;", 0)
            elif nm == "Leave":
                emit("goto L%d; /*leave*/" % (i + arg))
            elif nm == "Initobj":
                emit("&%s ▸ default(%s);" % (popv(), self.tyname(arg)))
            elif nm == "Endfinally":
                emit("/* endfinally */", 0)
            elif nm == "StackSpace":
                pass
            else:
                emit("/*UNK %s %d*/" % (nm, arg))

        if blk["handlers"]:
            out.append("    // handler table: %s" % blk["handlers"])

        return "\n".join(out)

    @staticmethod
    def jump_targets(I, n):
        out = set()
        for i in range(n):
            nm = G2N.get(I[i * 2], "")
            if nm in BRANCH:
                out.add(i + I[i * 2 + 1])
        return out


def dump_tables(pf, outdir):
    D = Decomp(pf)
    with open(os.path.join(outdir, "types.txt"), "w", encoding="utf-8") as f:
        for i in range(len(pf["types"])):
            f.write("%5d  %s\n" % (i, pf["types"][i]))
    with open(os.path.join(outdir, "methods.txt"), "w", encoding="utf-8") as f:
        for i, m in enumerate(pf["methods"]):
            ps = ", ".join(D.tyname(p["id"]) if not p["isName"] else p["name"]
                           for p in m["params"])
            f.write("%5d  %s %s::%s(%s)\n" %
                    (i, D.tyname(m["declType"]), D.short_ty(m["declType"]),
                     m["name"], ps))
    with open(os.path.join(outdir, "fields.txt"), "w", encoding="utf-8") as f:
        for i, fl in enumerate(pf["fields"]):
            f.write("%5d  %-8s %-40s  decl=%s\n" %
                    (i, "NEW" if fl["isNew"] else "", fl["name"],
                     D.tyname(fl["declType"])))
    with open(os.path.join(outdir, "strings.txt"), "w", encoding="utf-8") as f:
        for i, s in enumerate(pf["strings"]):
            f.write("%5d  %s\n" % (i, s))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src = sys.argv[1]
    outdir = sys.argv[2]
    only = None
    do_all = "--all" in sys.argv
    for a in sys.argv[3:]:
        if a.startswith("--only"):
            only = [int(x) for x in a.split("=", 1)[1].split(",")]

    data = open(src, "rb").read()
    pf = lqmb_parse(data)
    os.makedirs(outdir, exist_ok=True)
    os.makedirs(os.path.join(outdir, "all_blocks"), exist_ok=True)

    D = Decomp(pf)
    dump_tables(pf, outdir)

    hooks = {h["vm"]: h for h in pf["interpret"]}
    idx = ["# Decompile — %s" % os.path.basename(src), "",
           "types %d · methods %d · strings %d · fields %d · blocks %d · hooks %d"
           % (len(pf["types"]), len(pf["methods"]), len(pf["strings"]),
              len(pf["fields"]), len(pf["blocks"]), len(pf["interpret"])), "",
           "## Hooks", "", "| vm | method | ins | file |", "|---|---|---|---|"]
    for h in sorted(pf["interpret"], key=lambda x: x["vm"]):
        vm = h["vm"]
        m = h["method"]
        ins = len(pf["blocks"][vm]["instrs"]) // 2
        idx.append("| %d | `%s::%s` | %d | [block_%05d.cs](block_%05d.cs) |"
                   % (vm, D.short_ty(m["declType"]), m["name"], ins, vm, vm))

    targets = only if only is not None else sorted(hooks.keys())
    if do_all and only is None:
        targets = list(range(len(pf["blocks"])))

    for vm in targets:
        body = D.block(vm)
        name = os.path.join(outdir, "block_%05d.cs" % vm)
        hdr = ""
        if vm in hooks:
            m = hooks[vm]["method"]
            hdr = ("// HOOK: %s::%s(%s)\n" %
                   (D.tyname(m["declType"]), m["name"],
                    ", ".join(D.tyname(p["id"]) for p in m["params"] if not p["isName"])))
        with open(name, "w", encoding="utf-8") as f:
            f.write(hdr)
            f.write(body)
            f.write("\n")
        if do_all:
            with open(os.path.join(outdir, "all_blocks", "b%05d.cs" % vm),
                      "w", encoding="utf-8") as f:
                f.write(hdr)
                f.write(body)
                f.write("\n")

    with open(os.path.join(outdir, "index.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(idx) + "\n")

    print("ok: %d block -> %s" % (len(targets), outdir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
