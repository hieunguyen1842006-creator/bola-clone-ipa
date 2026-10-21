#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""server.py — web local mô phỏng Sophiacheat FFPROXY (chạy trên máy anh).

Chạy:  python server.py [port]        (mặc định 8080)

Trang:
  /                              landing + hướng dẫn + tải config ProxyPin
  /menu                          menu web: nhập Secret -> bật/tắt -> Apply
  /admin                         tạo key test, đặt CDN URL
  /api/ff-menu/proxypin/config   JSON import vào ProxyPin (giống Sophia)
  /api/ff-menu/auth              POST {secret}
  /api/ff-menu/config            GET/POST cấu hình theo secret
  /api/admin/keys                POST tạo key, GET danh sách
  /api/admin/config              POST đổi CDN URL / report
  /config.json                   alias tải config ProxyPin
  /api/hit, /api/hits            log script báo về
  /_abhu/<path>                  CDN giả lập: log request, trả file trong abhu/
  /_abhu?p=/ios/<ver>/fileinfo   manifest resource (base: fileinfo.txt,
                                 hash/size tự thay cho file có trong abhu/)

Ghi chú:
  - CDN URL phải là HTTPS khi test với game. Dùng tunnel:
        cloudflared tunnel --url http://localhost:8080
    rồi dán https://...trycloudflare.com/_abhu/ vào /admin.
  - File state.json giữ key + config; hits.jsonl giữ log request.
"""
from __future__ import annotations

import base64
import gzip as gzipmod
import hashlib
import json
import os
import secrets
import socket
import sys
import threading
import time
import zlib
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "state.json")
HITS = os.path.join(HERE, "hits.jsonl")
ABHU = os.path.join(HERE, "abhu")
MANIFEST = os.path.join(HERE, "fileinfo.txt")

FEATURES = [
    ("esp", "ESP", [
        ("box", "Box"),
        ("line", "Line"),
        ("name", "Tên hero"),
        ("hp", "Máu"),
        ("dist", "Khoảng cách"),
        ("bot", "Đánh dấu bot"),
        ("count", "Đếm số địch"),
        ("skeleton", "Xương"),
        ("team", "Cả đội"),
    ]),
    ("aim", "Aim", [
        ("aimbot", "Aimbot"),
        ("silent", "Silent aim"),
        ("bones", "Bắn theo xương"),
        ("showfov", "Hiện vòng FOV"),
        ("skipknock", "Bỏ qua ngã"),
        ("straight", "Đạn thẳng"),
    ]),
    ("misc", "Misc", [
        ("fastfire", "Bắn nhanh"),
        ("fastswap", "Đổi súng nhanh"),
        ("emote", "Emote nhanh"),
        ("highjump", "Nhảy cao"),
        ("backjump", "Nhảy lùi"),
        ("speedrun", "Chạy nhanh"),
        ("fps144", "FPS 144"),
        ("camwide", "Camera rộng"),
    ]),
]

DEFAULT_FEATURES = {
    "box": True, "line": True, "name": True, "hp": True, "dist": False,
    "bot": False, "count": False, "skeleton": False, "team": False,
    "aimbot": False, "silent": False, "bones": True, "showfov": False,
    "skipknock": False, "straight": False,
    "fastfire": False, "fastswap": False, "emote": False, "highjump": False,
    "backjump": False, "speedrun": False, "fps144": False, "camwide": False,
}

DEFAULT_PARAMS = {
    "espThick": 100, "silentFov": 30, "aimFov": 30,
    "camFov": 88, "headRate": 100, "bone": 0,
}


# ---------------------------------------------------------- BolaConfig codec

def _clampi(v, lo, hi) -> int:
    try:
        v = int(v)
    except Exception:
        v = lo
    return max(lo, min(hi, v))


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def bola_config_bytes(features: dict, params: dict) -> bytes:
    """30 byte `nvhcfg.bin`: 26 payload XOR keystream + CRC32 LE (giống BolaConfig)."""
    f, p = features or {}, params or {}

    flags = 0
    for bit, key in ((0, "box"), (1, "line"), (2, "hp"), (3, "name"), (4, "dist"),
                     (5, "bot"), (7, "count")):
        if f.get(key):
            flags |= 1 << bit

    extra = 0
    for bit, key in ((0, "aimbot"), (1, "bones"), (2, "silent"), (3, "skipknock"),
                     (4, "showfov"), (5, "team"), (6, "straight")):
        if f.get(key):
            extra |= 1 << bit

    misc1 = 0
    for bit, key in ((0, "fastfire"), (3, "fastswap"), (5, "emote"),
                     (6, "highjump"), (7, "fps144")):
        if f.get(key):
            misc1 |= 1 << bit

    misc2 = 0
    for bit, key in ((1, "camwide"), (4, "backjump"), (5, "speedrun")):
        if f.get(key):
            misc2 |= 1 << bit

    out = bytearray(26)
    out[0:4] = b"BOLA"
    out[4] = 1
    out[5] = flags
    out[6] = _clampi(p.get("espThick"), 50, 200)
    out[7] = extra
    out[8] = _clampi(p.get("bone"), 0, 2)
    for off, color in ((9, 0xF925), (11, 0xF925), (13, 0xF925)):
        out[off] = color & 0xFF
        out[off + 1] = (color >> 8) & 0xFF
    out[15] = _clampi(p.get("silentFov"), 5, 100)
    out[16] = misc1
    out[17] = misc2
    out[18] = _clampi(p.get("camFov"), 50, 130)
    out[19] = _clampi(p.get("aimFov"), 5, 100)
    out[20] = _clampi(p.get("headRate"), 10, 100)
    out[21] = 1 if f.get("draghead") else 0     # byte 21: drag head (patch goc khong doc)
    out[22] = 1 if f.get("wallcheck") else 0    # byte 22: check tuong
    out[23] = _clampi(p.get("textScale") or 100, 50, 200)   # co chu ESP (%)
    out[24] = _clampi(p.get("drawDist") or 100, 25, 200)    # khoang cach ve, don vi 2 m

    for i in range(26):
        out[i] ^= ((0x5A + i * 0x37) ^ (i << 4)) & 0xFF

    crc = _crc32(bytes(out))
    return bytes(out) + crc.to_bytes(4, "little")

DEFAULT_STATE = {
    "cdn_url": "https://CHANGE-ME.example/_abhu/?t=nvh-local&p=/",
    "report": True,
    "maintenance": False,
    "disabled": [],
    "keys": {},
}

TIKTOK_BLACKLIST = [
    r"(^|\.)tiktokv\.com$",
    r"(^|\.)tiktokcdn\.com$",
    r"(^|\.)ibyteimg\.com$",
    r"(^|\.)tiktok\.com$",
    r"(^|\.)byteoversea\.com$",
]


def policy_payload(s: dict) -> dict:
    feats = [{"id": fid, "label": label}
             for _g, _n, items in FEATURES for fid, label in items]
    return {
        "maintenance": bool(s.get("maintenance")),
        "disabled": list(s.get("disabled") or []),
        "features": feats,
    }

_lock = threading.Lock()
_gz_cache: dict = {}


# ---------------------------------------------------------------- state

def load_state() -> dict:
    try:
        with open(STATE, "r", encoding="utf-8") as f:
            s = json.load(f)
    except Exception:
        s = {}
    s.setdefault("cdn_url", DEFAULT_STATE["cdn_url"])
    s.setdefault("report", True)
    s.setdefault("maintenance", False)
    s.setdefault("disabled", [])
    s.setdefault("keys", {})
    for _, _, feats in FEATURES:
        for key, _label in feats:
            DEFAULT_FEATURES.setdefault(key, False)
    return s


def save_state(s: dict) -> None:
    with _lock:
        with open(STATE, "w", encoding="utf-8") as f:
            json.dump(s, f, ensure_ascii=False, indent=2)


def now_iso() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def mask_key(k: str) -> str:
    return (k[:4] + "••••" + k[-4:]) if len(k) > 10 else "••••"


def new_key() -> tuple[str, str]:
    raw = secrets.token_hex(6).upper()
    key = "NVH-" + "-".join(raw[i:i + 4] for i in range(0, 12, 4))
    return key, secrets.token_hex(16)          # key, secret 32 hex


def find_by_secret(s: dict, secret: str):
    secret = (secret or "").strip().lower()
    for key, rec in s["keys"].items():
        if rec.get("secret") == secret:
            return key, rec
    return None, None


def key_public(key: str, rec: dict) -> dict:
    exp = rec.get("expires", "")
    left = ""
    try:
        dt = datetime.strptime(exp, "%Y-%m-%d %H:%M:%S")
        secs = int((dt - datetime.now()).total_seconds())
        left = "hết hạn" if secs <= 0 else ("%d ngày %d giờ" % (secs // 86400, (secs % 86400) // 3600))
    except Exception:
        pass
    return {
        "key": mask_key(key),
        "expires": exp,
        "left": left,
        "platform": rec.get("platform", "ff"),
        "features": rec.get("features") or dict(DEFAULT_FEATURES),
        "params": rec.get("params") or dict(DEFAULT_PARAMS),
        "applied_at": rec.get("applied_at", ""),
    }


# ---------------------------------------------------------------- proxy script

def js_str(v: str) -> str:
    return json.dumps(v, ensure_ascii=False)


def proxy_script(cdn_url: str, report_url: str | None) -> str:
    report = ""
    if report_url:
        report = (
            "try{fetch(" + js_str(report_url + "/api/hit?kind=live&host=") +
            "+encodeURIComponent(r.host||'')+'&path='+encodeURIComponent(r.path||''));}catch(e){}"
        )
    return (
        "function onRequest(c,r){"
        "try{var u=(r&&(r.url||r.host||''))||'';"
        "if(u.indexOf('ff-menu')>=0){return null;}"
        "}catch(e){}return r;}"
        "function onResponse(c,r,s){"
        "try{"
        "if(r.path&&r.path.indexOf('/live')===0){"
        "var b=s.body||'';"
        "if(b.indexOf('abhotupdate_cdn_url')>=0){"
        "var o=JSON.parse(b);"
        "o.abhotupdate_cdn_url=" + js_str(cdn_url) + ";"
        "s.body=JSON.stringify(o);"
        + report +
        "}"
        "}"
        "}catch(e){}return s;}"
    )


# ---------------------------------------------------------------- fileinfo

def sha1_b64_bytes(data: bytes) -> str:
    return base64.b64encode(hashlib.sha1(data).digest()).decode()


def gzip_payload(path: str) -> bytes:
    """Game nhận body gzip rồi tự giải nén (giống bundle trong IPA của FF)."""
    st = os.stat(path)
    with _lock:
        rec = _gz_cache.get(path)
    if rec and rec[0] == (st.st_mtime_ns, st.st_size):
        return rec[1]
    gz = gzipmod.compress(open(path, "rb").read(), 9, mtime=0)
    with _lock:
        _gz_cache[path] = ((st.st_mtime_ns, st.st_size), gz)
    return gz


def replacement_for(name: str):
    """File thay thế cho 1 entry manifest: abhu/<basename>.bin hoặc abhu/<basename>."""
    base = os.path.join(ABHU, os.path.basename(name))
    for cand in (base + ".bin", base):
        if os.path.isfile(cand):
            return cand
    return None


def build_fileinfo() -> tuple[bytes, list[str]]:
    """Manifest dạng: name,hash1,size1,0,hash2,size2,True,0

    hash = SHA-1 base64 (28 ký tự). URL tải của game dùng hash2 + size2,
    nên khi có file thay thế trong abhu/ thì ghi đè cả 2 cặp hash/size.
    """
    try:
        with open(MANIFEST, "r", encoding="utf-8") as f:
            lines = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    except FileNotFoundError:
        return b"", []

    out, replaced = [], []
    for ln in lines:
        parts = ln.split(",")
        if len(parts) == 8:
            path = replacement_for(parts[0])
            if path:
                raw = open(path, "rb").read()
                gz = gzip_payload(path)
                parts[1], parts[2] = sha1_b64_bytes(raw), str(len(raw))
                parts[4], parts[5] = sha1_b64_bytes(gz), str(len(gz))
                replaced.append(parts[0])
        out.append(",".join(parts))
    return ("\n".join(out) + "\n").encode("utf-8"), replaced


# ---------------------------------------------------------------- html

LANDING = """<!doctype html><html lang="vi"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NVH CONTROL · FFPROXY (local)</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:#0b0b0d;color:#eee;font:15px/1.6 -apple-system,Segoe UI,sans-serif}
.wrap{max-width:900px;margin:0 auto;padding:28px 18px 60px}
.brand{display:flex;align-items:center;gap:10px;font-weight:800;letter-spacing:.5px}
.dot{width:10px;height:10px;border-radius:50%;background:#4ade80;box-shadow:0 0 14px #4ade80}
h1{font-size:34px;line-height:1.15;margin:26px 0 8px;letter-spacing:-.5px}
.sub{color:#9aa0a6;margin:0 0 22px}
.card{background:#141417;border:1px solid #242428;border-radius:14px;padding:18px;margin:14px 0}
.row{display:flex;gap:10px;flex-wrap:wrap}
.btn{display:inline-block;padding:11px 16px;border-radius:10px;background:#3b82f6;color:#fff;
     text-decoration:none;font-weight:700;border:0;cursor:pointer}
.btn.ghost{background:#222226;color:#ddd;border:1px solid #333}
.mono{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#8bd}
.step{display:flex;gap:12px;margin:12px 0}
.n{width:26px;height:26px;border-radius:50%;background:#1f2937;color:#93c5fd;
   display:flex;align-items:center;justify-content:center;font-weight:700;flex:none}
.warn{color:#f0b429}
small{color:#888}
</style>
<div class="wrap">
  <div class="brand"><span class="dot"></span> NVH CONTROL · FFPROXY <span class="mono">local</span></div>
  <h1>Một menu.<br>Toàn bộ cấu hình trong tầm tay.</h1>
  <p class="sub">Chỉnh cấu hình trên web, lưu theo key, quay lại game. Bản local để test
     luồng ProxyPin + CDN hot-update.</p>
  <div class="row">
    <a class="btn" href="/menu">Mở menu web</a>
    <a class="btn ghost" href="/api/ff-menu/proxypin/config">Tải cấu hình ProxyPin</a>
    <a class="btn ghost" href="/admin">Quản trị (tạo key)</a>
  </div>

  <div class="card">
    <b>Bắt đầu với ProxyPin</b>
    <div class="step"><div class="n">1</div><div>Tải file cấu hình ProxyPin, mở ProxyPin →
      Script → Import, chọn file vừa tải.</div></div>
    <div class="step"><div class="n">2</div><div>Bật Script, bật giải mã HTTPS, cài CA của ProxyPin
      và bật tin cậy trong Settings → Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng nhận.</div></div>
    <div class="step"><div class="n">3</div><div>Bật VPN ProxyPin, mở FF. Script sẽ sửa
      <span class="mono">/live</span> để game tải CDN trong <a href="/admin">Quản trị</a>.</div></div>
    <div class="step"><div class="n">4</div><div>Vào <a href="/menu">menu web</a>, nhập Secret
      (lấy từ menu trong game sau khi nhập key), chỉnh và Apply.</div></div>
    <p class="warn">Bản local: CDN URL mặc định là placeholder. Đặt URL HTTPS thật trong
      <a href="/admin">Quản trị</a> trước khi test với game.</p>
  </div>
</div></html>"""


MENU = """<!doctype html><html lang="vi"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NVH Control</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:#0b0b0d;color:#eee;font:15px/1.55 -apple-system,Segoe UI,sans-serif}
.wrap{max-width:760px;margin:0 auto;padding:22px 16px 70px}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
.brand{font-weight:800;letter-spacing:.4px}
.mono{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#8bd}
.card{background:#141417;border:1px solid #242428;border-radius:14px;padding:16px;margin:12px 0}
label{font-size:12px;color:#9aa0a6;display:block;margin-bottom:6px}
input[type=text]{width:100%;padding:12px;border-radius:10px;border:1px solid #2c2c31;background:#0e0e11;color:#eee}
input[type=number],select{padding:8px;border-radius:8px;border:1px solid #2c2c31;background:#0e0e11;color:#eee;width:96px}
.btn{padding:11px 16px;border-radius:10px;border:0;background:#3b82f6;color:#fff;font-weight:700;cursor:pointer}
.btn.ghost{background:#222226;color:#ddd;border:1px solid #333}
.btn:disabled{opacity:.5}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.sec{display:flex;justify-content:space-between;align-items:center;margin:16px 0 6px}
.sec b{font-size:13px;letter-spacing:.6px;color:#9ad}
.item{display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:1px solid #1f1f23}
.item:last-child{border-bottom:0}
.sw{position:relative;width:44px;height:26px;flex:none}
.sw input{display:none}
.sw span{position:absolute;inset:0;background:#2a2a30;border-radius:999px;transition:.15s}
.sw span:after{content:"";position:absolute;width:20px;height:20px;border-radius:50%;background:#fff;
  top:3px;left:3px;transition:.15s}
.sw input:checked + span{background:#22c55e}
.sw input:checked + span:after{left:21px}
.info{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.info div{background:#0f0f12;border:1px solid #242428;border-radius:10px;padding:10px}
.info small{color:#888;display:block}
.toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:#1f2937;color:#fff;
  padding:10px 14px;border-radius:10px;opacity:0;transition:.2s;font-size:13px}
.toast.on{opacity:1}
.hide{display:none}
</style>
<div class="wrap">
  <div class="top">
    <div class="brand">NVH CONTROL</div>
    <div class="row">
      <a class="btn ghost" href="/" style="text-decoration:none">Trang chủ</a>
      <button class="btn ghost hide" id="out" onclick="logout()">Đăng xuất</button>
    </div>
  </div>

  <div class="card" id="login">
    <label>Menu Secret (32 ký tự, lấy từ menu trong game)</label>
    <input id="secret" type="text" placeholder="dán Secret vào đây" autocomplete="off">
    <div class="row" style="margin-top:12px">
      <button class="btn" onclick="auth()">Đăng nhập</button>
      <span class="mono" id="loginMsg"></span>
    </div>
  </div>

  <div id="app" class="hide">
    <div class="card">
      <div class="info">
        <div><small>Key</small><span class="mono" id="kKey">—</span></div>
        <div><small>Hết hạn</small><span class="mono" id="kExp">—</span></div>
        <div><small>Còn lại</small><span class="mono" id="kLeft">—</span></div>
        <div><small>Áp dụng lần cuối</small><span class="mono" id="kApplied">—</span></div>
      </div>
      <div class="row" style="margin-top:12px">
        <button class="btn ghost" id="pFF" onclick="setPlat('ff')">Free Fire</button>
        <button class="btn ghost" id="pMAX" onclick="setPlat('ffmax')">Free Fire MAX</button>
      </div>
    </div>

    <div id="feats"></div>

    <div class="sec"><b>THÔNG SỐ</b></div>
    <div class="card">
      <div class="item"><span>Độ dày ESP</span><input id="pThick" type="number" min="50" max="200"></div>
      <div class="item"><span>Silent FOV</span><input id="pSilent" type="number" min="5" max="100"></div>
      <div class="item"><span>Aim FOV</span><input id="pAim" type="number" min="5" max="100"></div>
      <div class="item"><span>Camera FOV</span><input id="pCam" type="number" min="50" max="130"></div>
      <div class="item"><span>Tỉ lệ headshot</span><input id="pHead" type="number" min="10" max="100"></div>
      <div class="item"><span>Bone aim</span>
        <select id="pBone"><option value="0">Đầu</option><option value="1">Cổ</option><option value="2">Ngực</option></select>
      </div>
    </div>

    <div class="row" style="margin-top:14px">
      <button class="btn" id="apply" onclick="apply()">Áp dụng</button>
      <a class="btn ghost" id="dlCfg" href="#" style="text-decoration:none">Tải nvhcfg.bin</a>
      <a class="btn ghost" href="/api/ff-menu/proxypin/tiktok-blacklist" style="text-decoration:none">Blacklist TikTok</a>
      <button class="btn ghost" onclick="openGame()">Mở game</button>
    </div>
  </div>
</div>
<div class="toast" id="toast"></div>

<script>
const $ = s => document.querySelector(s);
const FEATURES = __FEATURES__;
let SECRET = localStorage.getItem('nvh.secret') || '';
let TOKEN = localStorage.getItem('nvh.token') || '';
let STATE = null;
let POLICY = null;

function toast(t){ const el=$('#toast'); el.textContent=t; el.classList.add('on');
  clearTimeout(el._t); el._t=setTimeout(()=>el.classList.remove('on'),1800); }

async function api(path, opt){ const r = await fetch(path, opt);
  if(!r.ok) throw new Error(await r.text()); return r.json(); }

function render(){
  const box = $('#feats'); box.innerHTML='';
  for(const [gid, gname, items] of FEATURES){
    const sec=document.createElement('div'); sec.className='sec'; sec.innerHTML='<b>'+gname+'</b>'; box.appendChild(sec);
    const card=document.createElement('div'); card.className='card';
    for(const [fid, label] of items){
      const row=document.createElement('div'); row.className='item';
      row.innerHTML='<span>'+label+'</span>'+
        '<label class="sw"><input type="checkbox" data-f="'+fid+'"'+
        ((STATE.features&&STATE.features[fid])?' checked':'')+'><span></span></label>';
      card.appendChild(row);
    }
    box.appendChild(card);
  }
  $('#pFF').style.background = STATE.platform==='ff' ? '#1d4ed8' : '';
  $('#pMAX').style.background = STATE.platform==='ffmax' ? '#1d4ed8' : '';
  const p = STATE.params || {};
  $('#pThick').value = p.espThick != null ? p.espThick : 100;
  $('#pSilent').value = p.silentFov != null ? p.silentFov : 30;
  $('#pAim').value = p.aimFov != null ? p.aimFov : 30;
  $('#pCam').value = p.camFov != null ? p.camFov : 88;
  $('#pHead').value = p.headRate != null ? p.headRate : 100;
  $('#pBone').value = p.bone != null ? p.bone : 0;
  $('#dlCfg').href = '/nvhcfg.bin?secret=' + encodeURIComponent(SECRET);
}

function showApp(){
  $('#login').classList.add('hide'); $('#app').classList.remove('hide');
  $('#out').classList.remove('hide');
  $('#kKey').textContent = STATE.key;
  $('#kExp').textContent = STATE.expires || '—';
  $('#kLeft').textContent = STATE.left || '—';
  $('#kApplied').textContent = STATE.applied_at || '—';
  render();
}

async function auth(){
  const s = ($('#secret').value||'').trim().toLowerCase();
  if(s.length !== 32){ $('#loginMsg').textContent='Secret phải 32 ký tự'; return; }
  try{
    const r = await api('/api/ff-menu/auth', {method:'POST',
      headers:{'content-type':'application/json'}, body:JSON.stringify({secret:s})});
    SECRET=s; TOKEN=(r.token||''); localStorage.setItem('nvh.secret', s);
    localStorage.setItem('nvh.token', TOKEN); STATE=r; showApp(); loadPolicy();
  }catch(e){ $('#loginMsg').textContent='Sai Secret'; }
}

function logout(){
  localStorage.removeItem('nvh.secret'); localStorage.removeItem('nvh.token');
  SECRET=''; TOKEN=''; STATE=null;
  $('#app').classList.add('hide'); $('#login').classList.remove('hide');
  $('#out').classList.add('hide'); $('#secret').value='';
}

function collect(){
  const f={};
  document.querySelectorAll('input[data-f]').forEach(el => f[el.dataset.f]=el.checked);
  return f;
}

function collectParams(){
  return {espThick:+$('#pThick').value, silentFov:+$('#pSilent').value,
          aimFov:+$('#pAim').value, camFov:+$('#pCam').value,
          headRate:+$('#pHead').value, bone:+$('#pBone').value};
}

async function apply(){
  const r = await api('/api/ff-menu/config', {method:'POST',
    headers:{'content-type':'application/json','authorization':'Bearer '+TOKEN},
    body:JSON.stringify({secret:SECRET, features:collect(), params:collectParams(), platform:STATE.platform})});
  STATE=r; showApp(); toast('Đã áp dụng — tải nvhcfg.bin để nạp vào game');
}

async function loadPolicy(){
  try{ POLICY = await (await fetch('/api/ff-menu/policy', {cache:'no-store'})).json(); }
  catch(e){ POLICY = null; }
  if(!POLICY) return;
  if(POLICY.maintenance){
    $('#apply').disabled = true;
    $('#apply').textContent = 'Đang bảo trì';
  }
  const off = POLICY.disabled || [];
  document.querySelectorAll('input[data-f]').forEach(el => {
    if(off.indexOf(el.dataset.f) >= 0){ el.disabled = true; el.checked = false; }
  });
}

function setPlat(p){ STATE.platform=p; render(); }

function openGame(){
  const scheme = STATE && STATE.platform==='ffmax' ? 'freefiremax://' : 'freefire://';
  location.href = scheme;
  setTimeout(()=>toast('Nếu game không mở, mở tay giúp mình'), 700);
}

(async function(){
  if(SECRET.length===32){
    try{ const r = await api('/api/ff-menu/auth', {method:'POST',
      headers:{'content-type':'application/json'}, body:JSON.stringify({secret:SECRET})});
      TOKEN=(r.token||TOKEN); localStorage.setItem('nvh.token', TOKEN);
      STATE=r; showApp(); loadPolicy(); }catch(e){ logout(); }
  }
})();
</script></html>"""


ADMIN = """<!doctype html><html lang="vi"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NVH Admin (local)</title>
<style>
:root{color-scheme:dark}
body{margin:0;background:#0b0b0d;color:#eee;font:14px/1.55 -apple-system,Segoe UI,sans-serif}
.wrap{max-width:860px;margin:0 auto;padding:22px 16px 70px}
.card{background:#141417;border:1px solid #242428;border-radius:14px;padding:16px;margin:12px 0}
input{width:100%;padding:10px;border-radius:9px;border:1px solid #2c2c31;background:#0e0e11;color:#eee}
label{font-size:12px;color:#9aa0a6;display:block;margin:8px 0 4px}
.btn{padding:10px 14px;border-radius:9px;border:0;background:#3b82f6;color:#fff;font-weight:700;cursor:pointer}
.btn.ghost{background:#222226;color:#ddd;border:1px solid #333}
.mono{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#8bd}
table{width:100%;border-collapse:collapse;font-size:12px}
th,td{border-bottom:1px solid #222;padding:7px;text-align:left}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:end}
</style>
<div class="wrap">
  <h2>NVH Admin · local</h2>
  <div class="card">
    <b>CDN + báo cáo</b>
    <label>CDN URL (HTTPS)</label>
    <input id="cdn" type="text">
    <div class="row" style="margin-top:10px">
      <button class="btn" onclick="saveCfg()">Lưu</button>
      <span class="mono" id="cfgMsg"></span>
    </div>
  </div>

  <div class="card">
    <b>Tạo key test</b>
    <div class="row" style="margin-top:8px">
      <div style="flex:1"><label>Số ngày</label><input id="days" type="text" value="7"></div>
      <button class="btn" onclick="mk()">Tạo</button>
    </div>
    <div class="mono" id="mkOut" style="margin-top:10px"></div>
  </div>

  <div class="card">
    <b>Key đã tạo</b>
    <table><thead><tr><th>key</th><th>secret</th><th>hết hạn</th><th>platform</th><th>apply</th></tr></thead>
    <tbody id="rows"></tbody></table>
  </div>
</div>
<script>
const $=s=>document.querySelector(s);
async function load(){
  const s = await (await fetch('/api/admin/state')).json();
  $('#cdn').value = s.cdn_url || '';
  $('#rows').innerHTML = (s.keys||[]).map(k =>
    `<tr><td class="mono">${k.key}</td><td class="mono">${k.secret}</td>
     <td class="mono">${k.expires||''}</td><td class="mono">${k.platform||''}</td>
     <td class="mono">${k.applied_at||''}</td></tr>`).join('');
}
async function saveCfg(){
  const r = await (await fetch('/api/admin/config',{method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify({cdn_url:$('#cdn').value})})).json();
  $('#cfgMsg').textContent = r.ok ? 'Đã lưu' : 'Lỗi';
}
async function mk(){
  const days = parseInt($('#days').value||'7',10);
  const r = await (await fetch('/api/admin/keys',{method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify({days})})).json();
  $('#mkOut').innerHTML = r.ok
    ? `KEY: ${r.key}<br>SECRET: ${r.secret}<br>Hết hạn: ${r.expires}`
    : 'Lỗi tạo key';
  load();
}
load();
</script></html>"""


# ---------------------------------------------------------------- handler

class Handler(BaseHTTPRequestHandler):
    server_version = "NVHLocal/2.0"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body: bytes, ctype="application/json"):
        self.send_response(code)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(body)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _html(self, text: str):
        self._send(200, text.encode(), "text/html; charset=utf-8")

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode())

    def _read_json(self):
        n = int(self.headers.get("content-length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        u = urlparse(self.path)
        p = u.path
        q = parse_qs(u.query)

        if p == "/":
            return self._html(LANDING)

        if p == "/menu":
            feats = [[g, name, [[fid, label] for fid, label in items]]
                     for g, name, items in FEATURES]
            return self._html(MENU.replace("__FEATURES__", json.dumps(feats, ensure_ascii=False)))

        if p == "/admin":
            return self._html(ADMIN)

        if p in ("/config.json", "/api/ff-menu/proxypin/config"):
            s = load_state()
            host = self.headers.get("host", "")
            local = host.startswith("127.") or host.startswith("localhost") or host.startswith("192.168.")
            report_url = (("http://" if local else "https://") + host) if s.get("report") else None
            script = proxy_script(s["cdn_url"], report_url)
            cfg = [{"enabled": True, "name": "NVH Local", "url": ".*", "script": script}]
            body = json.dumps(cfg, ensure_ascii=False, indent=2).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-disposition", 'attachment; filename="nvh-local.json"')
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)

        if p in ("/nvhcfg.bin", "/api/ff-menu/nvhcfg"):
            s = load_state()
            key, rec = find_by_secret(s, (q.get("secret") or [""])[0])
            if not rec:
                return self._json({"ok": False, "error": "bad secret"}, 401)
            body = bola_config_bytes(rec.get("features") or {}, rec.get("params") or {})
            print("[nvhcfg]", mask_key(key), len(body), "B")
            self.send_response(200)
            self.send_header("content-type", "application/octet-stream")
            self.send_header("content-disposition", 'attachment; filename="nvhcfg.bin"')
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)

        if p == "/localConfig.json":
            return self._send(200, b'{"testCodePatch":true}', "application/json")

        if p == "/api/admin/state":
            s = load_state()
            raw = []
            for key, rec in s["keys"].items():
                raw.append({"key": key, "secret": rec.get("secret", ""),
                            "expires": rec.get("expires", ""),
                            "platform": rec.get("platform", ""),
                            "applied_at": rec.get("applied_at", "")})
            return self._json({"cdn_url": s["cdn_url"], "report": s["report"], "keys": raw})

        if p == "/api/ff-menu/policy":
            return self._json(policy_payload(load_state()))

        if p == "/api/ff-menu/proxypin/tiktok-blacklist":
            body = json.dumps(TIKTOK_BLACKLIST, ensure_ascii=False, indent=2).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-disposition", 'attachment; filename="nvh-tiktok-blacklist.json"')
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)

        if p == "/api/ff-menu/game-status":
            s = load_state()
            key, rec = self._auth(s, (q.get("secret") or [""])[0])
            if not rec:
                return self._json({"ok": False, "error": "bad secret"}, 401)
            return self._json({"online": True, "key": mask_key(key),
                               "platform": rec.get("platform", "ff"),
                               "applied_at": rec.get("applied_at", ""),
                               "expires": rec.get("expires", "")})

        if p == "/api/ff-menu/config":
            s = load_state()
            key, rec = self._auth(s, (q.get("secret") or [""])[0])
            if not rec:
                return self._json({"ok": False, "error": "bad secret"}, 401)
            return self._json(key_public(key, rec))

        if p == "/api/hits":
            rows = []
            if os.path.exists(HITS):
                with open(HITS, "r", encoding="utf-8") as f:
                    for line in f:
                        try:
                            rows.append(json.loads(line))
                        except Exception:
                            pass
            return self._json(rows[-300:])

        if p == "/api/hit":
            rec = {"time": now_iso(), "kind": (q.get("kind") or [""])[0],
                   "host": (q.get("host") or [""])[0], "path": (q.get("path") or [""])[0]}
            log_hit(rec)
            print("[hit]", rec)
            return self._json({"ok": True})

        if p == "/fileinfo" or (p.startswith("/ios/") and p.endswith("/fileinfo")):
            return self._serve_fileinfo(p)

        if p.startswith("/_abhu"):
            # Game nối path vào sau "p=/" (dạng ?t=...&p=/ios/1.132.11/...)
            rel = (q.get("p") or [""])[0] or unquote(p[len("/_abhu"):])
            rel = rel.lstrip("/") or "index.bin"
            if rel.rsplit("/", 1)[-1] == "fileinfo":
                return self._serve_fileinfo(rel)
            rec = {"time": now_iso(), "kind": "abhu", "host": self.headers.get("host", ""),
                   "path": p, "query": u.query, "p": rel,
                   "range": self.headers.get("range", ""),
                   "ua": self.headers.get("user-agent", "")}
            log_hit(rec)
            print("[abhu]", rel, "range=", rec["range"])
            return self._serve_ab(rel)

        return self._send(404, b"404", "text/plain")

    def _serve_fileinfo(self, rel: str):
        body, replaced = build_fileinfo()
        rec = {"time": now_iso(), "kind": "fileinfo", "host": self.headers.get("host", ""),
               "path": rel, "bytes": len(body), "replaced": replaced,
               "ua": self.headers.get("user-agent", "")}
        log_hit(rec)
        print("[fileinfo]", rel, len(body), "B · thay", replaced or "không")
        self.send_response(200)
        self.send_header("content-type", "text/plain; charset=utf-8")
        self.send_header("access-control-allow-origin", "*")
        self.send_header("cache-control", "no-cache")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        return self.wfile.write(body)

    @staticmethod
    def _safe_rel(rel: str) -> str:
        # tên AB có hash chứa "~2F"/"~3D" (escape của '/' và '=') -> đổi sang '_'
        rel = rel.replace("~2F", "_").replace("~3D", "_").replace("~", "_")
        parts = [x for x in rel.split("/") if x not in ("", ".", "..")]
        return "/".join(parts)

    def _serve_ab(self, rel: str):
        base = os.path.abspath(ABHU)
        safe = self._safe_rel(rel)
        name = os.path.basename(safe)
        stem = name.split(".")[0]

        direct = [os.path.join(base, safe), os.path.join(base, name)]
        for cand in direct:
            if cand.startswith(base) and os.path.isfile(cand):
                return self._send_file(cand)

        # khớp mờ theo tên gốc (assembly-csharp-patch.<hash> -> assembly-csharp-patch.bin)
        for root, _dirs, files in os.walk(base):
            for f in files:
                if f.split(".")[0] == stem:
                    return self._send_file(os.path.join(root, f))

        return self._send(404, b"not found", "text/plain")

    def _send_file(self, path: str):
        data = gzip_payload(path)
        total = len(data)
        rng = self.headers.get("range", "")
        start, end, partial = 0, total - 1, False
        if rng.startswith("bytes="):
            try:
                a, _, b = rng[6:].split(",")[0].strip().partition("-")
                if a == "":
                    start = max(0, total - int(b))
                else:
                    start = int(a)
                    end = int(b) if b else total - 1
                end = min(end, total - 1)
                partial = start <= end
            except Exception:
                partial = False

        if partial:
            chunk = data[start:end + 1]
            self.send_response(206)
            self.send_header("content-type", "application/octet-stream")
            self.send_header("accept-ranges", "bytes")
            self.send_header("content-range", "bytes %d-%d/%d" % (start, end, total))
            self.send_header("content-length", str(len(chunk)))
            self.end_headers()
            return self.wfile.write(chunk)

        self.send_response(200)
        self.send_header("content-type", "application/octet-stream")
        self.send_header("accept-ranges", "bytes")
        self.send_header("content-length", str(total))
        self.end_headers()
        return self.wfile.write(data)

    def _auth(self, s: dict, secret: str = "", body: dict | None = None):
        """Bearer token (giống Sophia) hoặc secret trong query/body."""
        h = self.headers.get("authorization", "")
        if h.lower().startswith("bearer "):
            tok = h[7:].strip()
            for k, rec in s["keys"].items():
                if rec.get("token") == tok:
                    return k, rec
        return find_by_secret(s, secret or (body or {}).get("secret", ""))

    def do_POST(self):
        u = urlparse(self.path)
        p = u.path
        body = self._read_json()

        if p == "/api/ff-menu/auth":
            s = load_state()
            key, rec = find_by_secret(s, body.get("secret", ""))
            if not rec:
                return self._json({"ok": False, "error": "bad secret"}, 401)
            if not rec.get("token"):
                rec["token"] = secrets.token_hex(16)
                s["keys"][key] = rec
                save_state(s)
            pub = key_public(key, rec)
            pub["token"] = rec["token"]
            pub["keyId"] = pub["key"]
            return self._json(pub)

        if p == "/api/ff-menu/config":
            s = load_state()
            key, rec = self._auth(s, body.get("secret", ""), body)
            if not rec:
                return self._json({"ok": False, "error": "bad secret"}, 401)
            feats = body.get("features") or {}
            clean = {k: bool(feats.get(k, False)) for k in DEFAULT_FEATURES}
            rec["features"] = clean
            rawp = body.get("params") or {}
            rec["params"] = {
                "espThick": _clampi(rawp.get("espThick", 100), 50, 200),
                "silentFov": _clampi(rawp.get("silentFov", 30), 5, 100),
                "aimFov": _clampi(rawp.get("aimFov", 30), 5, 100),
                "camFov": _clampi(rawp.get("camFov", 88), 50, 130),
                "headRate": _clampi(rawp.get("headRate", 100), 10, 100),
                "bone": _clampi(rawp.get("bone", 0), 0, 2),
            }
            rec["platform"] = body.get("platform") or rec.get("platform", "ff")
            rec["applied_at"] = now_iso()
            s["keys"][key] = rec
            save_state(s)
            return self._json(key_public(key, rec))

        if p == "/api/admin/keys":
            s = load_state()
            try:
                days = int(body.get("days", 7))
            except Exception:
                days = 7
            key, secret = new_key()
            expires = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
            s["keys"][key] = {"secret": secret, "expires": expires,
                              "platform": "ff", "features": dict(DEFAULT_FEATURES),
                              "applied_at": ""}
            save_state(s)
            print("[key]", key, "secret", secret)
            return self._json({"ok": True, "key": key, "secret": secret, "expires": expires})

        if p == "/api/admin/config":
            s = load_state()
            if isinstance(body.get("cdn_url"), str):
                s["cdn_url"] = body["cdn_url"].strip()
            if isinstance(body.get("report"), bool):
                s["report"] = body["report"]
            if isinstance(body.get("maintenance"), bool):
                s["maintenance"] = body["maintenance"]
            if isinstance(body.get("disabled"), list):
                s["disabled"] = [x for x in body["disabled"] if isinstance(x, str)]
            save_state(s)
            return self._json({"ok": True})

        return self._json({"ok": False, "error": "not found"}, 404)


def log_hit(obj: dict) -> None:
    with _lock:
        with open(HITS, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def lan_ips():
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    return ips


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    os.makedirs(ABHU, exist_ok=True)
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("=" * 64)
    print(" NVH CONTROL · FFPROXY local — cổng", port)
    for ip in lan_ips():
        print(f"   panel:  http://{ip}:{port}/")
    print(f"   local:  http://127.0.0.1:{port}/")
    print(f"   abhu:   {ABHU}")
    print("=" * 64)
    print(" 1) vào /admin tạo key test + dán CDN URL")
    print(" 2) tải cấu hình ProxyPin ở trang chủ, import vào ProxyPin")
    print(" 3) mở /menu, nhập Secret vừa tạo, bật/tắt, Apply")
    print("=" * 64)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
