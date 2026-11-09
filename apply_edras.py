"""
v1.4.7 — Mirror AutoIce byte-for-byte, only change the slot constant.

The VS-screen freeze means our block runs while no battle exists.
My previous version called ActorManager::GetCampHeroActors / GetActor
without null-guarding loc 8 (ActorManager) and without checking
loc 13 / SkillControl — original AutoIce guards ALL of those.

v1.4.7 keeps the exact proven AutoIce shape:
    ldloc 13 / brfalse
    ldloc 13 / ldfld SkillControl / brfalse
    GetSkillSlot(slotType) / brfalse
    IsCDReady / brfalse
    RequestUseSkill()          <-- 0-arg form (argc=1), proven at pc 2440
and only adds the 1->2->3 rotation via PlayerPrefs.
"""
import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v147.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']

LDC_I4 = 0x8F
LDLOC  = 0x48
STLOC  = 0x24
BRT    = 0x7F
BRF    = 0x86
BR     = 0x5D
CALL   = 0x7A
LDFLD  = 0xA7
LDSTR  = 0x27
LDNULL = 0x75
EQ     = 0xA6
RET    = 0xAD

MID_SLOT_GETSLOT = 131141    # SkillComponent::GetSkillSlot (argc 2) - used by AutoIce
MID_IS_CD_READY  = 65606     # SkillSlot::get_IsCDReady (argc 1)
MID_REQ_NOARG    = 65721     # SkillSlot::RequestUseSkill (argc 1) - used by AutoIce

MID_PP_GET = MID_PP_SET = 0
for i, m in enumerate(pf['methods']):
    t = pf['types'][m['declType']].split(',')[0].split('.')[-1]
    if t == 'PlayerPrefs':
        if m['name'] == 'GetInt':
            MID_PP_GET = i
        elif m['name'] == 'SetInt':
            MID_PP_SET = i
assert MID_PP_GET and MID_PP_SET

FLD_SKILL_CONTROL = 19

STR_ENABLED = len(pf['strings']); pf['strings'].append('iFix.Edras.Enabled.v1')
STR_LAST    = len(pf['strings']); pf['strings'].append('iFix.Edras.LastCast.v1')

L_HOST_ROOT = 13      # LActorRoot (set at pc 410, guarded at 2334 by AutoIce)
L_SKILL     = 45
L_LAST      = 48
L_TYPE      = 33

new_ins, fixups, labels = [], [], {}

def emit(op, arg=0):
    new_ins.extend([op, arg]); return len(new_ins) - 2

def call(tok):
    return emit(CALL, tok)

def branch(op, label):
    b = emit(op, 0); fixups.append((b, len(new_ins)//2 - 1, label)); return b

def place(n):
    labels[n] = len(new_ins)//2

# ---- gate: toggle ----
emit(LDSTR, STR_ENABLED); emit(LDC_I4, 0); call((2 << 16) | MID_PP_GET)
branch(BRF, 'END')

# ---- gate: host root (mirrors AutoIce pc 2334..2336) ----
emit(LDLOC, L_HOST_ROOT); branch(BRF, 'END')

# ---- gate: SkillControl not null (mirrors pc 2338..2342) ----
emit(LDLOC, L_HOST_ROOT); emit(LDFLD, FLD_SKILL_CONTROL); branch(BRF, 'END')

# ---- rotation 1 -> 2 -> 3 -> 1 ----
emit(LDSTR, STR_LAST); emit(LDC_I4, 0); call((2 << 16) | MID_PP_GET)
emit(STLOC, L_LAST)

emit(LDC_I4, 1); emit(STLOC, L_TYPE)          # default next = 1
emit(LDLOC, L_LAST); emit(LDC_I4, 1); emit(EQ, 0); branch(BRF, 'CHK2')
emit(LDC_I4, 2); emit(STLOC, L_TYPE); branch(BR, 'CAST')
place('CHK2')
emit(LDLOC, L_LAST); emit(LDC_I4, 2); emit(EQ, 0); branch(BRF, 'CHK3')
emit(LDC_I4, 3); emit(STLOC, L_TYPE); branch(BR, 'CAST')
place('CHK3')
place('CAST')

# ---- slotType: skill 3 -> slot 13, else skill index ----
emit(LDLOC, L_TYPE); emit(LDC_I4, 3); emit(EQ, 0); branch(BRF, 'NOT3')

emit(LDLOC, L_HOST_ROOT); emit(LDFLD, FLD_SKILL_CONTROL)
emit(LDC_I4, 13); call(MID_SLOT_GETSLOT)
branch(BR, 'SLOT')

place('NOT3')
emit(LDLOC, L_HOST_ROOT); emit(LDFLD, FLD_SKILL_CONTROL)
emit(LDLOC, L_TYPE); call(MID_SLOT_GETSLOT)

place('SLOT')
emit(STLOC, L_SKILL)

# ---- slot null / CD guards (mirror pc 2354..2362) ----
emit(LDLOC, L_SKILL); branch(BRF, 'END')
emit(LDLOC, L_SKILL); call(MID_IS_CD_READY); branch(BRF, 'END')

# ---- fire (proven 0-arg form) ----
emit(LDLOC, L_SKILL); call(MID_REQ_NOARG)

# ---- remember rotation ----
emit(LDSTR, STR_LAST); emit(LDLOC, L_TYPE); call((2 << 16) | MID_PP_SET)

place('END')
emit(RET, 0)

for b, from_op, lab in fixups:
    new_ins[b + 1] = labels[lab] - from_op - 1

# ---- validations ----
oob = [i for i in range(0, len(new_ins), 2)
       if new_ins[i] in (LDLOC, STLOC, 0x0D) and new_ins[i+1] > 48]
assert not oob, f"local OOB: {oob}"
assert not [i for i in range(0, len(new_ins), 2) if new_ins[i] == 0x22], "box present"

ins3[2444] = BR; ins3[2445] = 0
ins3.extend(new_ins)

print(f"appended {len(new_ins)//2} ops; VM3 now {len(ins3)//2} ops")
print(f"labels: {labels}")

body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
open(OUT, 'wb').write(out)
print(f"{OUT} = {os.path.getsize(OUT)} bytes")