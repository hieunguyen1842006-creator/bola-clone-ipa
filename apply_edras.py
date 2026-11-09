"""
v1.4.6 - TRUE ROOT CAUSE FOUND.

Old code did:  ldloc <ActorLinker local>  +  box System.Byte(type 17)
               -> call ActorLinker::get_HasValue / get_handle / get_ConfigId

type 17 is System.Byte, NOT ActorLinker. Boxing as Byte then calling an
ActorLinker instance method -> invalid cast -> IFix exception -> game freeze.

The game itself always uses:  ldloca <ActorLinker local>  (opcode 0x0D)
(see VM 3 pc 1316/1322, VM 14 pc 88, VM 15 pc 732).

Fix: replace every  ldloc+box  with  ldloca. No boxing at all.
"""
import os
import tools.merge_menu as M

SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'
OUT = 'HeroSkin_2_v146.bytes'

pf, dtag, denc, dres = M.load(SRC)
ins3 = pf['blocks'][3]['instrs']

LDC_I4 = 0x8F
LDLOC  = 0x48
LDLOCA = 0x0D
STLOC  = 0x24
BRT    = 0x7F
BRF    = 0x86
BR     = 0x5D
CALL   = 0x7A
LDFLD  = 0xA7
LDSTR  = 0x27
RET    = 0xAD
EQ     = 0xA6

MID_GET_HOSTPLAYER  = 59
MID_LINKER_HASVALUE = 60
MID_LINKER_HANDLE   = 61
MID_ROOT_HANDLE     = 65
MID_IS_DEAD         = 66
MID_GET_ENEMY_CAMP  = 73
MID_GET_CAMP_HEROES = 74
MID_LINKER_ITEM     = 75
MID_GET_SKILL_SLOT  = 79
MID_IS_CD_READY     = 70
MID_GET_CONFIG_ID   = 170
MID_REQUEST_SKILL_3 = 192
MID_ROOT_OBJID      = 191
MID_LINKER_COUNT    = 186

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

L_HOST_LINKER  = 47
L_HOST_ROOT    = 13
L_HOST_HANDLE  = 21
L_ENEMY_CAMP   = 33
L_ENEMY_LIST   = 24
L_ENEMY_LINK   = 25
L_ENEMY_HANDLE = 26
L_ENEMY_OBJID  = 34
L_SKILL_SLOT   = 45
L_LAST_CAST    = 48
L_SKILL_TYPE   = 33

new_ins, fixups, labels = [], [], {}

def emit(op, arg=0):
    new_ins.extend([op, arg]); return len(new_ins) - 2

def call(argc, mid):
    return emit(CALL, (argc << 16) | mid)

def branch(op, label):
    b = emit(op, 0); fixups.append((b, len(new_ins)//2 - 1, label)); return b

def place_label(n):
    labels[n] = len(new_ins)//2

def push_linker(loc):
    """Reference a struct-wrapped ActorLinker local exactly like the game does."""
    emit(LDLOCA, loc)
    return 1  # argc counts 'this'

# 1 toggle
emit(LDSTR, STR_ENABLED); emit(LDC_I4, 0); call(2, MID_PP_GET); branch(BRF, 'L_END')

# 2 hostLogic
emit(LDLOC, 9); branch(BRF, 'L_END')

# 3 get_hostPlayer
emit(LDLOC, 9); call(1, MID_GET_HOSTPLAYER); emit(STLOC, L_HOST_LINKER)
emit(LDLOC, L_HOST_LINKER); branch(BRF, 'L_END')

# 4 HasValue  (ldloca, argc=1)
push_linker(L_HOST_LINKER); call(1, MID_LINKER_HASVALUE); branch(BRF, 'L_END')

# 5 get_handle -> LActorRoot
push_linker(L_HOST_LINKER); call(1, MID_LINKER_HANDLE); emit(STLOC, L_HOST_ROOT)
emit(LDLOC, L_HOST_ROOT); branch(BRF, 'L_END')

# 6 ConfigId == 595
push_linker(L_HOST_LINKER); call(1, MID_GET_CONFIG_ID)
emit(LDC_I4, 595); emit(EQ, 0); branch(BRF, 'L_END')

# 7 host dead?
emit(LDLOC, L_HOST_ROOT); call(1, MID_ROOT_HANDLE); emit(STLOC, L_HOST_HANDLE)
emit(LDLOC, L_HOST_HANDLE); emit(LDFLD, 18)
emit(CALL, (1 << 16) | MID_IS_DEAD); branch(BRT, 'L_END')

# 8 enemy list
emit(LDLOC, 9); call(1, MID_GET_ENEMY_CAMP); emit(STLOC, L_ENEMY_CAMP)
emit(LDLOC, 8); emit(LDLOC, L_ENEMY_CAMP); call(2, MID_GET_CAMP_HEROES)
emit(STLOC, L_ENEMY_LIST); emit(LDLOC, L_ENEMY_LIST); branch(BRF, 'L_END')

# 9 count>0
emit(LDLOC, L_ENEMY_LIST); call(1, MID_LINKER_COUNT)
emit(LDC_I4, 0); emit(EQ, 0); branch(BRT, 'L_END')

# 10 first enemy
emit(LDLOC, L_ENEMY_LIST); emit(LDC_I4, 0); call(2, MID_LINKER_ITEM)
emit(STLOC, L_ENEMY_LINK); emit(LDLOC, L_ENEMY_LINK); branch(BRF, 'L_END')

# 11 HasValue
push_linker(L_ENEMY_LINK); call(1, MID_LINKER_HASVALUE); branch(BRF, 'L_END')

# 12 handle
push_linker(L_ENEMY_LINK); call(1, MID_LINKER_HANDLE); emit(STLOC, L_ENEMY_HANDLE)
emit(LDLOC, L_ENEMY_HANDLE); branch(BRF, 'L_END')

# 13 dead?
emit(LDLOC, L_ENEMY_HANDLE); emit(LDFLD, 18)
emit(CALL, (1 << 16) | MID_IS_DEAD); branch(BRT, 'L_END')

# 14 objId
emit(LDLOC, L_ENEMY_HANDLE); emit(CALL, (1 << 16) | MID_ROOT_OBJID)
emit(STLOC, L_ENEMY_OBJID)

# 15 last cast
emit(LDSTR, STR_LAST); emit(LDC_I4, 0); call(2, MID_PP_GET); emit(STLOC, L_LAST_CAST)

# 16 rotation
emit(LDC_I4, 1); emit(STLOC, L_SKILL_TYPE)
emit(LDLOC, L_LAST_CAST); emit(LDC_I4, 1); emit(EQ, 0); branch(BRF, 'L_CHK2')
emit(LDC_I4, 2); emit(STLOC, L_SKILL_TYPE); branch(BR, 'L_CAST')
place_label('L_CHK2')
emit(LDLOC, L_LAST_CAST); emit(LDC_I4, 2); emit(EQ, 0); branch(BRF, 'L_CHK3')
emit(LDC_I4, 3); emit(STLOC, L_SKILL_TYPE); branch(BR, 'L_CAST')
place_label('L_CHK3')
place_label('L_CAST')

# 17 slot
emit(LDLOC, L_SKILL_TYPE); emit(LDC_I4, 3); emit(EQ, 0); branch(BRF, 'L_NOT3')
emit(LDLOC, L_HOST_ROOT); emit(LDFLD, FLD_SKILL_CONTROL); emit(LDC_I4, 13)
emit(CALL, (2 << 16) | MID_GET_SKILL_SLOT); branch(BR, 'L_SLOT')
place_label('L_NOT3')
emit(LDLOC, L_HOST_ROOT); emit(LDFLD, FLD_SKILL_CONTROL); emit(LDLOC, L_SKILL_TYPE)
emit(CALL, (2 << 16) | MID_GET_SKILL_SLOT)
place_label('L_SLOT')
emit(STLOC, L_SKILL_SLOT); emit(LDLOC, L_SKILL_SLOT); branch(BRF, 'L_END')

# 18 CD
emit(LDLOC, L_SKILL_SLOT); emit(CALL, (1 << 16) | MID_IS_CD_READY); branch(BRF, 'L_END')

# 19 cast
emit(LDLOC, L_SKILL_SLOT); emit(LDC_I4, 1); emit(LDLOC, L_ENEMY_OBJID)
emit(LDLOC, L_SKILL_TYPE); emit(CALL, (4 << 16) | MID_REQUEST_SKILL_3)

# 20 save
emit(LDSTR, STR_LAST); emit(LDLOC, L_SKILL_TYPE); call(2, MID_PP_SET)

place_label('L_END')
emit(RET, 0)

for b, from_op, lab in fixups:
    new_ins[b + 1] = labels[lab] - from_op - 1

# validations
assert not [1 for i in range(0, len(new_ins), 2)
            if new_ins[i] in (0x48, 0x24, 0x0D) and new_ins[i+1] > 48], "local OOB"
assert not [1 for i in range(0, len(new_ins), 2) if new_ins[i] == 0x22], "box still present"

ins3[2444] = BR; ins3[2445] = 0
ins3.extend(new_ins)

print(f"VM 3 = {len(ins3)//2} ops; appended {len(new_ins)//2} ops")
body = M.lqmb_serialize(pf)
out = M.resd_encrypt(body, dres, dtag, denc)
open(OUT, 'wb').write(out)
print(f"{OUT} = {os.path.getsize(OUT)} bytes")