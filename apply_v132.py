import os
import tools.merge_menu as M

src_path = '_lqdebug/v20_restored/HeroSkin_1.bytes'
out_path = 'HeroSkin_1_v132.bytes'

pf, dtag, denc, dres = M.load(src_path)

ins13 = pf['blocks'][13]['instrs']
ins24 = pf['blocks'][24]['instrs']

# --- VM 13 Patch: NOP out reset so existing buttons are preserved ---
vm13_count = 0
for pc in range(0, len(ins13), 2):
    if ins13[pc] == 0xA4 and ins13[pc+1] == 1:
        ins13[pc] = 0x8F
        ins13[pc+1] = 0
        vm13_count += 1
print(f"VM 13: patched {vm13_count} reset occurrences to ldc.i4.0")

# --- VM 24: 2-Form Morphing fixes ---
# 1. Do not delete key on first form load (pc 488)
assert ins24[488] == 0x7A and ins24[489] == 66045, f"pc 488: {ins24[488]}, {ins24[489]}"
ins24[488] = 0x67; ins24[489] = 0 # nop DeleteKey

# 2. Do not skip skin resolution on subforms (pc 524)
assert ins24[524] == 0x7F and ins24[525] == 553, f"pc 524: {ins24[524]}, {ins24[525]}"
ins24[525] = 0 # no jump

# 3. Do not XOR skin index when saving SelectedSkin (pc 728..730)
assert ins24[728] == 0x8F and ins24[729] == 1597463007, f"pc 728: {ins24[728]}, {ins24[729]}"
assert ins24[730] == 0x5A and ins24[731] == 0, f"pc 730: {ins24[730]}, {ins24[731]}"
ins24[728] = 0x67; ins24[729] = 0 # nop
ins24[730] = 0x67; ins24[731] = 0 # nop

# 4. Do not skip customization on subforms (pc 2714)
assert ins24[2714] == 0x7F and ins24[2715] == 609, f"pc 2714: {ins24[2714]}, {ins24[2715]}"
ins24[2715] = 0 # no jump

# 5. Do not skip customization if IsAtMyTeam is 0 in practice mode (pc 2742)
assert ins24[2742] == 0x7F and ins24[2743] == 588, f"pc 2742: {ins24[2742]}, {ins24[2743]}"
ins24[2743] = 0 # no jump

# 6. Compute valid global skinId (heroId, loc14) directly into loc23 at pc 2744..2762
assert ins24[2744] == 0x27 and ins24[2745] == 32, f"pc 2744: {ins24[2744]}, {ins24[2745]}"
ins24[2744] = 0x48; ins24[2745] = 4       # ldloc 4 (actor)
ins24[2746] = 0x7A; ins24[2747] = 66017   # call get_ConfigId (heroId)
ins24[2748] = 0x48; ins24[2749] = 14      # ldloc 14 (skinIndex)
ins24[2750] = 0x7A; ins24[2751] = 131567  # call CSkinInfo.GetHeroSkinID
ins24[2752] = 0x24; ins24[2753] = 23      # stloc 23 (loc23 = 15015)
ins24[2754] = 0x67; ins24[2755] = 0       # nop
ins24[2756] = 0x67; ins24[2757] = 0       # nop
ins24[2758] = 0x67; ins24[2759] = 0       # nop
ins24[2760] = 0x67; ins24[2761] = 0       # nop
ins24[2762] = 0x67; ins24[2763] = 0       # nop

# 7. Do not jump to Remove CacheNotifySkinIDMap (pc 2780)
assert ins24[2780] == 0x7F and ins24[2781] == 9, f"pc 2780: {ins24[2780]}, {ins24[2781]}"
ins24[2781] = 0 # no jump to Remove

# 8. Do not skip customization if IsFormOpen is 0 during asset preload (pc 2832)
assert ins24[2832] == 0x7F and ins24[2833] == 543, f"pc 2832: {ins24[2832]}, {ins24[2833]}"
ins24[2833] = 0 # no jump

# 9. Do not skip custom billboard 3D format (pc 3326)
assert ins24[3326] == 0x7F and ins24[3327] == 10, f"pc 3326: {ins24[3326]}, {ins24[3327]}"
ins24[3327] = 0 # no jump

# Save and serialize
body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
with open(out_path, 'wb') as f:
    f.write(out)

print(f"HeroSkin_1_v132 written successfully! Size = {os.path.getsize(out_path)} bytes")
