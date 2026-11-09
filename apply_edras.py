import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v141.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']

# --- Opcodes ---
NOP     = 0x67
LDC_I4  = 0x8F
LDLOC   = 0x48
STLOC   = 0x24
BRT     = 0x7F
BRF     = 0x86
BR      = 0x5D
CALL    = 0x7A
LDFLD   = 0xA7
LDSTR   = 0x27
BOX     = 0x22
RET     = 0xAD
EQ      = 0xA6

# --- Method ids ---
MID_GET_HOSTPLAYER  = 59
MID_LINKER_HASVALUE = 60
MID_LINKER_HANDLE   = 61
MID_ROOT_HASVALUE   = 64
MID_ROOT_HANDLE     = 65
MID_IS_DEAD         = 66
MID_GET_LOCATION    = 67
MID_GET_ENEMY_CAMP  = 73
MID_GET_CAMP_HEROES = 74
MID_LINKER_ITEM     = 75
MID_GET_SKILL_SLOT  = 79
MID_IS_CD_READY     = 70
MID_GET_CONFIG_ID   = 170
MID_REQUEST_SKILL_3 = 192
MID_ROOT_OBJID      = 191
MID_LINKER_COUNT    = 186

MID_PLAYERPREFS_GET = 0
MID_PLAYERPREFS_SET = 0
for i, m in enumerate(pf['methods']):
    t = pf['types'][m['declType']].split(',')[0].split('.')[-1]
    if t == 'PlayerPrefs':
        if m['name'] == 'GetInt':
            MID_PLAYERPREFS_GET = i
        elif m['name'] == 'SetInt':
            MID_PLAYERPREFS_SET = i
assert MID_PLAYERPREFS_GET, "PlayerPrefs::GetInt not found"
assert MID_PLAYERPREFS_SET, "PlayerPrefs::SetInt not found"

FLD_SKILL_CONTROL = 19

STR_EDRAS_ENABLED = len(pf['strings'])
pf['strings'].append('iFix.Edras.Enabled.v1')
STR_EDRAS_LAST = len(pf['strings'])
pf['strings'].append('iFix.Edras.LastCast.v1')

# Locals
L_HOST_LINKER = 47
L_HOST_ROOT   = 13
L_HOST_HANDLE = 21   # PoolObjHandle`1[LActorRoot]
L_ENEMY_CAMP  = 49
L_ENEMY_LIST  = 50
L_ENEMY_LINK  = 25
L_ENEMY_HANDLE= 26   # PoolObjHandle`1[LActorRoot]
L_ENEMY_OBJID = 52
L_SKILL_SLOT  = 45
L_LAST_CAST   = 53
L_SKILL_TYPE  = 55

new_ins = []
fixups = []
labels = {}

def emit(op, arg=0):
    new_ins.extend([op, arg])
    return len(new_ins) - 2

def call(argc, mid):
    return emit(CALL, (argc << 16) | mid)

def branch(op, label_name):
    byte_idx = emit(op, 0)
    fixups.append((byte_idx, len(new_ins) // 2 - 1, label_name))
    return byte_idx

def place_label(name):
    labels[name] = len(new_ins) // 2

# ============================================
# 1. Edras enabled check
emit(LDSTR, STR_EDRAS_ENABLED)
emit(LDC_I4, 0)
call(2, MID_PLAYERPREFS_GET)
branch(BRF, 'L_END')

# 2. hostLogic null check
emit(LDLOC, 9)
branch(BRF, 'L_END')

# 3. get_hostPlayer -> ActorLinker
emit(LDLOC, 9)
call(1, MID_GET_HOSTPLAYER)
emit(STLOC, L_HOST_LINKER)
emit(LDLOC, L_HOST_LINKER)
branch(BRF, 'L_END')

# 4. HasValue check
emit(LDLOC, L_HOST_LINKER)
emit(BOX, 17)
call(1, MID_LINKER_HASVALUE)
branch(BRF, 'L_END')

# 5. get_handle -> LActorRoot
emit(LDLOC, L_HOST_LINKER)
emit(BOX, 17)
call(1, MID_LINKER_HANDLE)
emit(STLOC, L_HOST_ROOT)
emit(LDLOC, L_HOST_ROOT)
branch(BRF, 'L_END')

# 6. ConfigId == 595 (via ActorLinker::get_ConfigId)
emit(LDLOC, L_HOST_LINKER)
emit(BOX, 17)
call(1, MID_GET_CONFIG_ID)
emit(LDC_I4, 595)
emit(EQ, 0)
branch(BRF, 'L_END')

# 7. Check IsDeadState on host
# host loc 13 is LActorRoot. get_handle returns PoolObjHandle.
# ldfld ActorControl on PoolObjHandle works via implicit deref (as seen in AutoIce pc 2394)
emit(LDLOC, L_HOST_ROOT)
call(1, MID_ROOT_HANDLE)
emit(STLOC, L_HOST_HANDLE)
emit(LDLOC, L_HOST_HANDLE)
emit(LDFLD, 18)      # ActorControl
emit(CALL, (1 << 16) | MID_IS_DEAD)
branch(BRT, 'L_END')

# 8. Get enemy camp + heroes list
emit(LDLOC, 9)
call(1, MID_GET_ENEMY_CAMP)
emit(STLOC, L_ENEMY_CAMP)
emit(LDLOC, 8)       # ActorManager
emit(LDLOC, L_ENEMY_CAMP)
call(2, MID_GET_CAMP_HEROES)
emit(STLOC, L_ENEMY_LIST)
emit(LDLOC, L_ENEMY_LIST)
branch(BRF, 'L_END')

# 9. Get Count and check > 0
emit(LDLOC, L_ENEMY_LIST)
call(1, MID_LINKER_COUNT)
emit(LDC_I4, 0)
emit(EQ, 0)
branch(BRT, 'L_END')

# 10. Get first enemy (index 0)
emit(LDLOC, L_ENEMY_LIST)
emit(LDC_I4, 0)
call(2, MID_LINKER_ITEM)
emit(STLOC, L_ENEMY_LINK)
emit(LDLOC, L_ENEMY_LINK)
branch(BRF, 'L_END')

# 11. HasValue check
emit(LDLOC, L_ENEMY_LINK)
emit(BOX, 17)
call(1, MID_LINKER_HASVALUE)
branch(BRF, 'L_END')

# 12. Get handle -> PoolObjHandle[LActorRoot]
emit(LDLOC, L_ENEMY_LINK)
emit(BOX, 17)
call(1, MID_LINKER_HANDLE)
emit(STLOC, L_ENEMY_HANDLE)
emit(LDLOC, L_ENEMY_HANDLE)
branch(BRF, 'L_END')

# 13. IsDeadState check
emit(LDLOC, L_ENEMY_HANDLE)
emit(LDFLD, 18)
emit(CALL, (1 << 16) | MID_IS_DEAD)
branch(BRT, 'L_END')

# 14. Get target objId (via implicit deref PoolObjHandle -> LActorRoot -> get_ObjID)
emit(LDLOC, L_ENEMY_HANDLE)
emit(CALL, (1 << 16) | MID_ROOT_OBJID)
emit(STLOC, L_ENEMY_OBJID)

# 15. Load last cast index
emit(LDSTR, STR_EDRAS_LAST)
emit(LDC_I4, 0)
emit(CALL, (2 << 16) | MID_PLAYERPREFS_GET)
emit(STLOC, L_LAST_CAST)

# 16. Compute next skill (rotation 1 -> 2 -> 3 -> 1)
emit(LDC_I4, 1)
emit(STLOC, L_SKILL_TYPE)
emit(LDLOC, L_LAST_CAST)
emit(LDC_I4, 1)
emit(EQ, 0)
branch(BRF, 'L_CHK_2')
emit(LDC_I4, 2)
emit(STLOC, L_SKILL_TYPE)
branch(BR, 'L_CAST')
place_label('L_CHK_2')
emit(LDLOC, L_LAST_CAST)
emit(LDC_I4, 2)
emit(EQ, 0)
branch(BRF, 'L_CHK_3')
emit(LDC_I4, 3)
emit(STLOC, L_SKILL_TYPE)
branch(BR, 'L_CAST')
place_label('L_CHK_3')
place_label('L_CAST')

# 17. Get skill slot
# If nextSkill == 3, slotType = 13; else slotType = nextSkill
emit(LDLOC, L_SKILL_TYPE)
emit(LDC_I4, 3)
emit(EQ, 0)
branch(BRF, 'L_NOT3')
# nextSkill == 3: use slotType 13
emit(LDLOC, L_HOST_ROOT)
emit(LDFLD, FLD_SKILL_CONTROL)
emit(LDC_I4, 13)
emit(CALL, (2 << 16) | MID_GET_SKILL_SLOT)
branch(BR, 'L_SLOT_LOADED')
place_label('L_NOT3')
# nextSkill != 3: use slotType = nextSkill
emit(LDLOC, L_HOST_ROOT)
emit(LDFLD, FLD_SKILL_CONTROL)
emit(LDLOC, L_SKILL_TYPE)
emit(CALL, (2 << 16) | MID_GET_SKILL_SLOT)
place_label('L_SLOT_LOADED')

emit(STLOC, L_SKILL_SLOT)
emit(LDLOC, L_SKILL_SLOT)
branch(BRF, 'L_END')

# 18. Check IsCDReady
emit(LDLOC, L_SKILL_SLOT)
emit(CALL, (1 << 16) | MID_IS_CD_READY)
branch(BRF, 'L_END')

# 19. Call RequestUseSkill(mode=1, objId, slotType)
emit(LDLOC, L_SKILL_SLOT)
emit(LDC_I4, 1)
emit(LDLOC, L_ENEMY_OBJID)
emit(LDLOC, L_SKILL_TYPE)
emit(CALL, (4 << 16) | MID_REQUEST_SKILL_3)

# 20. Save last cast
emit(LDSTR, STR_EDRAS_LAST)
emit(LDLOC, L_SKILL_TYPE)
emit(CALL, (2 << 16) | MID_PLAYERPREFS_SET)

place_label('L_END')
emit(RET, 0)

# Fix up branch targets
for byte_idx, from_op, label_name in fixups:
    target_op = labels[label_name]
    new_ins[byte_idx + 1] = target_op - from_op - 1

# Append to VM 3
assert ins3[2444] == RET, f"Expected ret at pc 2444, got {hex(ins3[2444])}"
ins3[2444] = BR
ins3[2445] = 0
ins3.extend(new_ins)

print(f"VM 3 new length: {len(ins3)} bytes ({len(ins3) // 2} ops)")
print(f"Appended {len(new_ins)} bytes ({len(new_ins) // 2} ops)")
print(f"Labels: {labels}")

# Serialize and encrypt
body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
with open(OUT, 'wb') as f:
    f.write(out)

print(f"{OUT} written! Size = {os.path.getsize(OUT)} bytes")
