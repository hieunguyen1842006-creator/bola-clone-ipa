import os
import tools.merge_menu as M

src_path = '_lqdebug/v20_restored/HeroSkin_1.bytes'
out_path = 'HeroSkin_1_v131.bytes'

pf, dtag, denc, dres = M.load(src_path)

ins23 = pf['blocks'][23]['instrs']
ins24 = pf['blocks'][24]['instrs']

# --- Verify VM 23 pre-conditions ---
assert ins23[1314] == 0x48 and ins23[1315] == 31, f"VM 23 at 1314: {ins23[1314]}, {ins23[1315]}"
assert ins23[1316] == 0x48 and ins23[1317] == 27, f"VM 23 at 1316: {ins23[1316]}, {ins23[1317]}"
assert ins23[1318] == 0x7A and ins23[1319] == 131083, f"VM 23 at 1318: {ins23[1318]}, {ins23[1319]}"

# --- Verify VM 24 pre-conditions ---
assert ins24[434] == 0x48 and ins24[435] == 8, f"VM 24 at 434: {ins24[434]}, {ins24[435]}"
assert ins24[524] == 0x7F and ins24[525] == 553, f"VM 24 at 524: {ins24[524]}, {ins24[525]}"
assert ins24[526] == 0x48 and ins24[527] == 8, f"VM 24 at 526: {ins24[526]}, {ins24[527]}"
assert ins24[2714] == 0x7F and ins24[2715] == 609, f"VM 24 at 2714: {ins24[2714]}, {ins24[2715]}"
assert ins24[2744] == 0x27 and ins24[2745] == 32, f"VM 24 at 2744: {ins24[2744]}, {ins24[2745]}"
assert ins24[3780] == 0x48 and ins24[3781] == 60, f"VM 24 at 3780: {ins24[3780]}, {ins24[3781]}"
assert ins24[3782] == 0xA7 and ins24[3783] == 192, f"VM 24 at 3782: {ins24[3782]}, {ins24[3783]}"
assert ins24[3874] == 0x7F and ins24[3875] == 3, f"VM 24 at 3874: {ins24[3874]}, {ins24[3875]}"

print("All baseline assertions PASSED!")

# === FIX 1: 2-Form Morphing (Liliana Fox, Volkath Horse, etc.) ===
# VM 23: save skinIndex under hero key loc31 (nop out concat with prefabName)
ins23[1316] = 0x67; ins23[1317] = 0
ins23[1318] = 0x67; ins23[1319] = 0

# VM 24: check HasKey for loc7 (hero key) instead of loc8 (subprefab key)
ins24[435] = 7

# VM 24: do not skip skin resolution on subprefabs
ins24[525] = 0

# VM 24: read skinIndex from loc7 (hero key) instead of loc8
ins24[527] = 7

# VM 24: do not skip customization on subprefabs
ins24[2715] = 0

# === FIX 2: Kill Notification Billboard Banner ===
# Replace obfuscated read at pc 2744..2762 with: CSkinInfo::GetHeroSkinID(heroId, skinIndex) -> loc23
# 2744: ldloc 4 (hero)
ins24[2744] = 0x48; ins24[2745] = 4
# 2746: call get_ConfigId (66017)
ins24[2746] = 0x7A; ins24[2747] = 66017
# 2748: ldloc 14 (skinIndex)
ins24[2748] = 0x48; ins24[2749] = 14
# 2750: call CSkinInfo::GetHeroSkinID (131567)
ins24[2750] = 0x7A; ins24[2751] = 131567
# 2752: stloc 23
ins24[2752] = 0x24; ins24[2753] = 23
# 2754..2762: nop out remaining 5 instructions
ins24[2754] = 0x67; ins24[2755] = 0
ins24[2756] = 0x67; ins24[2757] = 0
ins24[2758] = 0x67; ins24[2759] = 0
ins24[2760] = 0x67; ins24[2761] = 0
ins24[2762] = 0x67; ins24[2763] = 0

# VM 24: also do not skip custom billboard 3D format at pc 3326
ins24[3327] = 0

# === FIX 3: Personal Button Auto-Switch & Retention ===
# Pass loc23 (modded skin ID) to IsOpen / IsSpriteAssetBundleReady instead of hostPlayer.PersonalButtonID
ins24[3780] = 0x48; ins24[3781] = 23
ins24[3782] = 0x67; ins24[3783] = 0

# If skin has NO custom button (loc86 == 0), jump 21 instructions to 3918:
# SKIP the reset, keep previous buttons!
# If skin HAS custom button (loc86 == 1): falls through to Init() and applies new buttons!
ins24[3875] = 21

# Serialize and encrypt
body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
with open(out_path, 'wb') as f:
    f.write(out)

print(f"HeroSkin_1_v131 generated successfully! Size = {os.path.getsize(out_path)} bytes")
