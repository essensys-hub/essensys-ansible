#!/usr/bin/env python3
"""Clean duplicate Ansible blockinfile sections and legacy unmarked duplicates."""
from __future__ import annotations

import re
import sys
from pathlib import Path

BLOCK_RE = re.compile(
    r"^# BEGIN ANSIBLE MANAGED (?P<name>.+?)\r?\n.*?\r?\n# END ANSIBLE MANAGED (?P=name)\r?\n?",
    re.MULTILINE | re.DOTALL,
)

# marker name -> root YAML key managed inside the block
MARKER_KEYS = {
    "CLOUD SYNC": "cloud",
    "BLOCK UNIFI": "unifi",
    "BLOCK LAN IAM": "lan_iam",
    "DATABASE": "database",
}


def dedupe_marked_blocks(text: str) -> tuple[str, bool]:
    seen: set[str] = set()
    changed = False

    def repl(match: re.Match[str]) -> str:
        nonlocal changed
        name = match.group("name")
        if name in seen:
            changed = True
            return ""
        seen.add(name)
        return match.group(0)

    return BLOCK_RE.sub(repl, text), changed


def strip_unmarked_root_sections(text: str) -> tuple[str, bool]:
    """If a marked block exists for a key, drop unmarked root-level sections with the same key."""
    present_markers = {
        key
        for suffix, key in MARKER_KEYS.items()
        if f"# BEGIN ANSIBLE MANAGED {suffix}" in text
    }
    if not present_markers:
        return text, False

    lines = text.splitlines(keepends=True)
    out: list[str] = []
    changed = False
    i = 0
    in_marker = False

    while i < len(lines):
        line = lines[i]
        if line.startswith("# BEGIN ANSIBLE MANAGED "):
            in_marker = True
            out.append(line)
            i += 1
            continue
        if line.startswith("# END ANSIBLE MANAGED "):
            in_marker = False
            out.append(line)
            i += 1
            continue

        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if not in_marker and indent == 0:
            for key in present_markers:
                if stripped.startswith(f"{key}:"):
                    changed = True
                    i += 1
                    while i < len(lines):
                        nxt = lines[i]
                        ns = nxt.lstrip()
                        ni = len(nxt) - len(ns)
                        if ns and ni == 0 and not ns.startswith("#"):
                            break
                        i += 1
                    break
            else:
                out.append(line)
                i += 1
            continue

        out.append(line)
        i += 1

    return "".join(out), changed


def main() -> int:
    path = Path(sys.argv[1])
    if not path.is_file():
        print("missing")
        return 0
    original = path.read_text(encoding="utf-8")
    text, c1 = dedupe_marked_blocks(original)
    text, c2 = strip_unmarked_root_sections(text)
    if c1 or c2:
        path.write_text(text, encoding="utf-8")
        print("deduped")
    else:
        print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
