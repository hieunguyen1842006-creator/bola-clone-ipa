"""
verify_region.py - relative stack verifier for the Edras region in vm3.

The LQMB payload does not store method return types, so an absolute
whole-function stack model is not decidable from this file alone.
What IS decidable, and what actually caused the freeze, is the region's
own net stack effect:

  - entering at op 1163 with depth 0
  - every path must leave at depth 0 (Ret, or a branch past the region)
  - depth must never go negative
  - depth at each op must agree across all paths

That is exactly the property v1.5.1 violated: three RequestUseSkill bools
left on the stack before Ret.

Usage: python tools/verify_region.py <file.bytes> [start_op] [end_op]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import merge_menu as M

HERE = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    r"D:\FileChuaHack\LQ IOS DATA\opcode_table_lqmb_full.json",
    os.path.join(HERE, "..", "LQ IOS DATA", "opcode_table_lqmb_full.json"),
]
TABLE = next(p for p in _CANDIDATES if os.path.exists(p))
_t = json.load(open(TABLE, encoding="utf-8"))
NAMES = _t["names"]
G2N = {int(v): NAMES[int(k)] for k, v in _t["std_to_game"].items()}

# (pops, pushes) for ops whose effect is fixed regardless of signature.
FIXED = {
    "Nop": (0, 0), "Ret": (0, 0), "Break": (0, 0), "StackSpace": (0, 0),
    "Ldloc": (0, 1), "Stloc": (1, 0), "Ldarg": (0, 1), "Starg": (1, 0),
    "Ldloca": (0, 1), "Ldarga": (0, 1),
    "Ldnull": (0, 1), "Ldc_I4": (0, 1), "Ldc_I8": (0, 1),
    "Ldc_R4": (0, 1), "Ldc_R8": (0, 1),
    "Dup": (1, 2), "Pop": (1, 0),
    "Ldstr": (0, 1), "Ldfld": (1, 1), "Ldflda": (1, 1), "Stfld": (2, 0),
    "Ldsfld": (0, 1), "Ldsflda": (0, 1), "Stsfld": (1, 0),
    "Ldlen": (1, 1), "Newarr": (1, 1), "Ldelema": (2, 1),
    "Ldelem_Ref": (2, 1), "Ldelem_I4": (2, 1), "Ldelem_U4": (2, 1),
    "Ldelem_I8": (2, 1), "Ldelem_I": (2, 1), "Ldelem_R4": (2, 1),
    "Stelem_Ref": (3, 0), "Stelem_I4": (3, 0), "Stelem_I8": (3, 0),
    "Stelem_I": (3, 0), "Stelem_R4": (3, 0),
    "Box": (1, 1), "Unbox": (1, 1), "Unbox_Any": (1, 1),
    "Castclass": (1, 1), "Isinst": (1, 1),
    "Initobj": (1, 0), "Cpobj": (2, 0), "Ldobj": (1, 1), "Stobj": (2, 0),
    "Add": (2, 1), "Sub": (2, 1), "Mul": (2, 1), "Div": (2, 1),
    "Rem": (2, 1), "And": (2, 1), "Or": (2, 1), "Xor": (2, 1),
    "Shl": (2, 1), "Shr": (2, 1), "Shr_Un": (2, 1),
    "Neg": (1, 1), "Not": (1, 1),
    "Ceq": (2, 1), "Cgt": (2, 1), "Cgt_Un": (2, 1),
    "Clt": (2, 1), "Clt_Un": (2, 1),
    "Conv_I1": (1, 1), "Conv_I2": (1, 1), "Conv_I4": (1, 1),
    "Conv_I8": (1, 1), "Conv_R4": (1, 1), "Conv_R8": (1, 1),
    "Conv_U1": (1, 1), "Conv_U2": (1, 1), "Conv_U4": (1, 1),
    "Conv_U8": (1, 1), "Conv_I": (1, 1), "Conv_U": (1, 1),
    "Conv_R_Un": (1, 1), "Conv_Ovf_I_Un": (1, 1), "Conv_Ovf_U_Un": (1, 1),
    "Conv_Ovf_U4_Un": (1, 1),
    "Throw": (1, 0), "Rethrow": (0, 0),
    "Ldtoken": (0, 1), "Ldtype": (0, 1),
    "Ldftn": (0, 1), "Ldvirtftn": (0, 1),
    "Endfinally": (0, 0), "Endfilter": (1, 0),
}
COND_BR = {"Brfalse", "Brtrue", "Beq", "Bge", "Bgt", "Ble", "Blt",
           "Bne_Un", "Bge_Un", "Bgt_Un", "Ble_Un", "Blt_Un"}
UNCOND_BR = {"Br", "Leave"}

# Methods known to return void, by name. Everything else assumed to push 1.
VOID_NAMES = {
    "SetInt", "SetFloat", "SetString", "SetActive", "Destroy", "AddComponent",
    ".ctor", "set_renderMode", "set_sortingOrder", "SetParent",
}


def verify(pf, vm, start, end):
    ins = pf["blocks"][vm]["instrs"]
    n = len(ins) // 2
    methods = pf["methods"]

    def effect(i):
        code, arg = ins[i * 2], ins[i * 2 + 1]
        name = G2N.get(code, "op_0x%02x" % code)
        if name in ("Call", "CallExtern", "Callvirt", "Callvirtvirt"):
            pops = arg >> 16
            mi = arg & 0xFFFF
            void = False
            if mi < len(methods):
                mname = methods[mi]["name"]
                void = mname in VOID_NAMES or mname.startswith("set_")
            return name, arg, pops, (0 if void else 1)
        if name == "Newobj":
            return name, arg, arg >> 16, 1
        if name in COND_BR:
            return name, arg, 1, 0      # conditional branch pops its condition
        if name in UNCOND_BR:
            return name, arg, 0, 0
        if name in FIXED:
            p, q = FIXED[name]
            return name, arg, p, q
        return name, arg, 0, 0

    depth = {}
    work = [(start, 0)]
    errors = []
    while work:
        i, d = work.pop()
        if i < 0 or i > n:
            errors.append(f"op {i}: pc out of range")
            continue
        if i >= end or i == n:
            if d != 0:
                errors.append(f"exit at op {i} with depth {d} (expected 0)")
            continue
        if i in depth:
            if depth[i] != d:
                errors.append(f"op {i}: depth {d} conflicts with {depth[i]}")
            continue
        depth[i] = d
        name, arg, pops, pushes = effect(i)
        nd = d - pops
        if nd < 0:
            errors.append(f"op {i} {name}: underflow ({d} - {pops})")
            continue
        nd += pushes
        if name == "Ret":
            if nd != 0:
                errors.append(f"op {i} Ret at depth {nd} (expected 0)")
            continue
        if name in COND_BR:
            work.append((i + 1 + arg, nd))
            work.append((i + 1, nd))
            continue
        if name in UNCOND_BR:
            work.append((i + 1 + arg, nd))
            continue
        work.append((i + 1, nd))
    return errors, depth


def main():
    path = sys.argv[1]
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1163
    end = int(sys.argv[3]) if len(sys.argv) > 3 else 1223
    res = "HeroSkin_1" if "HeroSkin_1" in path else "HeroSkin_2"
    pf, _t, _e, _r = M.load(path, res)
    errs, depth = verify(pf, 3, start, end)
    print(f"{path}  region op {start}..{end-1}  ({len(depth)} ops reached)")
    if errs:
        print(f"FAIL - {len(errs)} problem(s):")
        for e in errs[:30]:
            print("   ", e)
        return 1
    print("PASS - region is stack-neutral on every path")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
