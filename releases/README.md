# Release files

Two cores, each a complete directory to copy to `/cores/` on the microSD card (add a
Kickstart ROM, see the top-level README):

* `apolkosnik.Minimig/`: the standard core (68000 to 68030), v0.9.0;
* `apolkosnik.Minimig040/`: the AP68040 build variant (`variants/ap68040`), v0.3.0. It
  is a core of its own on the card, next to the standard one.

Built with Vivado 2018.3 (`tools/build_vivado2018.sh`, `tools/build_variant.sh ap68040`)
and framework v1.1.0-beta5: they need a firmware that calls itself 1.1.0-beta5 or later
(`min_firmware`). Timing and utilisation: see the commit that built the bitstreams.

The network, a keyboard or a mouse on the dock and the mouse's wheel need the firmware
forks (top-level README): the handheld's at commit `f1b9bec4` or later
(`apolkosnik/gamebub`, branch `minimig-net-beta5`), the dock's at `8bd58a4` or later
(`apolkosnik/dock-firmware`, branch `usb-mouse`). With the stock firmware the cores run
without them: no A2065 in the Amiga's list of boards, no dock keyboard or mouse.

Everything is tested in simulation (`sim/run_tests.sh`, with the real `a2065.device` and
`toccata.library` under Kickstart 3.1; the 68040 and the Toccata also as synthesized
netlists, `sim/gls`). On a Game Bub (rev 4), with builds of these cores from the day
before the release:

* the A2065 with Roadshow, at about 50 KB/s both ways;
* the Toccata on the 68030;
* the mouse wheel (MiSTer's `WheelDriver` and `FreeWheel`);
* the picture from the frame store (the cores were used with it).

The 32 MB Zorro III board has not been reported on. Newer than those builds, and so
far tested in simulation only: the hard disks' reading
ahead, the Toccata's autocalibration at every mode change, and the A2065 saying that it
has no link. Not explained yet: the Toccata did not work on the 68040 core on the
Game Bub, though the real library sets it up there in simulation.
