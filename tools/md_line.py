#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""md_line.py — in N dong IL cua block vmK tu file markdown da decode.

Chay: python tools/md_line.py <il.md> <vm> [start] [count]
"""
import re
import sys


def main(path: str, vm: int, start: int = 0, count: int = 20) -> None:
    md = open(path, encoding="utf-8").read()
    parts = re.split(r"^##\s+vm(\d+)\s+\((\d+)\s+l", md, flags=re.M)
    # parts: [pre, vm, n, body, vm, n, body, ...]
    for i in range(1, len(parts), 3):
        if int(parts[i]) != vm:
            continue
        body = parts[i + 2]
        fence = body.split("```")
        block = fence[1] if len(fence) > 1 else body
        lines = [x for x in block.strip().split("\n") if x.strip()]
        print(f"== vm{vm} ({len(lines)} lenh)")
        for ln in lines[start:start + count]:
            print(ln)
        return
    print(f"khong thay vm{vm}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("dung: md_line.py <il.md> <vm> [start] [count]")
    main(sys.argv[1], int(sys.argv[2]),
         int(sys.argv[3]) if len(sys.argv) > 3 else 0,
         int(sys.argv[4]) if len(sys.argv) > 4 else 20)
