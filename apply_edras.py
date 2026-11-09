"""
v1.5.0 - SIZE-NEUTRAL Edras: overwrite in place, file stays 69208 bytes.

Evidence: every build v1.4.0..v1.4.7 APPENDED opcodes to HeroSkin_2 (69208 ->
69688/70168/70216...). All of them froze at the VS screen EVEN WITH THE
TOGGLE OFF, where the appended block only does
    ldstr / ldc.i4.0 / call GetInt / brfalse / ret
which cannot freeze. So the freeze is caused by the patch SHAPE changing,
not by the combo logic.

This build never changes the file size:
  - overwrite AutoIce region pc 2328..2444 (59 ops) in place
  - pad with nop
  - add no new strings (reuse 'iFix.AutoIce.Enabled.v1' as Edras toggle)
  - no new methods / fields / blocks
"""
import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v150.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']

ORIG_SIZE = len(ins3)
REGION_START = 2328

LDC_I4 = 0x8F
LDLOC  = 0x48
LDLOCA = 0x0D
STLOC  = 0x24
BRF    = 0x86
BRT    = 0x7F
BR     = 0x5D
CALL   = 0x7A
LDFLD  = 0xA7
LDSTR  = 0x27
NOP    = 0x67
EQ     = 0xA6
RET    = 0xAD

TOK_PP_GET   = 131117   # PlayerPrefs::GetInt (argc 2)
TOK_SLOT_GET = 131141   # SkillComponent::GetSkillSlot (argc 2) - AutoIce proven
TOK_CD_READY = 65606    # SkillSlot::get_IsCDReady (argc 1)
TOK_CAST     = 65721    # SkillSlot::RequestUseSkill (argc 1) - AutoIce proven

STR_TOGGLE = 63
assert pf['strings'][STR_TOGGLE] == 'iFix.AutoIce.Enabled.v1'

FLD_SKILL_CONTROL = 19
L_HOST_LINKER = 19
L_HOST_ROOT   = 13
L_SKILL       = 45

# region ends right before the final ret at 2444
REGION_END = 2444
REGION_OPS = (REGION_END - REGION_START) // 2 + 1

# ---- prove no OUTSIDE branch lands inside the region (except its start) ----
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in (BRT, BRF, BR):
        tgt = pc + 2 + arg * 2
        if REGION_START < tgt <= REGION_END and not (REGION_START <= pc <= REGION_END):
            raise SystemExit(f"external branch into region: pc {pc} -> {tgt}")
print(f"region pc {REGION_START}..{REGION_END} = {REGION_OPS} ops, self-contained OK")
assert ins3[REGION_END] == RET, f"region end not ret: {hex(ins3[REGION_END])}"

# ---------------- build code ----------------
code, fixups, labels = [], [], {}

def emit(op, arg=0):
    code.extend([op, arg]); return len(code) - 2

def branch(op, label):
    b = emit(op, 0); fixups.append((b, len(code) // 2 - 1, label)); return b

def place(n):
    labels[n] = len(code) // 2

# gate 1 toggle
emit(LDSTR, STR_TOGGLE)
emit(LDC_I4, 0)
emit(CALL, TOK_PP_GET)
branch(BRF, 'END')

# gate 2 hostPlayer linker present
emit(LDLOC, L_HOST_LINKER)
branch(BRF, 'END')

# gate 3 LActorRoot present
emit(LDLOC, L_HOST_ROOT)
branch(BRF, 'END')

# gate 4 SkillControl present
emit(LDLOC, L_HOST_ROOT)
emit(LDFLD, FLD_SKILL_CONTROL)
branch(BRF, 'END')

# rotation 1 -> 2 -> 3 -> 1
for idx, slot_type in ((1, 1), (2, 2), (3, 13)):
    nxt = f'TRY{idx}'
    nxtend = f'NEXT{idx}'
    emit(LDLOC, L_HOST_ROOT)
    emit(LDFLD, FLD_SKILL_CONTROL)
    emit(LDC_I4, slot_type)
    emit(CALL, TOK_SLOT_GET)
    emit(STLOC, L_SKILL)
    emit(LDLOC, L_SKILL)
    branch(BRF, nxtend)
    emit(LDLOC, L_SKILL)
    emit(CALL, TOK_CD_READY)
    branch(BRF, nxtend)
    emit(LDLOC, L_SKILL)
    emit(CALL, TOK_CAST)
    branch(BR, 'END')
    place(nxtend)

place('END')
emit(RET, 0)

used = len(code) // 2
print(f"Edras code = {used} ops (limit {REGION_OPS})")
assert used <= REGION_OPS, f"does not fit: {used} > {REGION_OPS}"

while len(code) < REGION_OPS * 2:
    code.extend([NOP, 0])

# resolve branches to absolute pcs
for b, from_op, lab in fixups:
    abs_from = REGION_START + from_op * 2
    abs_tgt = REGION_START + labels[lab] * 2
    code[b + 1] = (abs_tgt - abs_from - 2) // 2

ins3[REGION_START:REGION_START + REGION_OPS * 2] = code
assert len(ins3) == ORIG_SIZE, f"size changed: {len(ins3)} != {ORIG_SIZE}"

oob = [i for i in range(0, len(ins3), 2)
       if ins3[i] in (LDLOC, STLOC, LDLOCA) and ins3[i + 1] > 48]
assert not oob, f"local OOB: {oob}"

# branches all in range (past-end == implicit return, as in original)
total = len(ins3) // 2
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in (BRT, BRF, BR):
        t = (pc + 2 + arg * 2) // 2
        assert 0 <= t <= total, f"branch OOR at pc {pc}"

print(f"block size UNCHANGED: {ORIG_SIZE} bytes / {ORIG_SIZE // 2} ops")

body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
open(OUT, 'wb').write(out)
print(f"{OUT} = {os.path.getsize(OUT)} bytes (baseline 69208)")