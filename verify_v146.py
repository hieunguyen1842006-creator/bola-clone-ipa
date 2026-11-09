import tools.merge_menu as M

pf, _, _, _ = M.load('HeroSkin_2_v146.bytes', 'HeroSkin_2')
ins3 = pf['blocks'][3]['instrs']
total = len(ins3) // 2

print(f"VM 3 ops: {total}")
oob = [i for i in range(0, len(ins3), 2) if ins3[i] in (0x48,0x24,0x0D) and ins3[i+1] > 48]
print(f"local OOB: {oob if oob else 'OK'}")
boxed = [i for i in range(0, len(ins3), 2) if ins3[i] == 0x22]
print(f"box ops: {boxed if boxed else 'NONE OK'}")
bad = [i for i in range(0, len(ins3), 2)
       if ins3[i] in (0x7F,0x86,0x5D) and ((i + 2 + ins3[i+1]*2)//2 < 0 or (i + 2 + ins3[i+1]*2)//2 > total-1)]
print(f"bad branches: {bad if bad else 'OK'}")

print()
print("=== appended block ===")
for pc in range(2446, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc+1]
    extra = ''
    rm = arg & 0xFFFF
    if op == M.OP_CALLEXTERN and rm < len(pf['methods']):
        m = pf['methods'][rm]
        t = pf['types'][m['declType']].split(',')[0].split('.')[-1]
        extra = f"-> {t}::{m['name']} (argc {arg>>16})"
    elif op in M.FIELD_OPS and arg < len(pf['fields']):
        extra = "-> " + pf['fields'][arg]['name']
    elif op == M.OP_LDSTR and arg < len(pf['strings']):
        extra = f"-> {repr(pf['strings'][arg])}"
    print(f"pc {pc}: {hex(op)} {arg} {extra}")