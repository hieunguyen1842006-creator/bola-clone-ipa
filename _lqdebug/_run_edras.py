#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_run_edras.py — chay apply_edras_v152.py voi SRC/OUT khac (khong sua file goc)."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

SRC = "_lqdebug/v21/HeroSkin_2.bytes"
OUT = "_lqdebug/v21/HeroSkin_2_edras.bytes"

src = open(os.path.join(ROOT, "apply_edras_v152.py"), encoding="utf-8").read()
src = src.replace("SRC = '_lqdebug/v20_restored/HeroSkin_2.bytes'", "SRC = %r" % SRC)
src = src.replace("OUT = 'HeroSkin_2_v152.bytes'", "OUT = %r" % OUT)
assert SRC in src and OUT in src, "thay duong dan that bai"
exec(compile(src, "apply_edras_v152.py", "exec"), {"__name__": "__main__", "__file__": "apply_edras_v152.py"})
