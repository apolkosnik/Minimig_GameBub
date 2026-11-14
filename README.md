# Minimig (Amiga) for Game Bub

An Amiga 500 / 600 / 1200 core for the [Game Bub](https://gamebub.net/) handheld,
ported from [Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer)
to the [Game Bub core framework](https://docs.gamebub.net/developing-cores/overview/)
(v1.1.0-beta4).

The chipset (OCS, ECS, AGA), the CIAs, Paula's audio and floppy controller and both
CPUs (fx68k for the 68000, TG68K for the 68010 and 68EC020) are the MiSTer core's own
RTL, imported unchanged except for a few small patches (see *Upstream RTL*). What the
MiSTer's ARM (Main_MiSTer) and its framework do around the core is done here by the
FPGA itself: configuration, the Kickstart upload and the floppy drive (ADF images
encoded to MFM and decoded back on writes) are hardware state machines, and the Game
Bub's MCU only loads and saves the files.

## Using the core

1. Copy `releases/apolkosnik.Minimig/` to `/cores/apolkosnik.Minimig/` on the Game Bub's
   microSD card.
2. Put a Kickstart ROM image in that directory as `kick.rom` (256 KB, 512 KB or 1 MB;
   the 8 KB A1000 boot ROM works too). Kickstart is copyrighted and not included.
3. Start the core and choose the disk images (`.adf`, double density, up to 1 MB):
   Disk 1 is required, Disks 2 to 4 are optional ("[No Selection]").

The default machine is an Amiga 500 (OCS, 68000, 512 KB chip + 512 KB slow RAM, PAL),
which suits Kickstart 1.3 and most games. For Kickstart 3.x choose AGA, 68EC020 and
2 MB chip RAM, then **Reset (apply)**.

### Controls

| Game Bub (or the first dock controller) | Amiga |
|---|---|
| D-pad, left stick | joystick in port 2 |
| A / B | fire / second fire button |
| right stick | moves the mouse in port 1 |
| L (held) | D-pad moves the mouse in port 1, A and B are its left and right buttons |
| R | left mouse button (to drag while L is held) |
| X, Y, Start, Select | keys chosen in the settings (default Space, Return, F1, Esc) |
| second dock controller: D-pad, left stick, A, B | joystick in port 1 (two player games) |
| USB or Bluetooth mouse | the mouse in port 1 (needs the firmware fork, see below) |

Port 1 holds the mouse or the second joystick: as on MiSTer, pressing the second
controller's fire button switches it to the joystick, a left mouse click back to the
mouse. Dock controllers need the dock beta firmware that goes with framework
v1.1.0-beta4.

### Settings

| Setting | |
|---|---|
| Reset (apply) | restarts the Amiga with the chipset, CPU, memory and video settings below |
| Chipset | OCS (A500), ECS (A600), AGA (A1200) |
| CPU | 68000, 68010, 68EC020 |
| Memory | 512K, 512K + 512K slow, 1M chip, 1M + 512K slow, 2M chip, 2M chip + 2/4/8 MB fast |
| Video | PAL, NTSC |
| DF0, DF1 | which loaded disk is in the drive, or Empty. Changing it takes the disk out for half a second, so the Amiga sees the change: this is how multi-disk games are played |
| Drives | number of floppy drives (DF2 and DF3 hold Disks 3 and 4) |
| Floppy speed | Normal or Turbo |
| Audio filter | the Amiga 500's fixed 4.4 kHz output filter |
| Stereo mix | how much of each channel goes into the other (None, 12 %, 25 %, Mono) |
| X / Y / Start / Select key | Space, Return, Esc, F1, F2, Help, Del or P |
| Picture position | moves the 240 lines shown up or down |

Settings marked as applying on reset (chipset, CPU, memory, video) take effect with
**Reset (apply)**; the others apply at once.

### Saving

Disk images are written back to the microSD card when the core is exited (or the Game
Bub is switched off), with the Amiga's changes, like a real disk. Exit through the menu
before switching off to be sure.

The core is built with framework v1.1.0-beta4 and needs a firmware of that beta or
later. The [firmware fork](https://github.com/apolkosnik/gamebub/tree/mouse-3do) used by
the 3DO core adds the USB or Bluetooth mouse (the core takes its reports at
0x1030/0x1034). A loaded disk image is always reported at its full size when it is saved
(firmware 1.1.0-beta3 rewrote a file with as many bytes as the core reported, so a 0
would have emptied it). The release firmware may report an error on exit for Disks 2 to
4 that were not selected; the selected disks are still saved, and the fork skips the
unselected ones quietly.

## Limitations

* Floppies only: no hard disk images yet (Gayle IDE is built but has no host side; the
  framework's on-demand file commands of v1.1.0-beta4 make it possible), no CD32 or
  CDTV.
* ADF images only (no extended ADF / MFM-level images), double density.
* Up to four disk images per session; DF0 and DF1 can be switched between them while
  running.
* The 68030, RTG, Zorro III RAM and the expansion cards of the MiSTer core (Toccata,
  A2065, CDTV) are not built: on MiSTer they use its DDR3 memory or its ARM side. The
  core uses one of the two SDRAM chips (32 MB), which holds everything it needs.
* The picture is the framework's 320 x 240: the 320 low resolution pixels of the standard
  display window (high resolution pixels are averaged in pairs) and 240 of its lines. In
  PAL that is lines 8 to 247 of 256; **Picture position** chooses others.
* PAL runs at 50 Hz on the 60 Hz panel.
* **Not yet run on a Game Bub.** Everything is tested in simulation (see *Simulation*);
  the bitstream builds and meets timing.

## How it works

```
                 Game Bub MCU (files, settings, commands over SPI)
                                   |
                  HostV0 memory + command channel (framework)
                                   |
                               gb_host ----------------------+
                                   |                         |
         +-----------+------ gb_sdram_bridge             settings
         |           |             |                         |
      gb_boot    gb_floppy   SDRAM host port            gb_input, gb_audio,
         |           |             |                    gb_video
   gb_io_master (the MiSTer "HPS" I/O bus)                   |
         |           |             |                         |
   userio.v    paula_floppy.v   sdram_ctrl.v  <---  minimig (chipset), cpu_wrapper
```

| MiSTer (Minimig.sv) | Game Bub (rtl/minimig_gamebub.sv) |
|---|---|
| PLL 114 / 28 MHz | MMCM: 113.54 MHz SDRAM, 28.385 MHz Amiga (PAL 28.375 MHz +0.04 %), 181.7 MHz SPI, display clock |
| sdram_ctrl + ddram_ctrl (DDR3) | sdram_ctrl only, with a third "host" port; Zorro II fast RAM in the same SDRAM |
| Main_MiSTer ApplyConfiguration(), UploadKickstart() | `gb_boot`: replays the same userio commands, uploads the ROM from SDRAM |
| Main_MiSTer minimig_fdd.cpp | `gb_floppy`: the same track encoding, sync word handling, header and data checks in hardware |
| hps_io / hps_ext | `gb_io_master`: drives the same IO_UIO / IO_FPGA / IO_STROBE bus |
| video_mixer, scaler | `gb_video`: 320 x 240 window into the framework's frame buffer |
| audio_out | `gb_audio`: A500 filter, stereo mix |
| joysticks, PS/2 | `gb_input`: buttons, mouse emulation, keys |

SDRAM (32 MB, 16 bit words):

| Word address | |
|---|---|
| 0x000000 - 0x3FFFFF | Amiga chip RAM, slow RAM, Kickstart (as on MiSTer) |
| 0x400000 - 0x7FFFFF | Zorro II fast RAM (up to 8 MB) |
| 0x800000 - 0x9FFFFF | disk images 1 to 4, 1 MB each |
| 0xB80000 - 0xBFFFFF | Kickstart image as loaded from the microSD card |

Host (MCU) memory map:

| Address | |
|---|---|
| 0x0000_0000 | ID "MMIG", version, debug counters (floppy sectors read/written, last floppy error, boot state) |
| 0x0000_1000, 1004 | statistics: clocks paused / run (the firmware's convention) |
| 0x0000_1030, 1034 | mouse motion and buttons (firmware fork) |
| 0x0000_1040 - 107C | settings |
| 0x1000_0000 + n * 1 MB | disk image n (files 0 to 3) |
| 0x2000_0000 | Kickstart (file 4) |

Before a disk image is read back for saving, the core lets the floppy server finish a
sector it is writing into the image and holds the Amiga in reset until the image has
been read: the firmware's SPI reads cannot wait for the core, and with the chipset
stopped the SDRAM answers in time. `CoreHalt` (sent by the firmware before saving) also
waits for such a sector.

## Upstream RTL

`rtl/minimig/` is generated by `tools/import_minimig.py` from a pinned commit of
Minimig-AGA_MiSTer (see `rtl/minimig/UPSTREAM.md`): the files are renamed for the
framework's build (`.v` to `.sv`, `.vhd` to `.vhdl`), include files and microcode ROMs
are inlined, and the patches in `patches/minimig/` are applied:

* `0001`: `sdram_ctrl` with separate data in / out / output enable (the framework owns
  the tri-state buffer) and a low priority host port for the floppy server, the
  Kickstart upload and the MCU's file transfers.
* `0002`: the Toccata, A2065 and CDTV boards are not built.
* `0003`: `cpu_wrapper` does not offer them in the autoconfig chain.
* `0004`: registers that clocked blocks wrote with blocking assignments and other blocks
  read (the copper's jump strobes, Paula's floppy FIFO output, a few in userio) are
  written with nonblocking ones. Synthesis builds the same registers; in simulation the
  blocking writes were a race, and with Verilator 5 the copper never restarted at the
  start of a frame.

`rtl/gamebub/compat/` holds portable replacements for the two Altera RAM primitives the
MiSTer tree uses.

## Building

Requirements: Vivado 2023.2 or later (as the framework documents), a JDK (11 or later)
and Python 3.12 or 3.13.

```
git clone --recurse-submodules https://github.com/apolkosnik/Minimig_GameBub
cd Minimig_GameBub
./mill root.buildCore --target gamebub_rev4
```

The bitstream is written to `build/MinimigCore-gamebub_rev4/MinimigCore-gamebub_rev4.bit`.
Vivado 2018.3 also builds the core: `tools/build_vivado2018.sh` runs the framework
flow, removes the two `xpm_fifo_async` parameters that the 2018.3 XPM library does not
have, sets timing-driven implementation directives and fails if timing is not met.

## Simulation

`sim/build.sh` builds a Verilator simulation of the whole core (`minimig_gamebub` with
all of its RTL; the TG68K is converted from VHDL with GHDL) with an SDRAM model, and a
bench (`sim/tb/sim_main.cpp`) that plays the Game Bub around it:

* the release firmware's load sequence (files in `files.json` order, settings,
  `SetupComplete`, `CoreRun`, focus) and its exit sequence (`CoreHalt`, then each
  writable file read back);
* the framework's SPI receiver as it drives the HostV0 memory interface (enable held
  from one request to the next) and its frame buffer writer;
* checks on every run: files in SDRAM and read back through the host interface, settings
  read back, the SDRAM protocol (model) and pin timing (the controller's outputs only
  change with the falling SDRAM clock), the saved images against SDRAM.

`sim/run_tests.sh` runs the tests (Verilator 5, GHDL with `--synth` and vasm are
needed; `sim/build.sh` first):

| Test | |
|---|---|
| video | `sim/asm/vidtest.s` builds a one bitplane picture with the copper; every pixel of the 320 x 240 frame is checked |
| input | `inptest.s` copies the inputs to memory: D-pad, left stick and fire on port 2, keys (with the keyboard handshake), host mouse motion and buttons, the D-pad mouse mode, the right stick mouse, a second controller on port 1 |
| audio0..3 | `audtest.s` plays on Paula channel 0; left / right levels for each stereo mix |
| floppy | `wrtest.s` writes a track with disk DMA; the bench checks the 11 sectors decoded into the image and the image saved on exit |
| ks13_nodisk, ks13_boot, ks31_aga | with `KICK13`, `KICK31`, `ADF13`, `ADF31` set: Kickstart 1.3 to the insert disk picture, Kickstart 1.3 booting a disk to the CLI, Kickstart 3.1 on AGA with the 68EC020 booting a disk |

Results of the last run (Kickstart 1.3 rev 34.5, 3.1 rev 40.68 A1200, WhichAmiga 1.4):
all ten pass. Kickstart 1.3 shows its insert disk picture, boots WhichAmiga's OFS disk to
the CLI; Kickstart 3.1 boots the FFS disk and WhichAmiga reports a 68EC020, AGA Lisa and
Alice, 2 MB chip RAM.

Single runs:

```
sim/obj_dir/Vtb_top --kick kick13.rom --disk 0 game.adf --ms 10000 \
    --frames-dir out --shot-every 50 --expect-sectors 100 --exit
```

`--frames-dir` writes the frames as PPM files; see the head of `sim/tb/sim_main.cpp` for
the other options.

## License

GPL-3.0-or-later, as Minimig-AGA_MiSTer (`rtl/minimig/LICENSE-GPL.txt`). The TG68K is
LGPL-3.0-or-later, fx68k (Jorge Cwik) GPL-3.0-or-later. Minimig was written by Dennis van Weeren, extended by
Jakub Bednarski, Rok Krajnc, Sascha Boing, Alexey Melnikov (Sorgelig) and many others;
see the file headers.
