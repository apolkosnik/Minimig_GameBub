# Minimig (Amiga) for Game Bub

An Amiga 500 / 600 / 1200 core for the [Game Bub](https://gamebub.net/) handheld,
ported from [Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer)
to the [Game Bub core framework](https://docs.gamebub.net/developing-cores/overview/)
(v1.1.0-beta4).

The chipset (OCS, ECS, AGA), the CIAs, Paula's audio and floppy controller and both
CPUs (fx68k for the 68000, TG68K for the 68010 and 68EC020) are the MiSTer core's own
RTL, imported unchanged except for a few small patches (see *Upstream RTL*). What the
MiSTer's ARM (Main_MiSTer) and its framework do around the core is done here by the
FPGA itself: configuration, the Kickstart upload, the floppy drive (ADF images
encoded to MFM and decoded back on writes) and the hard disks (the IDE drives of an
A600 / A1200) are hardware state machines, and the Game Bub's MCU only loads and
saves the files.

## Using the core

1. Copy `releases/apolkosnik.Minimig/` to `/cores/apolkosnik.Minimig/` on the Game Bub's
   microSD card.
2. Put a Kickstart ROM image in that directory as `kick.rom` (256 KB, 512 KB or 1 MB;
   the 8 KB A1000 boot ROM works too). Kickstart is copyrighted and not included.
3. Start the core and choose the images, all optional ("[No Selection]"): Disks 1 to 4
   are floppies (`.adf`, double density, up to 1 MB), Hard disk 1 and 2 are hard disk
   images (`.hdf`, see *Hard disks*).

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
| USB or Bluetooth mouse on the dock | the mouse in port 1 (needs the firmware forks, see below) |
| USB keyboard on the dock | the Amiga's keyboard (needs the firmware forks, see below) |

Port 1 holds the mouse or the second joystick: as on MiSTer, pressing the second
controller's fire button switches it to the joystick, a left mouse click back to the
mouse. Dock controllers need the dock beta firmware that goes with framework
v1.1.0-beta4.

### Keyboard and mouse on the dock

The stock firmware passes only gamepads to a core. With the forks of the
[handheld firmware](https://github.com/apolkosnik/gamebub/tree/3do-beta4) and the
[dock firmware](https://github.com/apolkosnik/dock-firmware/tree/usb-mouse) a USB
keyboard and a USB or Bluetooth mouse on the dock are the Amiga's:

* the dock reads the keyboard (USB HID boot protocol) and reports the keys held; the
  handheld firmware writes every key going down or up to the core (0x1038: USB HID
  usage, bit 8 set when pressed), and the core translates it to the Amiga's raw key
  code. The Windows keys are the Amiga keys, Insert and F12 are Help, Caps Lock toggles
  as on an Amiga keyboard. Ctrl + Amiga + Amiga resets the Amiga as usual;
* the mouse's movement and buttons are written to 0x1030 / 0x1034.

Both work only while the core has the focus; keys let go while the menu is open are
released when the game goes on.

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
| Picture height (PAL) | All 256 lines (fitted to the screen, the default) or 240 lines, even (each line exactly two rows, 16 lines cut) |
| Picture position (PAL) | with 240 lines: which of the 256 PAL lines are shown, Top (the default), Middle, Bottom or in between |

Settings marked as applying on reset (chipset, CPU, memory, video) take effect with
**Reset (apply)**; the others apply at once.

### Hard disks

Hard disk 1 and 2 are the master and slave drive of the Amiga 600 / 1200 IDE port
(Gayle). The port is switched on when an image is chosen, and it needs a Kickstart with
an IDE driver (`scsi.device`): 2.05 of the A600HD, or 3.x of the A600 or A1200. With no
floppy in DF0 the Amiga boots from the hard disk.

Both kinds of `.hdf` work, as on MiSTer:

* an image of a whole disk, which starts with a Rigid Disk Block (made with HDToolBox,
  or by an emulator's "RDB" hardfile): its own geometry and partitions are used;
* an image of a single partition (most `.hdf` files): the core puts a Rigid Disk Block
  with one bootable FFS partition (DH0, DH1 for the slave) in front of it.

An image can be of any size up to 128 GB; it stays on the microSD card and the core
reads and writes only the sectors the Amiga asks for (the framework's on-demand file
commands), so what the Amiga writes is in the file straight away. The firmware flushes
it a second after the last write and when the core is exited.

### Saving

Disk images are written back to the microSD card when the core is exited (or the Game
Bub is switched off), with the Amiga's changes, like a real disk. Exit through the menu
before switching off to be sure.

The core is built with framework v1.1.0-beta4 and needs a firmware of that beta or
later (the forks above are built on it). A loaded disk image is always reported at its full size when it is saved
(firmware 1.1.0-beta3 rewrote a file with as many bytes as the core reported, so a 0
would have emptied it). The release firmware may report an error on exit for Disks 2 to
4 that were not selected; the selected disks are still saved, and the fork skips the
unselected ones quietly.

## Limitations

* Two hard disks on the primary IDE port; no CD-ROM, CD32 or CDTV.
* ADF images only (no extended ADF / MFM-level images), double density.
* Up to four disk images per session; DF0 and DF1 can be switched between them while
  running.
* The 68030, RTG, Zorro III RAM and the expansion cards of the MiSTer core (Toccata,
  A2065, CDTV) are not built: on MiSTer they use its DDR3 memory or its ARM side. The
  core uses one of the two SDRAM chips (32 MB), which holds everything it needs.
* The picture is 640 pixels wide, shown one to one across (640 of the handheld's 800 x
  480 panel, or of HDMI): all 640 high resolution pixels of the standard display window,
  so an 80 column Workbench or CLI is sharp; a low resolution pixel is two pixels wide.
  The screen has 480 rows. **Picture height (PAL)** chooses between all 256 PAL lines
  fitted to them (seven lines of every eight are two rows tall, one is one row: nothing
  is cut off, lines are slightly uneven) and 240 lines, each exactly two rows
  (**Picture position** chooses which 240). NTSC's 200 lines always fit, two rows each.
  Interlaced screens show one field's lines.
* Colour: two 640 x 256 frame buffers fit the FPGA's block RAM at 10 bits per pixel, not
  at the 24 of an AGA colour. A pixel is therefore stored as the index of its colour in a
  palette of 768 entries of 24 bits that the core fills with the colours that appear
  (`gb_palette`), and the framework looks the colour up when it shows the frame: colours
  are exact. An entry is reused four frames after its colour was last on screen. Only
  when more than 768 colours are in use within five frames (HAM pictures, colour ramps
  that change every frame) are the newest shown in the nearest of 256 fixed, dithered
  colours instead.
* The framework scales a core's picture by the same whole factor in both directions;
  `patches/framework/` adds scaling each direction separately, fitting all lines to the
  screen height, and the palette, which this picture needs (`tools/patch_framework.sh` applies it to
  the submodule).
* PAL runs at 50 Hz on the 60 Hz panel.
* Hardware testing is young: the core has booted Kickstart 3.2 to the CLI on a Game Bub
  (rev 4) with a floppy image; hard disks, the dock keyboard and mouse are tested in
  simulation (see *Simulation*) and by the firmware's unit tests.

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
| Main_MiSTer ide.cpp | `gb_ide`: the same commands, geometry rules and virtual RDB in hardware, on the management port of the unchanged `ide.sv`; sectors through the framework's on-demand file commands |
| hps_io / hps_ext | `gb_io_master`: drives the same IO_UIO / IO_FPGA / IO_STROBE bus |
| video_mixer, scaler | `gb_video`: 640 x 256 window into the framework's frame buffer; `gb_palette`: 24 bit colours to 10 bit palette indices |
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
| 0x0000_0000 | ID "MMIG", version, debug counters (floppy sectors read/written, last floppy error, boot state; from 0x24 hard disk state, sectors read/written, geometry and size of both drives) |
| 0x0000_1000, 1004 | statistics: clocks paused / run (the firmware's convention) |
| 0x0000_1030, 1034 | mouse motion and buttons (firmware fork) |
| 0x0000_1038 | keyboard event: USB HID usage, bit 8 set when pressed (firmware fork) |
| 0x0000_1040 - 107C | settings |
| 0x1000_0000 + n * 1 MB | disk image n (files 0 to 3) |
| 0x2000_0000 | Kickstart (file 4) |
| 0x3000_0000 - 3FFF | sector buffer of the hard disks (files 5 and 6, on demand): 32 sectors |
| 0xF000_1000 - 1014 | core -> host command: `FileGetSize`, `FileRead`, `FileWrite`, `FileFlush` and their parameters; the results are written back here |

For a hard disk block the core raises the framework's core command request with
`FileRead` (file, buffer address, offset, length); the firmware writes the bytes into the
sector buffer and the core hands them to `ide.sv`, already fetching the next block while
the Amiga reads this one. Writes go the other way with `FileWrite`. When the Amiga
boots, `FileGetSize` and one `FileRead` of the first 16 sectors tell whether a drive has
an image and which geometry it gets.

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
tools/patch_framework.sh
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
* the firmware's worker loop serving core requests (the command words read, busy, the
  on-demand file commands with the data moved in pieces of 16 KB, results, done);
* the framework's SPI receiver as it drives the HostV0 memory interface (enable held
  from one request to the next) and its frame buffer writer;
* checks on every run: files in SDRAM and read back through the host interface, settings
  read back, the SDRAM protocol (model) and pin timing (the controller's outputs only
  change with the falling SDRAM clock), the saved images against SDRAM.

`sim/run_tests.sh` runs the tests (Verilator 5, GHDL with `--synth` and vasm are
needed; `sim/build.sh` first):

| Test | |
|---|---|
| video, video_ecs, video_aga | `sim/asm/vidtest.s` builds a one bitplane picture with the copper; every pixel of the 640 x 240 frame is checked, with OCS, ECS and AGA and the picture at the top, middle and bottom |
| input | `inptest.s` copies the inputs to memory: D-pad, left stick and fire on port 2, keys (with the keyboard handshake), host mouse motion and buttons, the D-pad mouse mode, the right stick mouse, a second controller on port 1, host keyboard events (a key down and up, Caps Lock, a burst, an unknown usage) |
| audio0..3 | `audtest.s` plays on Paula channel 0; left / right levels for each stereo mix |
| floppy | `wrtest.s` writes a track with disk DMA; the bench checks the 11 sectors decoded into the image and the image saved on exit |
| colour | `coltest.s` gives every line its own background colour (256 colours a frame): a still picture is exact in every pixel; then the colours change every frame until the palette runs out, and no entry may change while a frame using it can still be shown |
| ide_part, ide_rdb, ide_slave | `idetest.s` drives the IDE port like `scsi.device`: identify, read / write sectors and multiple by LBA and CHS, set multiple, 256 sector reads, device parameters, the end of the image, an unknown command. Every byte read, the task file and the image afterwards are checked against what Main_MiSTer's rules give; with a partition image (virtual RDB), an image with an RDB (4 heads, 17 sectors) and the slave drive |
| ks31_hdf, ks31_rdb | with `KICK31` and `HDF31`, `HDFRDB31` set (`sim/make_hdf.sh` makes both images from the files of an ADF, with amitools): Kickstart 3.1 booting from a partition image and from an image with an RDB |
| ks13_nodisk, ks13_boot, ks31_aga | with `KICK13`, `KICK31`, `ADF13`, `ADF31` set: Kickstart 1.3 to the insert disk picture, Kickstart 1.3 booting a disk to the CLI, Kickstart 3.1 on AGA with the 68EC020 booting a disk |

Results of the last run (Kickstart 1.3 rev 34.5, 3.1 rev 40.68 A1200, WhichAmiga 1.4):
all fifteen pass. Kickstart 1.3 shows its insert disk picture, boots WhichAmiga's OFS disk
to the CLI; Kickstart 3.1 boots the FFS disk and WhichAmiga reports a 68EC020, AGA Lisa
and Alice, 2 MB chip RAM. From both hard disk images Kickstart 3.1 boots to the same
report, now with Gayle among the chips.

Single runs:

```
sim/obj_dir/Vtb_top --kick kick13.rom --disk 0 game.adf --ms 10000 \
    --frames-dir out --shot-every 50 --expect-sectors 100 --exit
```

```
sim/obj_dir/Vtb_top --kick kick31.rom --hdf 0 disk.hdf --set 1044=2 --set 1048=2 \
    --set 104C=4 --ms 12000 --frames-dir out --shot-every 50 --fw-verbose
```

`--frames-dir` writes the frames as PPM files; see the head of `sim/tb/sim_main.cpp` for
the other options.

## License

GPL-3.0-or-later, as Minimig-AGA_MiSTer (`rtl/minimig/LICENSE-GPL.txt`). The TG68K is
LGPL-3.0-or-later, fx68k (Jorge Cwik) GPL-3.0-or-later. Minimig was written by Dennis van Weeren, extended by
Jakub Bednarski, Rok Krajnc, Sascha Boing, Alexey Melnikov (Sorgelig) and many others;
see the file headers.
