# Release files

Two cores, each a complete directory to copy to `/cores/` on the microSD card (add a
Kickstart ROM, see the top-level README):

* `apolkosnik.Minimig/`: the standard core (68000 to 68030), v0.8.0;
* `apolkosnik.Minimig040/`: the AP68040 build variant (`variants/ap68040`), v0.2.0. It
  is a core of its own on the card, next to the standard one.

Built with Vivado 2018.3 (`tools/build_vivado2018.sh`, `tools/build_variant.sh ap68040`)
and framework v1.1.0-beta4 (needs a firmware of that beta or later); timing and
utilisation: see the commit that built the bitstreams. A keyboard or mouse on the dock
needs the firmware forks (top-level README); for the 68040 core the handheld's must be
at commit `0a58bbbc` or later.

Everything is tested in simulation (`sim/run_tests.sh`; the 68040 also as the
synthesized netlist, `sim/gls`). On a Game Bub (rev 4): v0.7.0 of the standard core ran
with RTG at 1280 x 720, and the 68040 core's build before this one (0.1.3) booted
Kickstart and ran its dock keyboard and mouse. The cartridge (HRTmon, Action Replay) of
these two builds, the picture centred on the display window, the interlace field drop
(v0.7.0) and the TG68K's four-entry MMU micro-TLB (v0.7.1) are so far tested in
simulation only.
