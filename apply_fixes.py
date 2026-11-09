import os
import tools.merge_menu as M

src_path = '_lqdebug/v20_restored/HeroSkin_1.bytes'
out_path = 'HeroSkin_1_patched.bytes'

pf, dtag, denc, dres = M.load(src_path)
ins24 = pf['blocks'][24]['instrs']

# Verify original values before patching
assert ins24[524] == 0x7F and ins24[525] == 553, f"Unexpected pc 524: {ins24[524]}, {ins24[525]}"
assert ins24[2714] == 0x7F and ins24[2715] == 609, f"Unexpected pc 2714: {ins24[2714]}, {ins24[2715]}"
assert ins24[2762] == 0x24 and ins24[2763] == 23, f"Unexpected pc 2762: {ins24[2762]}, {ins24[2763]}"
assert ins24[3326] == 0x7F and ins24[3327] == 10, f"Unexpected pc 3326: {ins24[3326]}, {ins24[3327]}"
assert ins24[3884] == 0x8F and ins24[3885] == 1, f"Unexpected pc 3884: {ins24[3884]}, {ins24[3885]}"
assert ins24[3890] == 0x8F and ins24[3891] == 1, f"Unexpected pc 3890: {ins24[3890]}, {ins24[3891]}"

print("Baseline verification passed!")

# Fix 1: Morph form change - do not skip skin resolution (pc 524)
ins24[525] = 0

# Fix 2: Morph form change - do not skip host player & customization (pc 2714)
ins24[2715] = 0

# Fix 3: SelectedSkin overwrite - store PlayerPrefs into dummy loc90 so loc23 stays skinId (pc 2762)
ins24[2763] = 90

# Fix 4: Billboard - do not skip custom billboard loading (pc 3326)
ins24[3327] = 0

# Fix 5: Personal button - do not force reset personal button to default (pc 3884, 3890)
ins24[3885] = 0
ins24[3891] = 0

# Save patched HeroSkin_1
body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
with open(out_path, 'wb') as f:
    f.write(out)

print(f"Patched HeroSkin_1 written to {out_path}, size = {os.path.getsize(out_path)} bytes")
