#!/usr/bin/env python3
"""Prepare blog index.json and markdown for Vite public/blog/."""
import json
import shutil
import sys
from pathlib import Path

src = Path(sys.argv[1])
dest = Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
posts = []
for fp in sorted(src.glob("*.md")):
    if fp.name == "README.md":
        continue
    text = fp.read_text()
    meta, body = {}, text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            for line in parts[1].strip().splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip().strip('"')
            body = parts[2].strip()
    posts.append({
        "slug": fp.stem,
        "title": meta.get("title", fp.stem),
        "date": meta.get("date", ""),
        "roadmap_id": meta.get("roadmap_id", ""),
        "change": meta.get("change", ""),
        "body": body,
    })
    shutil.copy2(fp, dest / fp.name)
(dest / "index.json").write_text(json.dumps({"posts": posts}, ensure_ascii=False, indent=2))
print(f"prepare_blog: {len(posts)} posts -> {dest}")
