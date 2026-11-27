# Release files

Two cores, each a complete directory to copy to `/cores/` on the microSD card (add a
Kickstart ROM, see the top-level README):

* `apolkosnik.Minimig/`: the standard core (68000 to 68030), v0.11.0;
* `apolkosnik.Minimig040/`: the AP68040 build variant (`variants/ap68040`), v0.5.0. It
  is a core of its own on the card, next to the standard one.

Built with Vivado 2018.3 (`tools/build_vivado2018.sh`, `tools/build_variant.sh ap68040`)
and framework v1.1.0-beta5: they need a firmware that calls itself 1.1.0-beta5 or later
(`min_firmware`). Timing: worst setup slack +0.096 ns (standard) and +0.143 ns (68040),
no hold violations. Block RAM: 130 and 131 of the FPGA's 135.

The network, a keyboard or a mouse on the dock and the mouse's wheel need the firmware
forks (top-level README): the handheld's at commit `f1b9bec4` or later
(`apolkosnik/gamebub`, branch `minimig-net-beta5`), the dock's at `8bd58a4` or later
(`apolkosnik/dock-firmware`, branch `usb-mouse`). With the stock firmware the cores run
without them: no A2065 in the Amiga's list of boards, no dock keyboard or mouse. A
second dock mouse (the mouse in port 2) needs the handheld's branch `minimig-mouse2`
(commit `bbead72d` or later; `falcon-input-mouse2` with the Falcon core's input too).

## v0.11.0 (68040 core v0.5.0)

* **Two mice, two players.** Each player has a joystick and a mouse: the first the
  joystick in port 2 and the mouse in port 1, the second the joystick in port 1 and
  the mouse in port 2, where games with a mouse for each player (Lemmings) look for
  it. A second USB or Bluetooth mouse on the dock is the second player's (it did
  nothing before), and so are the second controller's right stick, L + D-pad and R.
  Port 2 is the joystick while that is held and the mouse once that is used. The port
  2 mouse has two buttons and no wheel.
* New setting **Ports**: Normal, Mice swapped, Pads swapped, Both swapped, Mice as one
  (both dock mice are the first player's, as before), also with the pads swapped.
* **Picture** has six choices and sets PAL or NTSC with them (the Video setting is
  gone): PAL 640 x 256, NTSC 640 x 200, PAL overscan (720), NTSC overscan (720), PAL
  800 x 480, NTSC 800 x 480. The 640 pictures show the standard screen alone, one to
  one with black around it, NTSC's 200 lines in whole multiples (two rows on the
  panel, three on HDMI). Whoever had Video on NTSC chooses an NTSC picture once.
* 800 x 480 is at the same place on the panel as the 720 picture, on both cores (it
  was shifted one way on the standard core and the other on the 68040), and centred on
  HDMI, where it now shows the 720 picture's columns.
* **Drives** counts right: 2 was one drive and 3 or 4 were two, so a second disk in
  DF1 was not seen with Drives 2. Whoever chose 3 or 4 to get DF1 now has three or
  four drives.

Tested in simulation: both cores' full suites (66 and 65 tests) passed on these
sources, with new tests of the 640 pictures and the NTSC choices, the mouse in port 2
and the Ports setting, and the second drive, and with a checker of every CPU access
to the chipset in every test. On a Game Bub: the picture's placement was set from
what the two cores showed there; these builds and the firmware branch were copied to
one, and not yet reported on.

## v0.10.0 (68040 core v0.4.0)

* Picture **800 x 480**, a third choice next to 256 and 240 lines: 800 pixels of each
  line one to one across all 800 columns of the handheld's panel (720 before, with
  bars either side), 240 lines two rows each. An Amiga line has some 828 pixels
  between its blankings, so the 800 are not centred on the standard window: its 640
  pixels are at columns 99 to 738, the border colour out to both edges. An overscan
  screen moves the picture left with it. No 256 lines in this mode: two frames of 800 x
  256 need more block RAM than the FPGA has left. On HDMI the 800 pixels are fitted
  across the 1280 columns.
* Each of the two frames is shown with the size it was written in, so changing the
  setting does not show a garbled frame.

Tested in simulation: both cores' full suites (65 and 64 tests, the Kickstart boots
among them) passed on these sources, with new tests of the 800 x 480 picture (OCS,
AGA, NTSC, HDMI, an overscan window; every pixel checked) and of the frame store
switching between the two sizes while running. Not yet run on a Game Bub.

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
