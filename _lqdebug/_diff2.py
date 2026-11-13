import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import tools.merge_menu as M

def loadres(path):
    blob = open(path, 'rb').read()
    tag, o, body, enc = M.resd_decrypt(blob, 'HeroSkin_1')
    return M.lqmb_parse(body)

a = loadres('_lqharvest/work/HeroSkin_1_skin.bytes')
b = loadres('_lqdebug/v20_restored/HeroSkin_1.bytes')

OPS = {0x27:"Ldstr",0x7A:"CallExtern",0x2D:"Call",0xA7:"Ldfld",0x4B:"Stfld",
       0x3C:"Ldsfld",0x49:"Newobj",0x86:"Brfalse",0x7F:"Brtrue",0x5D:"Br",
       0x67:"Nop",0xA4:"Ldarg",0x48:"Ldloc",0x24:"Stloc",0x8F:"Ldc_I4",
       0x0D:"Ldloca",0xAD:"Ret",0xA6:"Ceq",0x2B:"Beq",0x92:"StackSpace",
       0x5A:"Xor",0x11:"Ble",0x5E:"Ble_Un"}

def desc(pf, op, arg):
    e = ''
    if op == 0x7A and (arg & 0xFFFF) < len(pf['methods']):
        m = pf['methods'][arg&0xFFFF]
        e = pf['types'][m['declType']].split(',')[0].split('.')[-1] + "::" + m['name']
    elif op in M.FIELD_OPS and (arg & 0xFFFF) < len(pf['fields']):
        f = pf['fields'][arg&0xFFFF]
        e = pf['types'][f['declType']].split(',')[0].split('.')[-1] + "::" + f['name']
    elif op == 0x27 and arg < len(pf['strings']):
        e = repr(pf['strings'][arg])
    return e

for label, pf in (("SKIN", a), ("V20", b)):
    ins = pf['blocks'][24]['instrs']
    print(f"===== {label} VM24 pc 1360..1390 =====")
    for i in range(1360, 1392, 2):
        op, arg = ins[i], ins[i+1]
        print(f"pc {i}: {OPS.get(op,hex(op)):<11} {arg:<8} {desc(pf,op,arg)}")