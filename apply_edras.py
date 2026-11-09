"""
v1.5.1 - fixes the two real bugs that made v1.5.0 freeze.

BUG A (stack corruption at region entry):
  Original pc 2326 = `ldstr 'iFix.AutoIce.Enabled.v1'` and my v1.5.0 started
  overwriting at 2328 -> the leftover `ldstr` pushed a string, then my
  `PlayerPrefs::GetInt(argc=2)` popped (string, string) -> underflow ->
  IFix exception -> freeze at VS screen.
  FIX: start overwrite at 2326 (region is 2326..2444 = 60 ops).

BUG B (branch lands inside the new code):
  pc 2114: `br 106` -> 2328, i.e. it enters the region MID-WAY.
  With new code at 2326, that entry has no string on the stack.
  FIX: retarget 2114 -> 2326 (offset 105).

Also gives Edras its OWN toggle:
  string 40 'iFix.bundle.guard.v1' (20 chars, referenced by NO block) is
  replaced in-place by 'iFix.Edras.Toggle.v1' (20 chars) -> file size unchanged.

File remains exactly 69208 bytes; no type/method/field/block added.
"""
import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v151.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']
ORIG_SIZE = len(ins3)

LDC_I4 = 0x8F
LDLOC  = 0x48
STLOC  = 0x24
BRF    = 0x86
BR     = 0x5D
CALL   = 0x7A
LDFLD  = 0xA7
LDSTR  = 0x27
NOP    = 0x67
RET    = 0xAD

TOK_PP_GET   = 131117    # PlayerPrefs::GetInt (argc 2)
TOK_SLOT_GET = 131141    # SkillComponent::GetSkillSlot (argc 2)
TOK_CD_READY = 65606     # SkillSlot::get_IsCDReady (argc 1)
TOK_CAST     = 65721     # SkillSlot::RequestUseSkill (argc 1)

FLD_SKILL_CONTROL = 19
L_ROOT  = 13
L_SKILL = 45

REGION_START = 2326
REGION_END   = 2444
REGION_OPS   = (REGION_END - REGION_START) // 2 + 1     # 60

# ---------- give Edras its own toggle string (same length, size-neutral) ----------
STR_ID  = 35
STR_OLD = 'iFix.bundle.obfuscation.v1'
STR_NEW = 'iFix.Edras.AutoCombo.On.v1'
assert len(STR_OLD) == len(STR_NEW), f"{len(STR_OLD)} vs {len(STR_NEW)}"
assert pf['strings'][STR_ID] == STR_OLD

# prove the string is referenced by no block
for b, blk in enumerate(pf['blocks']):
    ins = blk['instrs']
    for pc in range(0, len(ins), 2):
        if ins[pc] == LDSTR and ins[pc + 1] == STR_ID:
            raise SystemExit(f"string {STR_ID} is used by vm{b} pc{pc} - abort")
pf['strings'][STR_ID] = STR_NEW
print(f"string {STR_ID}: {STR_OLD!r} -> {STR_NEW!r} (same length, size-neutral)")

# ---------- BUG B: retarget the mid-region entry ----------
assert ins3[2114] == BR and (2114 + 2 + ins3[2115] * 2) == 2328, "unexpected 2114 branch"
ins3[2115] = 105          # 2114 + 2 + 210 = 2326
print("pc 2114: br -> 2328 retargeted to 2326")

# ---------- verify region self-contained for all other entries ----------
BRANCHES = (0x7F, 0x86, 0x5D)
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in BRANCHES:
        tgt = pc + 2 + arg * 2
        inside = REGION_START < tgt <= REGION_END
        src_inside = REGION_START <= pc <= REGION_END
        if inside and not src_inside:
            raise SystemExit(f"external branch into region: pc {pc} -> {tgt}")
print(f"region pc {REGION_START}..{REGION_END} ({REGION_OPS} ops) has no other entries")
assert ins3[REGION_END] == RET

# ---------- build Edras combo ----------
code, fixups, labels = [], [], {}

def emit(op, arg=0):
    code.extend([op, arg]); return len(code) - 2

def branch(op, label):
    b = emit(op, 0); fixups.append((b, len(code) // 2 - 1, label)); return b

def place(n):
    labels[n] = len(code) // 2

emit(LDSTR, STR_ID)
emit(LDC_I4, 0)
emit(CALL, TOK_PP_GET)
branch(BRF, 'END')

emit(LDLOC, L_ROOT); branch(BRF, 'END')
emit(LDLOC, L_ROOT); emit(LDFLD, FLD_SKILL_CONTROL); branch(BRF, 'END')

for idx, slot_type in ((1, 1), (2, 2), (3, 13)):
    nxt = f'N{idx}'
    emit(LDLOC, L_ROOT); emit(LDFLD, FLD_SKILL_CONTROL)
    emit(LDC_I4, slot_type); emit(CALL, TOK_SLOT_GET)
    emit(STLOC, L_SKILL)
    emit(LDLOC, L_SKILL); branch(BRF, nxt)
    emit(LDLOC, L_SKILL); emit(CALL, TOK_CD_READY); branch(BRF, nxt)
    emit(LDLOC, L_SKILL); emit(CALL, TOK_CAST)
    branch(BR, 'END')
    place(nxt)

place('END')
emit(RET, 0)

used = len(code) // 2
print(f"Edras code {used} ops (limit {REGION_OPS})")
assert used <= REGION_OPS, f"does not fit: {used} > {REGION_OPS}"
while len(code) < REGION_OPS * 2:
    code.extend([NOP, 0])

for b, from_op, lab in fixups:
    abs_from = REGION_START + from_op * 2
    abs_tgt = REGION_START + labels[lab] * 2
    code[b + 1] = (abs_tgt - abs_from - 2) // 2

ins3[REGION_START:REGION_START + REGION_OPS * 2] = code
assert len(ins3) == ORIG_SIZE, f"size changed {len(ins3)} != {ORIG_SIZE}"

# ---------- final validations ----------
oob = [i for i in range(0, len(ins3), 2)
       if ins3[i] in (LDLOC, STLOC, 0x0D) and ins3[i + 1] > 48]
assert not oob, f"local OOB {oob}"

total = len(ins3) // 2
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in BRANCHES:
        t = (pc + 2 + arg * 2) // 2
        assert 0 <= t <= total, f"branch OOR pc {pc} -> {t}"

boxed = [i for i in range(REGION_START, len(ins3), 2) if ins3[i] == 0x22]
assert not boxed, f"box in region {boxed}"

print(f"block size unchanged: {ORIG_SIZE} B / {ORIG_SIZE // 2} ops")

body = M.lqmb_serialize(pf)
blob = M.resd_encrypt(body, dres, dtag, denc)
open(OUT, 'wb').write(blob)
print(f"{OUT} = {os.path.getsize(OUT)} bytes")
