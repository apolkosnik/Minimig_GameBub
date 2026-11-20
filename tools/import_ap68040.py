#!/usr/bin/env python3
"""
Import the AP68040 CPU and its Minimig bus bridge for the Game Bub's AP68040
build variant (variants/ap68040, built by tools/build_variant.sh).

  1. The core: rtl/ of https://github.com/apolkosnik/AP68040 at a pinned
     commit (*.sv, fpu/*, gen/*).
  2. The bridge to the Minimig's 16-bit bus: ap68040_minimig.sv,
     ap040_bus16_adapter.v and ap040_bus_timeout.v from the AP68040 port of
     Minimig-AGA_MiSTer (https://github.com/apolkosnik/Minimig-AGA_MiSTer,
     branch ap040) at a pinned commit.
  3. variants/ap68040/patches/import/*.patch applied in sorted order (the
     RAM primitives written for Vivado 2018.3's inference, the bridge's Game
     Bub changes).
  4. Every `include of an .svh file inlined (the framework's build passes
     Vivado no include directories), and the result written flat to
     variants/ap68040/rtl/ with UPSTREAM.md.
  5. The declaration of every signal that an instance is connected to before
     it moved ahead of that instance (tools/decl_before_use.py: Vivado
     2018.3 synthesizes a separate net for such a signal inside a generate
     block, without an error).

Usage:
  tools/import_ap68040.py --ap68040 /path/to/AP68040 --minimig /path/to/Minimig-AGA_MiSTer
                          [--commit SHA] [--bridge-commit SHA]

Both paths must be git clones that contain the commits.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decl_before_use  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
VARIANT = REPO_ROOT / "variants" / "ap68040"
DEST = VARIANT / "rtl"
PATCH_DIR = VARIANT / "patches" / "import"

# AP68040 main, 2026-11-04 (Merge pull request #24, dmu-snooped-victim-push)
DEFAULT_COMMIT = "b16aa6a"
# Minimig-AGA_MiSTer branch ap040, 2026-10-18 ("Replace the AP040 with the
# AP68040 (faster branch) behind a 68040 bus bridge")
DEFAULT_BRIDGE_COMMIT = "f572ed875"

BRIDGE_FILES = ["ap68040_minimig.sv", "ap040_bus16_adapter.v", "ap040_bus_timeout.v"]

INCLUDE = re.compile(r'^\s*`include\s+"([^"]+)"\s*$')


def git(repo, *args, text=True):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=text)


def resolve(repo, commit):
    return git(repo, "rev-parse", commit + "^{commit}").strip()


def show(repo, commit, path):
    return git(repo, "show", f"{commit}:{path}")


def inline(text, headers, name, seen=()):
    """Replace each `include "x.svh" by the header's text (by base name)."""
    out = []
    for line in text.splitlines(keepends=True):
        m = INCLUDE.match(line)
        if not m:
            out.append(line)
            continue
        key = Path(m.group(1)).name
        if key not in headers:
            sys.exit(f"{name}: `include \"{m.group(1)}\" not found among the headers")
        if key in seen:
            sys.exit(f"{name}: recursive `include of {key}")
        out.append(f"// ---- inlined from {key} (tools/import_ap68040.py) ----\n")
        body = inline(headers[key], headers, key, seen + (key,))
        out.append(body if body.endswith("\n") else body + "\n")
        out.append(f"// ---- end of {key} ----\n")
    return "".join(out)


# The framework's build reads the files under rtl/ in os.walk's order (the
# directory's, not the names'), and Vivado needs a package read before the
# files that import it: the core's SystemVerilog files (the packages first)
# are written as one file.
CORE_FILE = "ap68040_core.sv"
PACKAGES = ["ap68040_pkg.sv", "ap68040_upkg.sv"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ap68040", required=True, type=Path, help="git clone of AP68040")
    ap.add_argument("--minimig", required=True, type=Path, help="git clone of the Minimig-AGA_MiSTer AP68040 port")
    ap.add_argument("--commit", default=DEFAULT_COMMIT)
    ap.add_argument("--bridge-commit", default=DEFAULT_BRIDGE_COMMIT)
    ap.add_argument("--core-from-bridge", action="store_true",
                    help="take the core too from the Minimig port's rtl/ap68040 at the bridge commit "
                         "(the copy that port was built and run with), not from the AP68040 clone")
    ap.add_argument("--patches", default=None,
                    help="comma separated prefixes of the import patches to apply (default: all), e.g. 0001,0002")
    ap.add_argument("--dest", type=Path, default=None, help="write the rtl here (default: variants/ap68040/rtl)")
    args = ap.parse_args()

    core = resolve(args.ap68040, args.commit)
    bridge = resolve(args.minimig, args.bridge_commit)

    files = {}      # name -> text (.sv / .v)
    headers = {}    # base name -> text (.svh)
    if args.core_from_bridge:
        src_repo, src_rev, src_root = args.minimig, bridge, ("rtl", "ap68040")
        core = bridge
    else:
        src_repo, src_rev, src_root = args.ap68040, core, ("rtl",)
    n = len(src_root)
    for path in git(src_repo, "ls-tree", "-r", "--name-only", src_rev, "/".join(src_root)).split():
        p = Path(path)
        if p.name in BRIDGE_FILES:
            continue
        if p.parts[n:n + 1] in (("fpu",), ("gen",)) or len(p.parts) == n + 1:
            if p.suffix == ".svh":
                headers[p.name] = show(src_repo, src_rev, path)
            elif p.suffix in (".sv", ".v"):
                if p.name in files:
                    sys.exit(f"two files named {p.name}")
                files[p.name] = show(src_repo, src_rev, path)
    for name in BRIDGE_FILES:
        files[name] = show(args.minimig, bridge, f"rtl/ap68040/{name}")

    # the patches, applied to the files as they are named here
    work = REPO_ROOT / "build" / "import_ap68040"
    subprocess.run(["rm", "-rf", str(work)], check=True)
    work.mkdir(parents=True)
    for name, text in files.items():
        (work / name).write_text(text)
    only = args.patches.split(",") if args.patches else None
    for patch in sorted(PATCH_DIR.glob("*.patch")):
        if only and not any(patch.name.startswith(x) for x in only):
            continue
        print(f"applying {patch.relative_to(REPO_ROOT)}")
        subprocess.run(["git", "apply", "--whitespace=nowarn", "-p1", "--directory=.", str(patch)],
                       cwd=work, check=True)
    for name in files:
        files[name] = (work / name).read_text()

    dest = args.dest.resolve() if args.dest else DEST
    subprocess.run(["rm", "-rf", str(dest)], check=True)
    dest.mkdir(parents=True)
    core_names = PACKAGES + sorted(n for n in files if n.endswith(".sv") and n not in PACKAGES
                                   and n not in BRIDGE_FILES)
    core_text = "".join(f"// ---- {n} ----\n" + inline(files[n], headers, n) for n in core_names)
    core_text, moved = decl_before_use.fix(core_text)
    print(f"{CORE_FILE}: {moved} declarations moved ahead of their first use")
    (dest / CORE_FILE).write_text(core_text)
    for name, text in sorted(files.items()):
        if name not in core_names:
            text, moved = decl_before_use.fix(inline(text, headers, name))
            if moved:
                print(f"{name}: {moved} declarations moved ahead of their first use")
            (dest / name).write_text(text)
    subprocess.run(["rm", "-rf", str(work)], check=True)

    if args.dest:
        print(f"imported {len(files)} files: core {core[:12]}{' (the bridge commit)' if args.core_from_bridge else ''}, bridge {bridge[:12]} into {dest}")
        return
    (VARIANT / "UPSTREAM.md").write_text(
        "# AP68040 sources of the variant\n\n"
        "Generated by `tools/import_ap68040.py`; do not edit `rtl/` by hand.\n"
        "Change `patches/import/*.patch` and re-run the import instead.\n\n"
        f"- Core: https://github.com/apolkosnik/AP68040 `{core}` (rtl/, GPL-2.0-or-later)\n"
        f"- Bridge: https://github.com/apolkosnik/Minimig-AGA_MiSTer branch ap040 `{bridge}`\n"
        f"  ({', '.join('rtl/ap68040/' + f for f in BRIDGE_FILES)}; GPL)\n"
        "- `.svh` headers inlined at their `` `include `` (the framework's build passes Vivado no\n"
        "  include directories)\n"
        f"- the core's SystemVerilog files in one, `{CORE_FILE}`, the packages first (the\n"
        "  framework's build reads the files in directory order)\n"
        "- declarations moved ahead of the instances that use them (`tools/decl_before_use.py`:\n"
        "  Vivado 2018.3 synthesizes a separate net for a signal used in a generate block before\n"
        "  its declaration)\n\n"
        "## Patches\n\n"
        + "".join(f"- `{p.name}`\n" for p in sorted(PATCH_DIR.glob("*.patch")))
    )
    print(f"imported {len(files)} files: AP68040 {core[:12]}, bridge {bridge[:12]} into {DEST.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
