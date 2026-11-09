"""
v1.5.2 - fix freeze at VS screen + make Edras actually Edras-only.

ROOT CAUSE OF THE FREEZE (verified by disassembling both files):
  SkillSlot::RequestUseSkill returns bool. Every call site in the baseline
  is followed by `Pop` (op 1221, 944, 494). v1.5.1 emitted three
  RequestUseSkill calls with NO Pop, so three bools stayed on the
  evaluation stack and `Ret` at op 1211 ran with a 3-slot imbalance.
  IFix throws -> freeze at the VS screen.
  FIX: emit `Pop` after each RequestUseSkill.

SECOND BUG (design, not crash):
  v1.5.1 never checked the hero. plan_edras.py designed a ConfigId == 595
  guard but apply_edras.py dropped it, so the toggle fired on ANY hero.
  FIX: guard on loc13 (ActorLinker) -> get_ConfigId == 595.

Region budget: pc 2326..2444 = 60 ops. New code uses 57 (56 + Ret).

File stays 69208 bytes; no type/method/field/block added.
"""
import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v152.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']
ORIG_SIZE = len(ins3)

# --- opcodes (game byte values, from opcode_table_lqmb_full.json) ---
NOP    = 0x67
LDSTR  = 0x27
LDC_I4 = 0x8F
LDLOC  = 0x48
STLOC  = 0x24
LDFLD  = 0xA7
BRF    = 0x86
BR     = 0x5D
CALLX  = 0x7A
POP    = 0x80
CEQ    = 0xA6
RET    = 0xAD

# --- method tokens: low16 = method index, high16 = argc ---
TOK_PP_GET    = 131117   # PlayerPrefs::GetInt        (m45,  argc 2)
TOK_SLOT_GET  = 131141   # SkillComponent::GetSkillSlot (m69, argc 2)
TOK_CD_READY  = 65606    # SkillSlot::get_IsCDReady   (m70,  argc 1)
TOK_CAST      = 65721    # SkillSlot::RequestUseSkill (m185, argc 1)
TOK_CONFIGID  = 65706    # ActorLinker::get_ConfigId  (m170, argc 1)

FLD_SKILL_CONTROL = 19   # ActorLinker::SkillControl
L_ROOT  = 13             # ActorLinker (host player handle)
L_SKILL = 45             # scratch, already used by baseline

EDRAS_ID = 595
STR_ID = 35

REGION_START = 2326
REGION_END   = 2444
REGION_OPS   = (REGION_END - REGION_START) // 2 + 1     # 60

# ---------- size-neutral toggle string ----------
STR_OLD = 'iFix.bundle.obfuscation.v1'
STR_NEW = 'iFix.Edras.AutoCombo.On.v1'
assert len(STR_OLD) == len(STR_NEW), f"{len(STR_OLD)} vs {len(STR_NEW)}"
assert pf['strings'][STR_ID] == STR_OLD, pf['strings'][STR_ID]
for b, blk in enumerate(pf['blocks']):
    ins = blk['instrs']
    for pc in range(0, len(ins), 2):
        if ins[pc] == LDSTR and ins[pc + 1] == STR_ID:
            raise SystemExit(f"string {STR_ID} used by vm{b} op{pc//2} - abort")
pf['strings'][STR_ID] = STR_NEW
print(f"string {STR_ID}: {STR_OLD!r} -> {STR_NEW!r}")

# ---------- retarget the mid-region entry (same as v1.5.1) ----------
assert ins3[2114] == BR and (2114 + 2 + ins3[2115] * 2) == 2328, "unexpected 2114 branch"
ins3[2115] = 105          # 2114 + 2 + 210 = 2326
print("op 2114: br -> 2328 retargeted to 2326")

# ---------- region must have no other external entries ----------
BRANCHES = (0x7F, 0x86, 0x5D)
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in BRANCHES:
        tgt = pc + 2 + arg * 2
        inside = REGION_START < tgt <= REGION_END
        src_inside = REGION_START <= pc <= REGION_END
        if inside and not src_inside:
            raise SystemExit(f"external branch into region: op {pc//2} -> {tgt//2}")
assert ins3[REGION_END] == RET
print(f"region op {REGION_START//2}..{REGION_END//2} ({REGION_OPS} ops) clean")

# ---------- build ----------
code, fixups, labels = [], [], {}

def emit(op, arg=0):
    code.extend([op, arg]); return len(code) - 2

def branch(op, label):
    b = emit(op, 0)
    fixups.append((b, len(code) // 2 - 1, label))
    return b

def place(n):
    labels[n] = len(code) // 2

# 1. toggle
emit(LDSTR, STR_ID)
emit(LDC_I4, 0)
emit(CALLX, TOK_PP_GET)
branch(BRF, 'END')

# 2. host actor linker present
emit(LDLOC, L_ROOT); branch(BRF, 'END')
emit(LDLOC, L_ROOT); emit(LDFLD, FLD_SKILL_CONTROL); branch(BRF, 'END')

# 3. only when the hero really is Edras (ConfigId 595)
emit(LDLOC, L_ROOT)
emit(CALLX, TOK_CONFIGID)
emit(LDC_I4, EDRAS_ID)
emit(CEQ, 0)
branch(BRF, 'END')

# 4. skill 1 -> 2 -> EX3, first ready one only, Pop the bool result
for idx, slot_type in ((1, 1), (2, 2), (3, 13)):
    nxt = f'N{idx}'
    emit(LDLOC, L_ROOT); emit(LDFLD, FLD_SKILL_CONTROL)
    emit(LDC_I4, slot_type); emit(CALLX, TOK_SLOT_GET)
    emit(STLOC, L_SKILL)
    emit(LDLOC, L_SKILL); branch(BRF, nxt)
    emit(LDLOC, L_SKILL); emit(CALLX, TOK_CD_READY); branch(BRF, nxt)
    emit(LDLOC, L_SKILL); emit(CALLX, TOK_CAST)
    emit(POP, 0)                      # <-- the freeze fix
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

# ---------- validations ----------
oob = [i for i in range(0, len(ins3), 2)
       if ins3[i] in (LDLOC, STLOC, 0x0D) and ins3[i + 1] > 48]
assert not oob, f"local OOB {oob}"

total = len(ins3) // 2
for pc in range(0, len(ins3), 2):
    op = ins3[pc]; arg = ins3[pc + 1]
    if op in BRANCHES:
        t = (pc + 2 + arg * 2) // 2
        assert 0 <= t <= total, f"branch OOR op {pc//2} -> {t}"

boxed = [i for i in range(REGION_START, len(ins3), 2) if ins3[i] == 0x22]
assert not boxed, f"box in region {boxed}"

# every RequestUseSkill in the region must be followed by Pop
for pc in range(REGION_START, REGION_END, 2):
    if ins3[pc] == CALLX and (ins3[pc + 1] & 0xFFFF) == 185:
        nxt = ins3[pc + 2]
        assert nxt == POP, f"op {pc//2}: RequestUseSkill not followed by Pop (0x{nxt:02x})"
print("stack balance: every RequestUseSkill followed by Pop")

print(f"block size unchanged: {ORIG_SIZE} B / {ORIG_SIZE // 2} ops")

body = M.lqmb_serialize(pf)
blob = M.resd_encrypt(body, dres, dtag, denc)
open(OUT, 'wb').write(blob)
print(f"{OUT} = {os.path.getsize(OUT)} bytes")
