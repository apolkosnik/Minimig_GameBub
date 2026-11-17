# Release files

`apolkosnik.Minimig/` is the complete core directory to copy to `/cores/apolkosnik.Minimig/`
on the microSD card (add a Kickstart ROM as `kick.rom`, see the top-level README). Built
with Vivado 2018.3 via `tools/build_vivado2018.sh` and framework v1.1.0-beta4 (needs a
firmware of that beta or later); timing and utilisation: see the commit that built the bitstream.

Everything is tested in simulation (`sim/run_tests.sh`). v0.7.0 runs on a Game Bub
(rev 4) with RTG checked there at 1280 x 720; the picture centred on the display window
and the interlace field drop are new in this build and so far tested in simulation only.
