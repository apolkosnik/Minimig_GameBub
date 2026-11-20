#!/usr/bin/env python3
"""Check a core's metadata (core.json, files.json, settings.json) against the
Game Bub firmware's limits (firmware/handheld/src/core/info.rs): a core whose
core.json does not fit is left out of the core list without a word.

  - core.json metadata id, name and author: at most 32 characters each (an
    author of 33 hides the core); the id is the core's folder on the card;
  - at most 16 bitstreams, 16 files, 16 settings;
  - files: label at most 16 characters, filename 32, at most 4 extensions of
    at most 8 characters; exactly one of filename, user_selected and
    dependent_on_0, and extensions for a user-selected file;
  - list settings: at most 8 items.

It also says when the ID is not one the firmware fork sends the dock's keyboard
and mouse to (firmware/lightgun/src/lib.rs, is_minimig): "apolkosnik.Minimig",
or that with letters or digits after it (a build variant). That is no error:
the core runs, without them.

Usage: tools/check_metadata.py <metadata dir> [expected id]
SPDX-License-Identifier: GPL-3.0-or-later
"""
import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    d = Path(sys.argv[1])
    errors = []
    core = json.load(open(d / "core.json"))
    m = core["metadata"]
    for k in ("id", "name", "author"):
        v = m.get(k, "")
        if not v.strip():
            errors.append(f"core.json: metadata.{k} is empty")
        if len(v) > 32:
            errors.append(f"core.json: metadata.{k} '{v}' is {len(v)} characters (at most 32)")
    if len(sys.argv) == 3 and m.get("id") != sys.argv[2]:
        errors.append(f"core.json: metadata.id '{m.get('id')}' is not '{sys.argv[2]}' (the folder on the card)")
    if len(core.get("bitstreams", [])) > 16:
        errors.append("core.json: more than 16 bitstreams")
    files = json.load(open(d / "files.json"))["files"]
    if len(files) > 16:
        errors.append("files.json: more than 16 files")
    for f in files:
        if len(f.get("label", "")) > 16:
            errors.append(f"files.json [id={f['id']}]: label '{f['label']}' longer than 16")
        if len(f.get("filename", "") or "") > 32:
            errors.append(f"files.json [id={f['id']}]: filename longer than 32")
        ext = f.get("extensions", [])
        sources = bool(f.get("filename")) + bool(f.get("user_selected")) + bool(f.get("dependent_on_0"))
        if sources != 1:
            errors.append(f"files.json [id={f['id']}]: exactly one of filename, user_selected, dependent_on_0")
        if f.get("user_selected") and not ext:
            errors.append(f"files.json [id={f['id']}]: user_selected needs extensions")
        if len(ext) > 4 or any(len(e) > 8 for e in ext):
            errors.append(f"files.json [id={f['id']}]: more than 4 extensions or one longer than 8")
    settings = json.load(open(d / "settings.json"))["settings"]
    if len(settings) > 16:
        errors.append("settings.json: more than 16 settings")
    for s in settings:
        if s.get("type") == "list" and len(s.get("items", [])) > 8:
            errors.append(f"settings.json [id={s['id']}]: more than 8 items")
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        sys.exit(1)
    base = "apolkosnik.Minimig"
    variant = m["id"][len(base):]
    if not m["id"].startswith(base) or not (variant.isascii() and (variant.isalnum() or not variant)):
        print(f"{d}: note: the firmware fork gives '{m['id']}' no dock keyboard or mouse "
              f"(it knows '{base}' and that with letters or digits after it)", file=sys.stderr)
    print(f"{d}: {m['id']} fits the firmware's limits")


if __name__ == "__main__":
    main()
