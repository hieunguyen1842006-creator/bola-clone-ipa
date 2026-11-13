import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import tools.merge_menu as M

# M.load lay res name tu ten file; dung ham truc tiep de chon res "HeroSkin_1"
def loadres(path):
    blob = open(path, 'rb').read()
    tag, o, body, enc = M.resd_decrypt(blob, 'HeroSkin_1')
    return M.lqmb_parse(body)

a = loadres('_lqharvest/work/HeroSkin_1_skin.bytes')
b = loadres('_lqdebug/v20_restored/HeroSkin_1.bytes')

# so sanh block VM24 (ActorLinker VisionUtility::ChangeMeshCallBack)
ia = a['blocks'][24]['instrs']
ib = b['blocks'][24]['instrs']
print("VM24 lens:", len(ia)//2, len(ib)//2, "equal:", ia == ib)
if ia != ib:
    n = min(len(ia), len(ib))
    diffs = []
    for i in range(0, n, 2):
        if ia[i:i+2] != ib[i:i+2]:
            diffs.append(i//2)
    print("diff instr count:", len(diffs))
    print("first 40 diffs (pc):", diffs[:40])

# so sanh VM13
ia13 = a['blocks'][13]['instrs']
ib13 = b['blocks'][13]['instrs']
print("VM13 equal:", ia13 == ib13, "lens", len(ia13)//2, len(ib13)//2)

# so sanh VM20 (OnPrepareFight) va VM23
for vm in (20, 23, 39):
    va = a['blocks'][vm]['instrs']
    vb = b['blocks'][vm]['instrs']
    print(f"VM{vm}: equal={va==vb} lens {len(va)//2}/{len(vb)//2}")