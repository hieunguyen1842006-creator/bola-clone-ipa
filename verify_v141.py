import tools.merge_menu as M

pf, _, _, _ = M.load('HeroSkin_2_v141.bytes', 'HeroSkin_2')
ins3 = pf['blocks'][3]['instrs']
print(f"VM 3 len: {len(ins3)}")
for pc in range(2446, min(len(ins3), 2684), 2):
    op = ins3[pc]
    arg = ins3[pc+1]
    extra = ''
    rm = arg & 0xFFFF
    if op == M.OP_CALLEXTERN and rm < len(pf['methods']):
        m = pf['methods'][rm]
        t = pf['types'][m['declType']].split(',')[0].split('.')[-1]
        mname = m['name']
        extra = f"-> {t}::{mname}"
    elif op in M.FIELD_OPS and arg < len(pf['fields']):
        extra = "-> " + pf['fields'][arg]['name']
    elif op == M.OP_LDSTR and arg < len(pf['strings']):
        s = pf['strings'][arg]
        extra = f"-> {repr(s)}"
    print(f"pc {pc}: op={hex(op)} arg={arg} {extra}")
