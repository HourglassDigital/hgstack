#!/usr/bin/env python3
"""Convert a subject folder's course material to text and combine it into one file.

Usage: build_context.py [FOLDER]

Every PDF, PPTX, DOCX, MD and TXT file under FOLDER (hidden folders skipped) is
converted to text and cached in FOLDER/.tutor/text/. Only new or changed files
are converted, so re-running after a new lecture arrives is fast. All cached
text is then written, in order, to FOLDER/.tutor/course.txt with a contents
table at the top giving the line each file starts on.
"""

import json
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

EXTS = {".pdf", ".pptx", ".docx", ".md", ".txt"}
ROLE_ORDER = ["lectures", "tutorials", "assignments", "other"]
ROLE_HINTS = {
    "lectures": ("lecture", "lec", "slide", "notes", "week"),
    "tutorials": ("tutorial", "tute", "workshop", "worksheet", "problem", "exercise", "exam", "practice", "quiz"),
    "assignments": ("assignment", "assessment", "project", "spec", "rubric", "marking", "report"),
}


def role_of(rel: Path) -> str:
    text = str(rel).lower()
    for role in ("tutorials", "assignments", "lectures"):
        if any(h in text for h in ROLE_HINTS[role]):
            return role
    return "other"


def natural_key(rel: Path):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", str(rel).lower())]


def xml_text(data: bytes, para_tag: str) -> str:
    s = data.decode("utf-8", errors="replace")
    s = re.sub(rf"</{para_tag}>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    for a, b in (("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'), ("&apos;", "'")):
        s = s.replace(a, b)
    return re.sub(r"\n{3,}", "\n\n", s).strip()


def convert_pdf(path: Path) -> str:
    if shutil.which("pdftotext"):
        out = subprocess.run(
            ["pdftotext", "-layout", str(path), "-"], capture_output=True, text=True
        )
        if out.returncode == 0:
            pages = out.stdout.split("\f")
            if pages and not pages[-1].strip():
                pages.pop()
            return "\n".join(f"--- page {i} ---\n{p.rstrip()}" for i, p in enumerate(pages, 1))
    try:
        from pypdf import PdfReader
        reader = PdfReader(str(path))
        return "\n".join(
            f"--- page {i} ---\n{(pg.extract_text() or '').rstrip()}"
            for i, pg in enumerate(reader.pages, 1)
        )
    except ImportError:
        return ""


def convert_pptx(path: Path) -> str:
    with zipfile.ZipFile(path) as z:
        slides = sorted(
            (n for n in z.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
            key=lambda n: int(re.search(r"(\d+)", n).group(1)),
        )
        return "\n".join(
            f"--- slide {i} ---\n{xml_text(z.read(n), 'a:p')}" for i, n in enumerate(slides, 1)
        )


def convert_docx(path: Path) -> str:
    with zipfile.ZipFile(path) as z:
        return xml_text(z.read("word/document.xml"), "w:p")


def convert(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".pdf":
        return convert_pdf(path)
    if ext == ".pptx":
        return convert_pptx(path)
    if ext == ".docx":
        return convert_docx(path)
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    work = root / ".tutor"
    cache = work / "text"
    cache.mkdir(parents=True, exist_ok=True)
    manifest_path = work / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}

    sources = sorted(
        (
            p.relative_to(root)
            for p in root.rglob("*")
            if p.is_file()
            and p.suffix.lower() in EXTS
            and not any(part.startswith(".") for part in p.relative_to(root).parts)
        ),
        key=natural_key,
    )

    new, updated, unreadable = [], [], []
    seen = {}
    for rel in sources:
        src = root / rel
        key = str(rel)
        stamp = [src.stat().st_mtime, src.stat().st_size]
        cached = cache / (key.replace("/", "__") + ".txt")
        if manifest.get(key, {}).get("stamp") != stamp or not cached.exists():
            try:
                text = convert(src)
            except (zipfile.BadZipFile, KeyError, OSError) as e:
                text = ""
                print(f"warning: could not convert {key}: {e}", file=sys.stderr)
            cached.write_text(text, encoding="utf-8")
            (updated if key in manifest else new).append(key)
        else:
            text = cached.read_text(encoding="utf-8")
        if len(re.sub(r"--- (page|slide) \d+ ---|\s", "", text)) < 50:
            unreadable.append(key)
        seen[key] = {"stamp": stamp, "role": role_of(rel), "cache": str(cached.relative_to(root))}

    for gone in set(manifest) - set(seen):
        stale = root / manifest[gone].get("cache", "")
        if stale.is_file() and stale.parent == cache:
            stale.unlink()
    manifest_path.write_text(json.dumps(seen, indent=2))

    ordered = sorted(seen, key=lambda k: (ROLE_ORDER.index(seen[k]["role"]), natural_key(Path(k))))
    bodies = [(k, (root / seen[k]["cache"]).read_text(encoding="utf-8")) for k in ordered]

    toc_len = len(ordered) + 4
    line = toc_len + 1
    toc = []
    for k, body in bodies:
        toc.append(f"  line {line:>6}  [{seen[k]['role']}]  {k}")
        line += body.count("\n") + 3
    out = [f"COURSE MATERIAL: {root.name}", "CONTENTS", *toc, "", ""]
    for k, body in bodies:
        out += [f"===== {k} =====", body, ""]
    (work / "course.txt").write_text("\n".join(out), encoding="utf-8")

    total = sum(b.count("\n") + 3 for _, b in bodies) + toc_len
    print(json.dumps({
        "combined_file": str(work / "course.txt"),
        "files": len(ordered),
        "lines": total,
        "new": new,
        "updated": updated,
        "removed": sorted(set(manifest) - set(seen)),
        "no_text_extracted": unreadable,
        "pdftotext": bool(shutil.which("pdftotext")),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
