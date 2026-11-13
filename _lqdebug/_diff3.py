import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import tools.merge_menu as M

def loadres(path):
    blob = open(path, 'rb').read()
    tag, o, body, enc = M.resd_decrypt(blob, 'HeroSkin_1')
    return M.lqmb_parse(body)

OPS = {0x27:"Ldstr",0x7A:"CallExtern",0x2D:"Call",0xA7:"Ldfld",0x4B:"Stfld",
       0x3C:"Ldsfld",0x49:"Newobj",0x86:"Brfalse",0x7F:"Brtrue",0x5D:"Br",
       0x67:"Nop",0xA4:"Ldarg",0x48:"Ldloc",0x24:"Stloc",0x8F:"Ldc_I4",
       0x0D:"Ldloca",0xAD:"Ret",0xA6:"Ceq",0x2B:"Beq",0x92:"StackSpace",0x5A:"Xor"}

def desc(pf, op, arg):
    if op == 0x7A and (arg & 0xFFFF) < len(pf['methods']):
        m = pf['methods'][arg&0xFFFF]
        return pf['types'][m['declType']].split(',')[0].split('.')[-1] + "::" + m['name']
    elif op in M.FIELD_OPS and (arg & 0xFFFF) < len(pf['fields']):
        f = pf['fields'][arg&0xFFFF]
        return pf['types'][f['declType']].split(',')[0].split('.')[-1] + "::" + f['name']
    elif op == 0x27 and arg < len(pf['strings']):
        return repr(pf['strings'][arg])
    return ''

for label, path in (("SKIN(v13)", '_lqharvest/work/HeroSkin_1_skin.bytes'),
                    ("V20(current)", '_lqdebug/v20_restored/HeroSkin_1.bytes')):
    pf = loadres(path)
    ins = pf['blocks'][24]['instrs']
    print(f"\n===== {label} VM24 pc 2740..2770 =====")
    for i in range(2740, 2770, 2):
        op, arg = ins[i], ins[i+1]
        print(f"pc {i}: {OPS.get(op,hex(op)):<11} {arg:<8} {desc(pf,op,arg)}")