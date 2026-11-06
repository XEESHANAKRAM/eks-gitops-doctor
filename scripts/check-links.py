#!/usr/bin/env python3
"""Check relative Markdown links resolve to files inside the repo.

Usage: check-links.py [repo-root]
Walks *.md files (skipping node_modules/.git), extracts links of the form
[text](target) and [text]: target, and verifies that every relative target
exists on disk. External http(s) links and pure anchors are ignored.
Exits 1 if any link is broken, printing each one.
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
REF_RE = re.compile(r"^\[[^\]]+\]:\s*(\S+)", re.MULTILINE)

broken = []
checked = 0

for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in {".git", "node_modules"}]
    for filename in filenames:
        if not filename.endswith(".md"):
            continue
        path = os.path.join(dirpath, filename)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        targets = LINK_RE.findall(text) + REF_RE.findall(text)
        for target in targets:
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target_path = target.split("#", 1)[0]
            if not target_path:
                continue
            checked += 1
            full = os.path.normpath(os.path.join(os.path.dirname(path), target_path))
            if not os.path.exists(full):
                broken.append(f"{os.path.relpath(path, ROOT)} -> {target}")

print(f"checked {checked} relative links")
if broken:
    print("BROKEN LINKS:")
    for item in broken:
        print(f"  {item}")
    sys.exit(1)
print("all links OK")
