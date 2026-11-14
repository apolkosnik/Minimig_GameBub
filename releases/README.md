# Release files

`apolkosnik.Minimig/` is the complete core directory to copy to `/cores/apolkosnik.Minimig/`
on the microSD card (add a Kickstart ROM as `kick.rom`, see the top-level README). Built
with Vivado 2018.3 via `tools/build_vivado2018.sh`; timing met (WNS +0.18 ns), 38% LUTs,
71% block RAM.

This is a hardware bring-up build: everything is tested in simulation
(`sim/run_tests.sh`), but it has not yet run on a Game Bub.
