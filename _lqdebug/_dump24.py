import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import tools.merge_menu as M

pf, _, _, _ = M.load('_lqdebug/v20_restored/HeroSkin_1.bytes')
ins = pf['blocks'][24]['instrs']

OPS = {0x27:"Ldstr",0x7A:"CallExtern",0x2D:"Call",0xA7:"Ldfld",0x4B:"Stfld",
       0x3C:"Ldsfld",0x49:"Newobj",0x58:"Castclass",0x22:"Box",0x59:"Newarr",
       0x5E:"Ldtoken",0x97:"Initobj",0x16:"Constrained",0x86:"Brfalse",
       0x7F:"Brtrue",0x5D:"Br",0x67:"Nop",0xA4:"Ldarg",0x48:"Ldloc",0x24:"Stloc",
       0x8F:"Ldc_I4",0x0D:"Ldloca",0xAD:"Ret",0xA6:"Ceq",0x2B:"Beq",0x80:"Pop",
       0x5A:"Xor",0x4D:"Ldind_I4",0x92:"StackSpace",0x3F:"Clt",0x0B:"Sub"}

def dump(a, b):
    for pc in range(a, b, 2):
        op = ins[pc]; arg = ins[pc+1]
        extra = ''
        if op == 0x7A and (arg & 0xFFFF) < len(pf['methods']):
            m = pf['methods'][arg&0xFFFF]
            extra = "-> " + pf['types'][m['declType']].split(',')[0].split('.')[-1] + "::" + m['name']
        elif op in M.FIELD_OPS and (arg & 0xFFFF) < len(pf['fields']):
            f = pf['fields'][arg&0xFFFF]
            extra = "-> " + pf['types'][f['declType']].split(',')[0].split('.')[-1] + "::" + f['name']
        elif op == 0x27 and arg < len(pf['strings']):
            extra = f"-> {pf['strings'][arg]!r}"
        print(f"pc {pc}: {OPS.get(op,hex(op)):<11} {arg:<8} {extra}")

if __name__ == "__main__":
    dump(int(sys.argv[1]), int(sys.argv[2]))