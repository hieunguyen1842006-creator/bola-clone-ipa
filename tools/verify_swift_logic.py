#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_swift_logic.py — transcribe Y NGUYEN thuat toan trong AES128.swift /
ResD.swift / LqmbFormat.swift (Swift) sang Python de kiem chung tinh dung dan
truoc khi build tren GitHub Actions.

Muc dich: bat loi index (shiftRows/mixColumns), thu tu doc/ghi, va round-trip
byte-exact tren file that. KHONG phai ban tham chieu doc lap.
"""
import struct
import sys

# ===== AES128.swift transcription =====
SBOX = [
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16,
]
INV_SBOX = [0] * 256
for i, v in enumerate(SBOX):
    INV_SBOX[v] = i
RCON = [0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36]


def expand_key(key):
    assert len(key) == 16
    w = [0] * 176
    w[0:16] = key
    rnd = 1
    off = 16
    while off < 176:
        t = list(w[off - 4:off])
        if off % 16 == 0:
            t = [t[1], t[2], t[3], t[0]]
            t = [SBOX[x] for x in t]
            t[0] ^= RCON[rnd]
            rnd += 1
        for i in range(4):
            w[off] = w[off - 16] ^ t[i]
            off += 1
    return w


def xtime(a):
    return ((a << 1) ^ (0x1B if (a & 0x80) else 0x00)) & 0xFF


def mul(a, b):
    r = 0
    x, y = a, b
    while y:
        if y & 1:
            r ^= x
        x = xtime(x)
        y >>= 1
    return r & 0xFF


def add_round_key(s, w, rnd):
    base = rnd * 16
    for i in range(16):
        s[i] ^= w[base + i]


def sub_bytes(s):
    for i in range(16):
        s[i] = SBOX[s[i]]


def inv_sub_bytes(s):
    for i in range(16):
        s[i] = INV_SBOX[s[i]]


def shift_rows(s):
    t = list(s)
    for row in range(1, 4):
        for col in range(4):
            t[col * 4 + row] = s[((col + row) % 4) * 4 + row]
    s[:] = t


def inv_shift_rows(s):
    t = list(s)
    for row in range(1, 4):
        for col in range(4):
            t[((col + row) % 4) * 4 + row] = s[col * 4 + row]
    s[:] = t


def mix_columns(s):
    for c in range(4):
        i = c * 4
        a0, a1, a2, a3 = s[i], s[i + 1], s[i + 2], s[i + 3]
        s[i]     = mul(a0, 2) ^ mul(a1, 3) ^ a2 ^ a3
        s[i + 1] = a0 ^ mul(a1, 2) ^ mul(a2, 3) ^ a3
        s[i + 2] = a0 ^ a1 ^ mul(a2, 2) ^ mul(a3, 3)
        s[i + 3] = mul(a0, 3) ^ a1 ^ a2 ^ mul(a3, 2)


def inv_mix_columns(s):
    for c in range(4):
        i = c * 4
        a0, a1, a2, a3 = s[i], s[i + 1], s[i + 2], s[i + 3]
        s[i]     = mul(a0, 14) ^ mul(a1, 11) ^ mul(a2, 13) ^ mul(a3, 9)
        s[i + 1] = mul(a0, 9)  ^ mul(a1, 14) ^ mul(a2, 11) ^ mul(a3, 13)
        s[i + 2] = mul(a0, 13) ^ mul(a1, 9)  ^ mul(a2, 14) ^ mul(a3, 11)
        s[i + 3] = mul(a0, 11) ^ mul(a1, 13) ^ mul(a2, 9)  ^ mul(a3, 14)


def encrypt_block(block, w):
    add_round_key(block, w, 0)
    for rnd in range(1, 10):
        sub_bytes(block)
        shift_rows(block)
        mix_columns(block)
        add_round_key(block, w, rnd)
    sub_bytes(block)
    shift_rows(block)
    add_round_key(block, w, 10)


def decrypt_block(block, w):
    add_round_key(block, w, 10)
    for rnd in range(9, 0, -1):
        inv_shift_rows(block)
        inv_sub_bytes(block)
        add_round_key(block, w, rnd)
        inv_mix_columns(block)
    inv_shift_rows(block)
    inv_sub_bytes(block)
    add_round_key(block, w, 0)


def cbc_encrypt(key, iv, data):
    if len(key) != 16 or len(iv) != 16 or len(data) % 16:
        return None
    w = expand_key(key)
    prev = list(iv)
    out = [0] * len(data)
    off = 0
    while off < len(data):
        block = list(data[off:off + 16])
        for i in range(16):
            block[i] ^= prev[i]
        encrypt_block(block, w)
        out[off:off + 16] = block
        prev = block
        off += 16
    return bytes(out)


def cbc_decrypt(key, iv, data):
    if len(key) != 16 or len(iv) != 16 or len(data) % 16:
        return None
    w = expand_key(key)
    prev = list(iv)
    out = [0] * len(data)
    off = 0
    while off < len(data):
        cblock = list(data[off:off + 16])
        block = list(cblock)
        decrypt_block(block, w)
        for i in range(16):
            out[off + i] = block[i] ^ prev[i]
        prev = cblock
        off += 16
    return bytes(out)


# ===== ResD.swift transcription =====
RAW_KEY = bytes([0x99,0x64,0xB1,0xB0,0x6B,0x03,0x8D,0x7F,
                 0xB7,0x7D,0xB6,0xA7,0x54,0x90,0x8B,0x73])
IV0 = b'\x00' * 16
MAGIC = 0x4A22
IFIX_LQMB = bytes.fromhex('d0db2c0e465fd41f')
IFIX_OLD = bytes.fromhex('cba2b40db219a366')


def dotnet_hash_upper(s):
    h = 0
    for ch in s.upper():
        h = (h * 31 + (ord(ch) & 0xFFFF)) & 0xFFFFFFFF
    return h


def mixed_key(res_name):
    h = dotnet_hash_upper(res_name)
    return bytes(RAW_KEY[i] ^ ((h >> (8 * (i & 3))) & 0xFF) for i in range(16))


def looks_plain(body):
    return len(body) >= 8 and (body[:8] == IFIX_LQMB or body[:8] == IFIX_OLD)


def resd_decrypt(blob, res_name):
    if len(blob) < 8:
        raise ValueError('too short')
    m = struct.unpack_from('<H', blob, 0)[0]
    if m != MAGIC:
        raise ValueError('bad magic %04x' % m)
    tag = struct.unpack_from('<H', blob, 2)[0]
    orig_len = struct.unpack_from('<I', blob, 4)[0]
    body = blob[8:]
    if len(body) == orig_len and looks_plain(body):
        return tag, orig_len, body, False
    if len(body) % 16:
        raise ValueError('not block aligned')
    pt = cbc_decrypt(mixed_key(res_name), IV0, body)
    if pt is None or len(pt) < orig_len:
        raise ValueError('truncated')
    return tag, orig_len, pt[:orig_len], True


def resd_encrypt(plain, res_name, tag, encrypt=True):
    if encrypt:
        pad = 16 - (len(plain) % 16)
        padded = plain + bytes([pad]) * pad
        body = cbc_encrypt(mixed_key(res_name), IV0, padded)
    else:
        body = plain
    head = struct.pack('<HHI', MAGIC, tag, len(plain))
    return head + body


def res_name_for_file(name):
    base = name.split('/')[-1]
    if base.endswith('.bytes'):
        return base[:-len('.bytes')]
    if '.' in base:
        return base.rsplit('.', 1)[0]
    return base


# ===== LqmbFormat.swift transcription =====
MAGIC_LQMB = bytes.fromhex('d0db2c0e465fd41f')
MAGIC_OLD = bytes.fromhex('cba2b40db219a366')


class Reader:
    def __init__(self, buf):
        self.buf = buf
        self.pos = 0

    @property
    def remaining(self):
        return len(self.buf) - self.pos

    def need(self, k, what):
        if self.remaining < k:
            raise ValueError('truncated %s need %d have %d' % (what, k, self.remaining))

    def u8(self, what):
        self.need(1, what)
        v = self.buf[self.pos]
        self.pos += 1
        return v

    def i32(self, what):
        self.need(4, what)
        v = struct.unpack_from('<i', self.buf, self.pos)[0]
        self.pos += 4
        return v

    def u7(self, what):
        v = 0
        shift = 0
        for _ in range(5):
            b = self.u8(what)
            v |= (b & 0x7F) << shift
            if not (b & 0x80):
                return v
            shift += 7
        raise ValueError('varint too long')

    def string(self, what):
        n = self.u7(what)
        self.need(n, what)
        s = self.buf[self.pos:self.pos + n].decode('utf-8')
        self.pos += n
        return s

    def count(self, what, min_bytes):
        v = self.i32(what)
        if v < 0:
            raise ValueError('negative count %s %d' % (what, v))
        if min_bytes > 0 and v * min_bytes > self.remaining:
            raise ValueError('absurd count %s %d' % (what, v))
        return v

    def raw(self, n, what):
        self.need(n, what)
        s = self.buf[self.pos:self.pos + n]
        self.pos += n
        return bytes(s)


class Writer:
    def __init__(self):
        self.out = bytearray()

    def u8(self, v):
        self.out.append(v & 0xFF)

    def i32(self, v):
        self.out += struct.pack('<i', v)

    def u7(self, n):
        v = n
        while True:
            if v < 0x80:
                self.u8(v)
                return
            self.u8((v & 0x7F) | 0x80)
            v >>= 7

    def string(self, s):
        b = s.encode('utf-8')
        self.u7(len(b))
        self.out += b

    def raw(self, b):
        self.out += b


def read_method(r, what):
    m = {}
    m['isGeneric'] = r.u8(what) != 0
    m['declType'] = r.i32(what)
    m['name'] = r.string(what + '.name')
    m['typeArgs'] = []
    if m['isGeneric']:
        n = r.count(what + '.targs', 4)
        for _ in range(n):
            m['typeArgs'].append(r.i32(what))
    m['params'] = []
    np_ = r.count(what + '.params', 1 if m['isGeneric'] else 4)
    for _ in range(np_):
        p = {'isName': False, 'id': -1, 'name': ''}
        if m['isGeneric']:
            p['isName'] = r.u8(what) != 0
            if p['isName']:
                p['name'] = r.string(what)
            else:
                p['id'] = r.i32(what)
        else:
            p['id'] = r.i32(what)
        m['params'].append(p)
    return m


def write_method(w, m):
    w.u8(1 if m['isGeneric'] else 0)
    w.i32(m['declType'])
    w.string(m['name'])
    if m['isGeneric']:
        w.i32(len(m['typeArgs']))
        for v in m['typeArgs']:
            w.i32(v)
    w.i32(len(m['params']))
    for p in m['params']:
        if m['isGeneric']:
            w.u8(1 if p['isName'] else 0)
        if p['isName']:
            w.string(p['name'])
        else:
            w.i32(p['id'])


def lqmb_parse(data):
    r = Reader(data)
    pf = {}
    head = r.raw(8, 'magic')
    if head == MAGIC_LQMB:
        pf['magic'] = MAGIC_LQMB
    elif head == MAGIC_OLD:
        pf['magic'] = MAGIC_OLD
    else:
        raise ValueError('bad magic')
    has_pad = pf['magic'] != MAGIC_LQMB

    pf['bridge'] = r.string('bridge')
    n = r.count('types', 1)
    pf['types'] = [r.string('types') for _ in range(n)]

    pf['nextAlloc'] = r.i32('next_alloc')
    pf['blocks'] = []
    for bi in range(pf['nextAlloc']):
        blk = {'instrs': [], 'handlers': []}
        cnt = r.count('block.instrs', 8)
        for _ in range(cnt):
            blk['instrs'].append(r.i32('instr.code'))
            blk['instrs'].append(r.i32('instr.op'))
        ehc = r.count('block.handlers', 24)
        for _ in range(ehc):
            blk['handlers'].append([r.i32('handler') for _ in range(6)])
        pf['blocks'].append(blk)

    n = r.count('methods', 6)
    pf['methods'] = [read_method(r, 'methods') for _ in range(n)]

    n = r.count('strings', 1)
    pf['strings'] = [r.string('strings') for _ in range(n)]

    n = r.count('fields', 6)
    pf['fields'] = []
    for _ in range(n):
        f = {'isNew': r.u8('fields') != 0, 'declType': r.i32('fields'),
             'name': r.string('fields.name'), 'ftype': -1, 'ctor': -1}
        if f['isNew']:
            f['ftype'] = r.i32('fields')
            f['ctor'] = r.i32('fields')
        pf['fields'].append(f)

    n = r.count('fsvm', 8)
    pf['fsvm'] = [(r.i32('fsvm'), r.i32('fsvm')) for _ in range(n)]

    n = r.count('anon', 20)
    pf['anon'] = []
    for _ in range(n):
        an = {}
        nf = r.count('anon.fields', 4)
        an['fieldIds'] = [r.i32('anon.fields') for _ in range(nf)]
        an['ctor'] = r.i32('anon')
        an['paramCount'] = r.i32('anon')
        nif = r.count('anon.interfaces', 8)
        an['interfaces'] = [(r.i32('iface'), r.i32('iface')) for _ in range(nif)]
        nv = r.count('anon.vtable', 4)
        an['vtable'] = [r.i32('anon.vtable') for _ in range(nv)]
        pf['anon'].append(an)

    pf['wrapper'] = r.string('wrapper')
    pf['idmap'] = r.string('idmap')
    pf['pad'] = 0
    if has_pad:
        pf['pad'] = r.u8('pad')

    n = r.count('interpret', 6)
    pf['interpret'] = []
    for _ in range(n):
        m = read_method(r, 'interpret')
        pf['interpret'].append({'method': m, 'vm': r.i32('interpret.vm')})

    n = r.count('newClasses', 1)
    pf['newClasses'] = [r.string('newClasses') for _ in range(n)]

    tail_len = r.remaining
    pf['trailer'] = r.raw(tail_len, 'trailer')
    return pf


def lqmb_serialize(pf):
    if pf['nextAlloc'] != len(pf['blocks']):
        raise ValueError('next_alloc mismatch')
    w = Writer()
    w.raw(pf['magic'])
    w.string(pf['bridge'])
    w.i32(len(pf['types']))
    for t in pf['types']:
        w.string(t)
    w.i32(pf['nextAlloc'])
    for blk in pf['blocks']:
        assert len(blk['instrs']) % 2 == 0
        w.i32(len(blk['instrs']) // 2)
        for v in blk['instrs']:
            w.i32(v)
        w.i32(len(blk['handlers']))
        for h in blk['handlers']:
            assert len(h) == 6
            for v in h:
                w.i32(v)
    w.i32(len(pf['methods']))
    for m in pf['methods']:
        write_method(w, m)
    w.i32(len(pf['strings']))
    for s in pf['strings']:
        w.string(s)
    w.i32(len(pf['fields']))
    for f in pf['fields']:
        w.u8(1 if f['isNew'] else 0)
        w.i32(f['declType'])
        w.string(f['name'])
        if f['isNew']:
            w.i32(f['ftype'])
            w.i32(f['ctor'])
    w.i32(len(pf['fsvm']))
    for a, b in pf['fsvm']:
        w.i32(a)
        w.i32(b)
    w.i32(len(pf['anon']))
    for an in pf['anon']:
        w.i32(len(an['fieldIds']))
        for v in an['fieldIds']:
            w.i32(v)
        w.i32(an['ctor'])
        w.i32(an['paramCount'])
        w.i32(len(an['interfaces']))
        for a, b in an['interfaces']:
            w.i32(a)
            w.i32(b)
        w.i32(len(an['vtable']))
        for v in an['vtable']:
            w.i32(v)
    w.string(pf['wrapper'])
    w.string(pf['idmap'])
    if pf['magic'] != MAGIC_LQMB:
        w.u8(pf['pad'])
    w.i32(len(pf['interpret']))
    for h in pf['interpret']:
        write_method(w, h['method'])
        w.i32(h['vm'])
    w.i32(len(pf['newClasses']))
    for c in pf['newClasses']:
        w.string(c)
    w.raw(pf['trailer'])
    return bytes(w.out)


def main():
    ok = True

    def check(name, cond, extra=''):
        nonlocal ok
        print(('  OK   ' if cond else '  FAIL ') + name + (('  ' + extra) if extra else ''))
        if not cond:
            ok = False

    print('=== AES-128 FIPS-197 (transcription cua Swift) ===')
    key = bytes(range(16))
    pt = bytes.fromhex('00112233445566778899aabbccddeeff')
    w = expand_key(list(key))
    blk = list(pt)
    encrypt_block(blk, w)
    check('encrypt == 69c4e0d8...', bytes(blk).hex() == '69c4e0d86a7b0430d8cdb78070b4c55a',
          bytes(blk).hex())
    back = list(bytes(blk))
    decrypt_block(back, w)
    check('decrypt == plaintext', bytes(back) == pt, bytes(back).hex())

    print('=== ResD vectors ===')
    check('hash HeroSkin_1 == d62be269',
          dotnet_hash_upper('HeroSkin_1') == 0xD62BE269,
          '%08x' % dotnet_hash_upper('HeroSkin_1'))
    check('key HeroSkin_1 == f0869a66...',
          mixed_key('HeroSkin_1').hex() == 'f0869a6602e1a6a9de9f9d713d72a0a5',
          mixed_key('HeroSkin_1').hex())

    plain = b'NVH-TEST-PATCH-PAYLOAD-0123456789'
    ref = bytes.fromhex(
        '224a6700210000004c5e1a80e19efaba9abcb418cbce22e561a839e0'
        '19c00be9cbf3af167b538cd05f747a7049270c18997e756197a2a0b5')
    mine = resd_encrypt(plain, 'TestSkin_1', 103, True)
    check('ResD encrypt khop vector Python-ref', mine == ref, '%d vs %d byte' % (len(mine), len(ref)))
    tag, olen, dec, enc = resd_decrypt(ref, 'TestSkin_1')
    check('ResD decrypt tra plaintext', dec == plain, '%d byte' % len(dec))
    check('ResD decrypt tag=103 encrypted=True', tag == 103 and enc)

    print('=== Round-trip file that (HeroSkin_1..4) ===')
    import os
    base = r'd:\FileChuaHack\FF DATA IOS\AOVPatch_decrypted'
    for n in (1, 2, 3, 4):
        p = os.path.join(base, 'Thanos_HeroSkin_%d.bytes.plain.bin' % n)
        if not os.path.isfile(p):
            check('HeroSkin_%d ton tai' % n, False, p)
            continue
        data = open(p, 'rb').read()
        pf = lqmb_parse(data)
        ser = lqmb_serialize(pf)
        check('HeroSkin_%d round-trip byte-exact' % n,
              ser == data,
              '%d block, %d instr, %d hook' % (len(pf['blocks']),
                                               sum(len(b['instrs']) // 2 for b in pf['blocks']),
                                               len(pf['interpret'])))

    print('=== ResD round-trip tren file game that (tag 103) ===')
    game = r'd:\FileChuaHack\FF DATA IOS\AOVPatch_extracted\Application\com.garena.game.kgvn\Documents\Resources\1.64.1\Thanos'
    for n in (1, 2, 3, 4):
        p = os.path.join(game, 'HeroSkin_%d.bytes' % n)
        if not os.path.isfile(p):
            continue
        blob = open(p, 'rb').read()
        tag, olen, plain2, enc = resd_decrypt(blob, 'HeroSkin_%d' % n)
        reenc = resd_encrypt(plain2, 'HeroSkin_%d' % n, tag, enc)
        check('HeroSkin_%d.bytes ResD encrypt(decrypt(x)) == x' % n, reenc == blob,
              '%d byte, tag %d, %s' % (len(blob), tag, 'AES' if enc else 'plain'))

    print('=== Patch zoom tren file that ===')
    p = os.path.join(base, 'Thanos_HeroSkin_1.bytes.plain.bin')
    data = open(p, 'rb').read()
    pf = lqmb_parse(data)
    zoom_vm = None
    for h in pf['interpret']:
        m = h['method']
        owner = pf['types'][m['declType']].split(',')[0] if m['declType'] >= 0 else '?'
        if (owner + '::' + m['name']).endswith('CameraSystem::GetZoomRate'):
            zoom_vm = h['vm']
    check('tim thay hook CameraSystem::GetZoomRate', zoom_vm is not None, 'vm%s' % zoom_vm)
    if zoom_vm is not None:
        blk = pf['blocks'][zoom_vm]['instrs']
        newbits = struct.unpack('<i', struct.pack('<f', 2.0))[0]
        hits = 0
        i = 0
        while i + 1 < len(blk):
            if blk[i] == 0x8D:     # Ldc_R4
                blk[i + 1] = newbits
                hits += 1
                break
            i += 2
        check('ghi de duoc Ldc_R4 -> 2.0f', hits == 1, '%d site' % hits)
        ser = lqmb_serialize(pf)
        check('sau patch van serialize + parse lai duoc',
              lqmb_serialize(lqmb_parse(ser)) == ser)
        check('so byte khong doi', len(ser) == len(data), '%d vs %d' % (len(ser), len(data)))
        final = resd_encrypt(ser, 'HeroSkin_1', 103, True)
        check('dong goi lai ResD duoc', len(final) == len(open(
            os.path.join(game, 'HeroSkin_1.bytes'), 'rb').read()),
            '%d byte' % len(final))

    print('')
    print('RESULT:', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
