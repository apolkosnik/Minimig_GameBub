# Release files

Two cores, each a complete directory to copy to `/cores/` on the microSD card (add a
Kickstart ROM, see the top-level README):

* `apolkosnik.Minimig/`: the standard core (68000 to 68030), v0.9.1;
* `apolkosnik.Minimig040/`: the AP68040 build variant (`variants/ap68040`), v0.3.1. It
  is a core of its own on the card, next to the standard one.

Built with Vivado 2018.3 (`tools/build_vivado2018.sh`, `tools/build_variant.sh ap68040`)
and framework v1.1.0-beta5: they need a firmware that calls itself 1.1.0-beta5 or later
(`min_firmware`). Timing: worst setup slack +0.009 ns (standard) and +0.049 ns (68040),
no hold violations.

The network, a keyboard or a mouse on the dock and the mouse's wheel need the firmware
forks (top-level README): the handheld's at commit `f1b9bec4` or later
(`apolkosnik/gamebub`, branch `minimig-net-beta5`), the dock's at `8bd58a4` or later
(`apolkosnik/dock-firmware`, branch `usb-mouse`). With the stock firmware the cores run
without them: no A2065 in the Amiga's list of boards, no dock keyboard or mouse.

## v0.9.1 (68040 core v0.3.1)

* NTSC on the handheld's panel: every frame is shown. The panel's driver was built for
  PAL's 20 ms frame and showed about one NTSC frame in three, so NTSC games and demos
  ran visibly at a third to half their rate. It is now built for NTSC's 16.7 ms and
  waits in its blanking for PAL's longer frame.
* NTSC picture at the very top: 240 lines from the display window's top line, as in
  PAL (before, NTSC's 200 lines were centred 20 lines down). The rows below the NTSC
  frame's end are black.
* Standard core: the CPU cache no longer takes in a write that was never made (a
  select that lingers a clock after a transfer, beside the next transfer's address).
  It could have given rare wrong reads from fast RAM with the 68020 / 68030 cache on.
  The 68040 core was not affected.
* Upstream Minimig `575b8e7`: CIA time of day counter no longer loses its carry when
  the CPU writes something else (DiagROM's CIA-B TOD test).

Tested in simulation: both cores' full suites (56 and 55 tests) passed with the first
three changes before the last two were added; then the standard core's ROM tests (49,
including new NTSC picture and time of day tests) passed with all of them. Not rerun on
the final sources: the long Kickstart boot tests and the 68040 core's suite.

On a Game Bub (rev 4) these builds have been run in NTSC, which showed the picture
starting below the top (fixed in these bitstreams). Not yet reported on: the full
frame rate in NTSC on the panel, the cache fix and the time of day fix.

Known: Nexus 7 (Andromeda) in NTSC draws the objects of its "Shade Cluster" part all
white; not yet known whether the core or the demo's PAL timing is the cause.
