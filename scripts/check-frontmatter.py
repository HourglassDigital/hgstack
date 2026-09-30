#!/usr/bin/env python3
"""Validate SKILL.md frontmatter: delimited, a YAML mapping, with name and description.

Usage: check-frontmatter.py [file ...]   (defaults to every skills/*/SKILL.md)
"""
import glob
import re
import sys

import yaml


def check(path):
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---\n"):
        return "does not open with a --- line"
    close = re.search(r"^---[ \t]*$", text[4:], re.MULTILINE)
    if not close:
        return "has no closing --- line"
    try:
        data = yaml.safe_load(text[4:4 + close.start()])
    except yaml.YAMLError as e:
        return f"YAML parse failed: {e}"
    if not isinstance(data, dict):
        return "frontmatter is not a mapping"
    missing = [k for k in ("name", "description") if not data.get(k)]
    if missing:
        return f"missing {', '.join(missing)}"
    return None


files = sys.argv[1:] or sorted(glob.glob("skills/*/SKILL.md"))
if not files:
    print("No SKILL.md files found")
    sys.exit(1)

failed = 0
for f in files:
    err = check(f)
    if err:
        print(f"FAIL {f}: {err}")
        failed = 1
print(f"{len(files)} SKILL.md file(s) checked")
sys.exit(failed)
