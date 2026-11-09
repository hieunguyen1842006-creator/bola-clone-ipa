import tools.merge_menu as M

base, _, _, _ = M.load('_lqdebug/v20_restored/HeroSkin_2.bytes')
new, _, _, _ = M.load('HeroSkin_2_v151.bytes', 'HeroSkin_2')

print(f"types/strings/methods/fields/blocks/hooks identical: "
      f"{base['types']==new['types']} {len(base['strings'])}->{len(new['strings'])} "
      f"{len(base['methods'])}->{len(new['methods'])} {len(base['fields'])}->{len(new['fields'])} "
      f"{len(base['blocks'])}->{len(new['blocks'])} {len(base['interpret'])}->{len(new['interpret'])}")

diffs = [i for i,(a,b) in enumerate(zip(base['blocks'], new['blocks']))
         if a['instrs'] != b['instrs'] or a['handlers'] != b['handlers']]
print(f"blocks difF: {diffs}")

a = base['blocks'][3]['instrs']; b = new['blocks'][3]['instrs']
print(f"vm3 len {len(a)} -> {len(b)}")
ch = [pc for pc in range(0, len(a), 2) if a[pc:pc+2] != b[pc:pc+2]]
print(f"changed pc count {len(ch)}, min {min(ch)}, max {max(ch)}")

# string diffs
sd = [(i, base['strings'][i], new['strings'][i])
      for i in range(len(base['strings'])) if base['strings'][i] != new['strings'][i]]
print(f"string diffs: {sd}")

print()
print("=== new region dump ===")
for pc in range(2320, len(b), 2):
    if pc < 2326:
        continue
    op = b[pc]; arg = b[pc+1]
    ex = ''
    rm = arg & 0xFFFF
    if op == 0x7A and rm < len(new['methods']):
        m = new['methods'][rm]
        tn = new['types'][m['declType']].split(',')[0].split('.')[-1]
        ex = f"-> {tn}::{m['name']} argc={arg>>16}"
    elif op in (0xA7,) and arg < len(new['fields']):
        ex = "-> " + new['fields'][arg]['name']
    elif op == 0x27 and arg < len(new['strings']):
        ex = f"-> {new['strings'][arg]!r}"
    print(f"pc {pc}: {hex(op)} {arg} {ex}")