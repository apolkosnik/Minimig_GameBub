#!/usr/bin/env python3
"""
Import the Minimig-AGA_MiSTer RTL into rtl/minimig/ for the Game Bub port.

The upstream sources are taken verbatim from a pinned commit of
https://github.com/MiSTer-devel/Minimig-AGA_MiSTer and then:

  1. renamed so the Game Bub build picks them up
       *.v   -> *.sv     (upstream relies on SystemVerilog syntax in .v files)
       *.vhd -> *.vhdl   (build_core.py only recognises .vhdl)
  2. mechanically transformed so that no side files are needed by Vivado
       - cpu_cycles: the `include "tg68k/*.vh" PAL tables are inlined
       - fx68k: microrom.mem / nanorom.mem are inlined as initial assignments
  3. patched with patches/minimig/*.patch (in sorted order) for the Game Bub
     specific changes (SDRAM pins, extra SDRAM port, removed expansion cards).

Usage:
  tools/import_minimig.py --upstream /path/to/Minimig-AGA_MiSTer [--commit SHA]

The upstream path must be a git clone that contains the requested commit.
Run from anywhere; paths are resolved relative to the repository root.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEST = REPO_ROOT / "rtl" / "minimig"
PATCH_DIR = REPO_ROOT / "patches" / "minimig"

# Pinned upstream revision (MiSTer-devel/Minimig-AGA_MiSTer MiSTer, 2026-11-23).
DEFAULT_COMMIT = "575b8e72d96ed9ecad51006d34b3a4483e61d439"

# Upstream files used by the Game Bub core (paths relative to upstream root).
# Expansion hardware that needs the MiSTer HPS or DDR3 (A2065, CDTV,
# Akiko/CD32, MT32-pi, IDE fast path) is intentionally not imported; the
# Toccata sound card (fpga-toccata) needs neither and is. RTG's
# registers (rtg.v) are; its display is the port's own (rtl/gamebub).
FILES = [
    "rtl/agnus.v",
    "rtl/agnus_audiodma.v",
    "rtl/agnus_beamcounter.v",
    "rtl/agnus_bitplanedma.v",
    "rtl/agnus_blitter.v",
    "rtl/agnus_blitter_adrgen.v",
    "rtl/agnus_blitter_barrelshifter.v",
    "rtl/agnus_blitter_fill.v",
    "rtl/agnus_blitter_minterm.v",
    "rtl/agnus_copper.v",
    "rtl/agnus_diskdma.v",
    "rtl/agnus_refresh.v",
    "rtl/agnus_spritedma.v",
    "rtl/amiga_clk.v",
    "rtl/cart.v",
    "rtl/cia_int.v",
    "rtl/cia_timera.v",
    "rtl/cia_timerb.v",
    "rtl/cia_timerd.v",
    "rtl/ciaa.v",
    "rtl/ciab.v",
    "rtl/cpu_cache_new.v",
    "rtl/cpu_cycles.v",
    "rtl/cpu_wrapper.v",
    "rtl/denise.v",
    "rtl/denise_bitplane_shifter.v",
    "rtl/denise_bitplanes.v",
    "rtl/denise_collision.v",
    "rtl/denise_colortable.v",
    "rtl/denise_hamgenerator.v",
    "rtl/denise_playfields.v",
    "rtl/denise_spritepriority.v",
    "rtl/denise_sprites.v",
    "rtl/denise_sprites_shifter.v",
    "rtl/fx68k/fx68k.sv",
    "rtl/fx68k/fx68kAlu.sv",
    "rtl/fx68k/uaddrPla.sv",
    "rtl/fpga-toccata/toccata.sv",
    "rtl/fpga-toccata/toccata_capture.sv",
    "rtl/fpga-toccata/toccata_fifo.sv",
    "rtl/fpga-toccata/toccata_playback.sv",
    "rtl/fpga-toccata/toccata_volume.sv",
    "rtl/gary.v",
    "rtl/gayle.v",
    "rtl/ide.v",
    "rtl/memory_router.v",
    "rtl/minimig.v",
    "rtl/minimig_bankmapper.v",
    "rtl/minimig_m68k_bridge.v",
    "rtl/minimig_sram_bridge.v",
    "rtl/minimig_syscontrol.v",
    "rtl/MiSTerFloppyFifo.v",
    "rtl/MiSTerFloppyi2c.v",
    "rtl/MiSTerFloppyPLL.v",
    "rtl/MiSTerFloppyRAWIO.v",
    "rtl/MiSTerFloppySHUGART.v",
    "rtl/MiSTerFloppyVirtualFluxDrive.v",
    "rtl/paula.v",
    "rtl/paula_audio.v",
    "rtl/paula_audio_channel.v",
    "rtl/paula_audio_mixer.v",
    "rtl/paula_audio_volume.v",
    "rtl/paula_floppy.v",
    "rtl/paula_floppy_fifo.v",
    "rtl/paula_intcontroller.v",
    "rtl/paula_uart.v",
    "rtl/rtg.v",
    "rtl/sdram_ctrl.v",
    "rtl/tg68k/TG68K_ALU.vhd",
    "rtl/tg68k/TG68K_MMU030.vhd",
    "rtl/tg68k/TG68K_Pack.vhd",
    "rtl/tg68k/TG68KdotC_Kernel.vhd",
    "rtl/userio.v",
]

# Files that are needed by the transformations but are not copied themselves.
INCLUDES = {
    "tg68k/m68k_cyc_pal.vh": "rtl/tg68k/m68k_cyc_pal.vh",
    "tg68k/m68k_ea_pal.vh": "rtl/tg68k/m68k_ea_pal.vh",
    "tg68k/m68k_misc_030.vh": "rtl/tg68k/m68k_misc_030.vh",
}
ROMS = {
    "microrom.mem": ("rtl/fx68k/microrom.mem", "uRam"),
    "nanorom.mem": ("rtl/fx68k/nanorom.mem", "nRam"),
}

LICENSE_FILES = ["gpl.txt", "README.md"]


def git_show(upstream: Path, commit: str, path: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(upstream), "show", f"{commit}:{path}"],
            text=True, errors="surrogateescape",
        )
    except subprocess.CalledProcessError:
        sys.exit(f"error: {path} not found at {commit} in {upstream}")


def dest_name(path: str) -> Path:
    rel = Path(path).relative_to("rtl")
    if rel.suffix == ".v":
        rel = rel.with_suffix(".sv")
    elif rel.suffix == ".vhd":
        rel = rel.with_suffix(".vhdl")
    return DEST / rel


def inline_includes(text: str, upstream: Path, commit: str) -> str:
    def repl(m):
        name = m.group(1)
        if name not in INCLUDES:
            sys.exit(f"error: unexpected include {name}")
        body = git_show(upstream, commit, INCLUDES[name]).rstrip("\n")
        return f"// ---- begin inlined {name} (import_minimig.py) ----\n{body}\n// ---- end inlined {name} ----"
    return re.sub(r'^[ \t]*`include\s+"([^"]+)"[ \t]*$', repl, text, flags=re.M)


def inline_roms(text: str, upstream: Path, commit: str) -> str:
    def repl(m):
        indent, fname, array = m.group(1), m.group(2), m.group(3)
        if fname not in ROMS or ROMS[fname][1] != array:
            sys.exit(f"error: unexpected $readmemb({fname}, {array})")
        words = [w for w in git_show(upstream, commit, ROMS[fname][0]).split() if w]
        for w in words:
            if not re.fullmatch(r"[01]+", w):
                sys.exit(f"error: bad word '{w}' in {fname}")
        width = len(words[0])
        lines = [f"{indent}// {fname} inlined by import_minimig.py ({len(words)} x {width} bits)"]
        lines += [f"{indent}{array}[{i}] = {width}'b{w};" for i, w in enumerate(words)]
        return "\n".join(lines)
    out, n = re.subn(r'^([ \t]*)\$readmemb\(\s*"([^"]+)"\s*,\s*(\w+)\s*\);[ \t]*$', repl, text, flags=re.M)
    if n != 2:
        sys.exit(f"error: expected 2 ROM initialisations in fx68k.sv, found {n}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upstream", required=True, type=Path, help="git clone of Minimig-AGA_MiSTer")
    ap.add_argument("--commit", default=None, help="upstream commit (default: pinned)")
    ap.add_argument("--no-patches", action="store_true", help="skip patches/minimig (for creating patches)")
    args = ap.parse_args()

    commit = args.commit or DEFAULT_COMMIT
    full = subprocess.check_output(["git", "-C", str(args.upstream), "rev-parse", commit], text=True).strip()

    if DEST.exists():
        for f in sorted(DEST.rglob("*"), reverse=True):
            if f.is_file():
                f.unlink()
            else:
                f.rmdir()
    DEST.mkdir(parents=True, exist_ok=True)

    for path in FILES:
        text = git_show(args.upstream, full, path)
        if path.endswith("cpu_cycles.v"):
            text = inline_includes(text, args.upstream, full)
        if path.endswith("fx68k/fx68k.sv"):
            text = inline_roms(text, args.upstream, full)
        if "`include" in re.sub(r"//.*", "", text):
            sys.exit(f"error: unhandled `include left in {path}")
        out = dest_name(path)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, errors="surrogateescape")

    (DEST / "LICENSE-GPL.txt").write_text(git_show(args.upstream, full, "gpl.txt"))
    (DEST / "UPSTREAM.md").write_text(
        "# Upstream Minimig RTL\n\n"
        "Generated by `tools/import_minimig.py`; do not edit by hand.\n"
        "Change `patches/minimig/*.patch` and re-run the import instead.\n\n"
        f"- Source: https://github.com/MiSTer-devel/Minimig-AGA_MiSTer\n"
        f"- Commit: `{full}`\n"
        f"- Licence: GPL (see LICENSE-GPL.txt and the file headers)\n\n"
        "## Files\n\n" + "".join(f"- `{p}` -> `{dest_name(p).relative_to(DEST)}`\n" for p in FILES)
        + "\n## Patches\n\n"
        + "".join(f"- `{p.name}`\n" for p in sorted(PATCH_DIR.glob("*.patch")))
    )

    if not args.no_patches:
        for patch in sorted(PATCH_DIR.glob("*.patch")):
            print(f"applying {patch.relative_to(REPO_ROOT)}")
            subprocess.run(["git", "apply", "--whitespace=nowarn", "-p1", str(patch)],
                           cwd=REPO_ROOT, check=True)

    print(f"imported {len(FILES)} files from {full[:12]} into {DEST.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
