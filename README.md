# Minimig (Amiga) for Game Bub

An Amiga 500 / 600 / 1200 core for the [Game Bub](https://gamebub.net/) handheld,
ported from [Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer)
to the [Game Bub core framework](https://docs.gamebub.net/developing-cores/overview/)
(v1.1.0-beta5).

The chipset (OCS, ECS, AGA), the CIAs, Paula's audio and floppy controller and both
CPUs (fx68k for the 68000, TG68K for the 68010 and 68EC020) are the MiSTer core's own
RTL, imported unchanged except for a few small patches (see *Upstream RTL*). What the
MiSTer's ARM (Main_MiSTer) and its framework do around the core is done here by the
FPGA itself: configuration, the Kickstart and cartridge upload, the floppy drive (ADF images
encoded to MFM and decoded back on writes) and the hard disks (the IDE drives of an
A600 / A1200) are hardware state machines, and the Game Bub's MCU only loads and
saves the files.

## Using the core

1. Copy `releases/apolkosnik.Minimig/` to `/cores/apolkosnik.Minimig/` on the Game Bub's
   microSD card.
2. Put a Kickstart ROM image on the card, its name ending in `.rom` or `.ROM` (256 KB,
   512 KB or 1 MB; the 8 KB A1000 boot ROM works too): the core asks for it every time
   it starts, after the disks (the firmware's file browser, at the last one chosen).
   Kickstart is copyrighted and not included.
3. Start the core and choose the images, all optional ("[No Selection]"): Disks 1 to 4
   are floppies (`.adf`, double density, up to 1 MB), Hard disk 1 and 2 are hard disk
   images (`.hdf`, see *Hard disks*), Cartridge is a freezer cartridge's ROM (HRTmon or
   the Action Replay, see *Cartridge*).

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
v1.1.0-beta5.

### Keyboard and mouse on the dock

The stock firmware passes only gamepads to a core. With the forks of the
[handheld firmware](https://github.com/apolkosnik/gamebub/tree/minimig-net-beta5)
(commit `f1b9bec4` or later for the network and the wheel) and the
[dock firmware](https://github.com/apolkosnik/dock-firmware/tree/usb-mouse) (commit
`8bd58a4` or later for the network) a USB
keyboard and a USB or Bluetooth mouse on the dock are the Amiga's:

* the dock reads the keyboard (USB HID boot protocol) and reports the keys held; the
  handheld firmware writes every key going down or up to the core (0x1038: USB HID
  usage, bit 8 set when pressed), and the core translates it to the Amiga's raw key
  code. The Windows keys are the Amiga keys, Insert and F12 are Help, Caps Lock toggles
  as on an Amiga keyboard. Ctrl + Amiga + Amiga resets the Amiga as usual;
* the mouse's movement and buttons are written to 0x1030 / 0x1034, its wheel's clicks
  to 0x103C. The wheel is the one of MiSTer's Minimig: the Amiga reads the sum of the
  clicks in the low byte of `$DFF1F0`, so it needs a wheel driver made for MiSTer or
  the Minimig (AmigaOS has none of its own).

Both work only while the core has the focus; keys let go while the menu is open are
released when the game goes on.

The handheld firmware picks the cores it sends them to by their ID (`core.json`): this
core's, `apolkosnik.Minimig`, and that ID with letters or digits after it, which is a
build variant with the same registers (`apolkosnik.Minimig040`, see
[variants/ap68040](variants/ap68040/README.md)). The fork's builds up to `f4b4556f`
know only `apolkosnik.Minimig`: with those a variant gets no keyboard and no dock
mouse.

### Settings

| Setting | |
|---|---|
| Reset (apply) | restarts the Amiga with the chipset, CPU, memory and video settings below |
| Chipset | OCS (A500), ECS (A600), AGA (A1200) |
| CPU | 68000, 68010, 68EC020, 68020, 68030 |
| Memory | 512K, 512K + 512K slow, 1M chip, 2M chip, 2M chip + 2/4/8 MB fast (Zorro II), 2M chip + 32 MB fast (Zorro III: a 68020 or 68030) |
| Video | PAL, NTSC |
| DF0, DF1 | which loaded disk is in the drive, or Empty. Changing it takes the disk out for half a second, so the Amiga sees the change: this is how multi-disk games are played |
| Drives | number of floppy drives (DF2 and DF3 hold Disks 3 and 4) |
| Floppy speed | Normal or Turbo |
| Audio filter | the Amiga 500's fixed 4.4 kHz output filter |
| Stereo mix | how much of each channel goes into the other (None, 12 %, 25 %, Mono) |
| X / Y / Start / Select key | Space, Return, Esc, F1, F2, Help, Del or P |
| Picture | 256 or 240 PAL lines (see *Limitations*). 256 lines: all of them fitted to the screen, slightly uneven; 240: the top ones, each exactly two rows |

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

A request to the firmware takes a few milliseconds whatever its size, and the Amiga
asks for a few sectors at a time (on a Game Bub: 2.4 KB a request, a millisecond in the
card and the SPI and three more until the next request). So the core reads ahead: a
block that begins where the one before it ended is fetched with what follows it, 32
sectors in all, and the blocks after it come out of the core's buffer without a
request. A block anywhere else is fetched alone, as before.

### Cartridge

The last file the core asks for is a freezer cartridge, as the MiSTer core has it: choose
its ROM image (`.rom`) and the cartridge is fitted, choose "[No Selection]" and there is
none. What kind it is the image says:

* **HRTmon** (`HRTMON.ROM` of the MiSTer's or WinUAE's; it has `HRT!` in its bytes 4 to
  7): at `$A10000`, with the configuration Main_MiSTer gives it (the chipset, PAL or
  NTSC, the IDE port, the chip RAM's size);
* anything else is taken for the **Action Replay** in the
  [Action Replay V](https://github.com/apolkosnik/ActionReplay5) DeMoN v2 layout
  (`AR5.ROM`, up to 512 KB): the ROM at `$A80000`, the RAM at `$AC0000`.

**Help freezes** the Amiga and enters the cartridge: Insert or F12 on a USB keyboard on
the dock, or a button of the handheld set to Help (*X / Y / Start / Select button key*
in the settings). The key still reaches the Amiga as Help. The cartridge's image goes up
again with every **Reset (apply)**, and when the core starts.

On the 68040 variant the freeze works while the vector base register is 0, where
AmigaOS leaves it (a program that moves it takes the cartridge's entry away until it is
0 again).

### Network

The core has a Commodore **A2065** Ethernet board (Zorro II; the Amiga's `a2065.device`
and a TCP/IP stack such as Roadshow, AmiTCP or Miami drive it). Its Ethernet controller,
the Am7990 "LANCE", is in the FPGA with the board's 32 KB of RAM (`gb_a2065`; on MiSTer
the controller runs on the ARM side). Whole Ethernet frames go to the Game Bub's MCU and
come from it. With the firmware forks (see *Keyboard and mouse on the dock*) the network
is a USB Ethernet adapter on the dock, in its standard CDC Ethernet configuration (the
Realtek RTL8152 / RTL8153 adapters have one; the dock firmware selects it): the dock
passes frames between the adapter and the handheld in the 64 byte packets of the pads'
reports, 26 of them for a full frame, and the handheld's firmware between those and the
core. The dock's USB host is a full speed port shared with everything else on it, so
this is a link for tens of KB a second (about 50 KB/s measured both ways on a Game
Bub): a shell, IRC, mail, small transfers. The adapter takes every frame on its
network, since the Amiga's station address is not its own; the dock passes on only
broadcasts and what is addressed to the Amiga, so that a network's multicasts do not
fill the link. The station address is 00:80:10 and three bytes made from the handheld's
serial number, so every handheld has its own.

With the firmware fork the board is always fitted, like the sound card: on the dock or
off it, and before the Amiga starts, so that it is there at every reset. (With other
firmware the Amiga does not see a board.) The dock's adapter and its cable only decide
whether the link is up; the handheld says so when that changes while the core runs
("Network connected" / "Network unplugged (adapter or cable)").

Without a link (the handheld not on its dock, no adapter, the cable out) a frame the
Amiga sends goes nowhere, and the driver is told in the one way `a2065.device` passes
on to a stack: the LANCE's memory error. The driver then stops the chip, is offline and
says so (`S2EVENT_OFFLINE`), and the stack does not wait for answers that cannot come.
It does not come back by itself: with the link there again the interface has to be put
online from the Amiga (the stack's online command, or starting the interface again).
A real A2065 has no such thing; its driver ignores the LANCE's loss of carrier.

### Sound card

The core has MiSTer's **Toccata** sound card (MacroSystem's Zorro II board with the
AD1848 codec: 16 bit stereo up to 48 kHz; `rtl/minimig/fpga-toccata`, by ranzbak), for
AHI with its Toccata driver and `toccata.library`. Its two channels are added to
Paula's at the core's audio output. Playback only: there is no audio input. The board
is always fitted, in every configuration, as on MiSTer.

### Saving

Disk images are written back to the microSD card when the core is exited (or the Game
Bub is switched off), with the Amiga's changes, like a real disk. Exit through the menu
before switching off to be sure.

The core is built with framework v1.1.0-beta5 and needs a firmware of that beta or
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
* The CDTV of the MiSTer core and its shared folder (SHARE:) are not built: on MiSTer
  they use its DDR3 memory or its ARM side. The A2065 is the port's own (see *Network*),
  the Toccata MiSTer's (see *Sound card*; it records nothing).
* RTG (68020 or 68030, memory "2M + 32M Z3 fast"; MiSTer's P96 driver `MiSTer.card`
  unchanged) is shown on HDMI only. The handheld's panel is scanned in columns of the
  landscape picture, which a line buffer cannot feed; there the Amiga's own picture
  stays. The RTG picture is fitted to 1280 x 720 (nearest pixel, its shape kept, at most
  2048 pixels of a line; 1280 x 720 is shown one to one). Lines come from the second
  SDRAM chip as they are shown: 640 x 480 at 32 bits, 800 x 600 and 1024 x 768 at 16
  bits, and 1280 x 720, 1920 x 1080 and 1600 x 1200 at 8 bits fit the bandwidth; wider
  lines at 16 or 32 bits (1280 x 720 at 16 bits and up) do not, and show late.
* The picture is 720 pixels wide, centred on the screen's display window: the 640 high
  resolution pixels of the standard window and 40 either side, and an overscan screen
  wherever Overscan prefs put it, so a 720 pixel overscan Workbench is shown whole (a
  wider one loses its edges evenly). Each frame the core measures where Denise's display
  window opens and closes and centres the next frame on it.
  On the handheld's screen (720 x 480 visible of the panel's 800 x 480) it is one to one
  across, edge to edge, so an 80 column Workbench or CLI is sharp (a low resolution pixel is two pixels wide); on HDMI it is fitted across
  all 1280 columns (column x shows pixel x * 9 / 16).
  The screen has 480 rows. **Picture** chooses between all 256 PAL lines
  fitted to them (seven lines of every eight are two rows tall, one is one row: nothing
  is cut off, lines are slightly uneven) and the top 240 lines, each exactly two rows
  (the firmware takes 16 settings at most, so there is none for which 240). In NTSC the picture is 240 lines from the same top line as PAL's, two rows each: the 200 lines of an NTSC screen are at the very top (up to v0.9.1 they were centred, 20 lines down), a PAL-sized screen run in NTSC shows as far as the NTSC frame goes (some 220 lines), and the rows below the frame's end are black.
  Interlaced screens show their long fields only: there is memory for two frames of
  256 lines, not of both fields' 512, and the two fields in the same lines would
  flicker. The picture has the lines of one field (every other line of the screen) and
  changes at 25 Hz.
* Colour: 18 bits a pixel (6 + 6 + 6: 262,144 colours), with a fine 2 x 2 dither of the
  two bits below, so that a colour's average over four pixels is the Amiga's 24 bits to
  within 1 of 255. The 64 values a 6 bit component is shown as come out as they are, in
  every pixel (black, white, the greys of 85 and 170 among them); any other value is
  the one below it or the one above, a step of 4 or 5 of 255.
  The core keeps the picture's two frames itself (`gb_fb`): the board's 512 KiB SRAM
  holds 16 bits of 262,144 pixels and block RAM the rest (75 of the FPGA's 135 block
  RAMs; two 720 x 256 frames in block RAM alone left 9 bits a pixel, which is what the
  core showed up to v0.8.0, dithered or through a palette of 384 colours). Two frames
  it must be: the panel is scanned in columns of the landscape picture while the Amiga
  draws it in rows, so one frame written while it is shown has a diagonal seam between
  the old and the new picture on everything that moves. At 24 bits two frames need
  8.8 Mbit; the SRAM and the block RAM the rest of the core leaves are 7.6.
  Neither screen can be fed from the SRAM pixel by pixel, so the scan lines of the
  screen shown (the panel's columns, HDMI's lines) are read ahead into four line
  buffers, between the writes of the picture coming in.
* The framework scales a core's picture by the same whole factor in both directions and
  keeps its frames in block RAM; `patches/framework/` adds scaling each direction
  separately and fitting all lines to the screen height (`0001`, with a palette this
  core no longer uses), 720p HDMI (`0002`), a picture of the core's own on HDMI, for
  RTG (`0003`: the framework names each pixel, the core answers with its colour 12
  clocks later), on HDMI a picture whose width 1280 is not a multiple of fitted across
  (`0004`), and a core that keeps the frames itself and shows them through that same
  path on the panel too (`0005`: the framework still decides from the stream's timing
  which frame is written and which is shown, and builds no frame buffers);
  `tools/patch_framework.sh` applies them to the submodule.
* The handheld's panel follows the Amiga's frames, PAL's 50 a second and NTSC's 60: its
  driver is built for the shorter NTSC frame and waits in its vertical blanking for a
  longer one (up to 21.9 ms: a screen mode slower than 45.6 Hz is shown unlocked). Up
  to v0.9.0 it was built for PAL's 20 ms and showed about one NTSC frame in three.
* Hardware testing is young: the core has booted Kickstart 3.2 to the CLI on a Game Bub
  (rev 4) with a floppy image; hard disks, the dock keyboard and mouse and the cartridge
  are tested in simulation (see *Simulation*) and by the firmware's unit tests. The
  picture in the SRAM is new and tested in simulation only: the SRAM is driven as the
  Game Bub 3DO core drives it on the same board (every pin from an I/O block register,
  three clocks of 8.8 ns a word where that core runs at two of 10 ns).

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
| Main_MiSTer ApplyConfiguration(), UploadKickstart(), UploadActionReplay() | `gb_boot`: replays the same userio commands, uploads the ROM and the cartridge (with HRTmon's configuration) from SDRAM |
| Main_MiSTer minimig_fdd.cpp | `gb_floppy`: the same track encoding, sync word handling, header and data checks in hardware |
| Main_MiSTer ide.cpp | `gb_ide`: the same commands, geometry rules and virtual RDB in hardware, on the management port of the unchanged `ide.sv`; sectors through the framework's on-demand file commands |
| hps_io / hps_ext | `gb_io_master`: drives the same IO_UIO / IO_FPGA / IO_STROBE bus |
| video_mixer, scaler | `gb_video`: a 720 x 256 window as a stream of 18 bit pixels (dithered); `gb_fb`: the two frames in the SRAM and block RAM, shown on the panel and on HDMI through line buffers |
| audio_out | `gb_audio`: A500 filter, stereo mix |
| joysticks, PS/2 | `gb_input`: buttons, mouse emulation, keys |

SRAM (512 KiB, 262,144 words of 16 bits): bits 17:2 of the first 262,144 pixels of the
picture's two frames (frame 0 and 108 lines of frame 1; `gb_fb`).

SDRAM (32 MB, 16 bit words):

| Word address | |
|---|---|
| 0x000000 - 0x3FFFFF | Amiga chip RAM, slow RAM, Kickstart (as on MiSTer) |
| 0x400000 - 0x7FFFFF | Zorro II fast RAM (up to 8 MB) |
| 0xC00000 - 0xFFFFFF | the last 8 MB of the 32 MB Zorro III board (the second chip has the RTG board's 8 MB and the board's first 24 MB) |
| 0x800000 - 0x9FFFFF | disk images 1 to 4, 1 MB each |
| 0xB00000 - 0xB3FFFF | cartridge image as loaded from the microSD card |
| 0xB80000 - 0xBFFFFF | Kickstart image as loaded from the microSD card |

Host (MCU) memory map:

| Address | |
|---|---|
| 0x0000_0000 | ID "MMIG", version, debug counters (floppy sectors read/written, last floppy error, boot state; from 0x24 hard disk state, sectors read/written, geometry and size of both drives; 0x40 the frames: scan lines read for the screen, those not read in time, a pixel lost; 0x44 the cartridge image) |
| 0x0000_1000, 1004 | statistics: clocks paused / run (the firmware's convention) |
| 0x0000_1030, 1034 | mouse motion and buttons (firmware fork) |
| 0x0000_103C | mouse wheel: clicks since the write before, signed 8 bit (firmware fork) |
| 0x0000_1038 | keyboard event: USB HID usage, bit 8 set when pressed (firmware fork) |
| 0x0000_1040 - 107C | settings |
| 0x1000_0000 + n * 1 MB | disk image n (files 0 to 3) |
| 0x2000_0000 | Kickstart (file 4) |
| 0x2010_0000 | cartridge (file 7), up to 512 KB |
| 0x3000_0000 - 3FFF | sector buffer of the hard disks (files 5 and 6, on demand): 32 sectors |
| 0x0000_0050 - 005C | the A2065: frame to send / frame received state, the board fitted, the station address's last three bytes, counters (see `gb_host.sv`) |
| 0x4000_0000 - 07FF, 0x4000_1000 - 17FF | the Ethernet frame the Amiga sends (read) and the frame brought to it (write) |
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
* `0002`: the Toccata, A2065 and CDTV boards are not built (the first two come back with `0013` and `0014`).
* `0003`: `cpu_wrapper` does not offer them in the autoconfig chain.
* `0004`: registers that clocked blocks wrote with blocking assignments and other blocks
  read (the copper's jump strobes, Paula's floppy FIFO output, a few in userio) are
  written with nonblocking ones. Synthesis builds the same registers; in simulation the
  blocking writes were a race, and with Verilator 5 the copper never restarted at the
  start of a frame.
* `0005`: the second SDRAM chip: a Zorro III board of 16 MB (32 MB with `0012`), and uncached reads drain the
  rest of the SDRAM's burst in `cpu_cache_new`.
* `0006`: no `$DD4000-$DD5FFF` window. On MiSTer it is shared memory in DDR3 through
  which Main_MiSTer serves the SHARE: device; nothing serves it here.
* `0007`: Denise's display window (`window_del`) out to the top level, for `gb_video`'s
  centring of the 720 pixels.
* `0008`: the 68030's long words in one RAM transfer (the TG68K's `long_cand` /
  `ramready_l`, which MiSTer uses for its DDR3 fast RAM) also for the RTG memory (bytes
  swapped) and the Kickstart ROM's fetches; `cpu_cache_new`'s 256 x 16 byte-write RAM
  (its 64-bit lines, `LINE_TAKE`) as one block RAM. `gb_sdram_ctrl` takes the long word:
  a write is one entry of its write buffer and both words go to the SDRAM in one slot; a
  read is answered whole where the cache has the line. `cpu_cache_new` also gets the
  ports of the AP68040 variant's cache (a line answered whole, the next line read
  ahead), tied off: `gb_sdram_ctrl` has one cache instance for both builds (its
  `CPU_LINE16` and `WQN` options are the variant's; the standard core builds them as
  before).

* `0009`: no 32-bit chip bus access while the Kickstart overlays chip RAM: the SDRAM has
  no second word for the ROM there, and a CPU that reads its start address as one long
  word (the 68040 of the AP68040 variant) took a stale low half after a reset.
* `0010`: the cartridge takes the level 7 acknowledge also as an event
  (`nmi_ack_toggle`), for a CPU whose bus bridge answers the acknowledge itself (the
  AP68040 variant); tied off in the standard core.
* `0011`: no Kickstart mirror at `$A80000` while a cartridge is fitted. The mirror
  (upstream's, for the CD32) answered HRTmon's reads of its copy of the custom
  registers at `$A9F000` too, and the ROM's words were ORed into them.
* `0012`: the Zorro III memory board is 32 MB (one board, one block of memory to the
  Amiga): autoconfig size, a base compared in 32 MB, its 25 address bits to the RAM
  port. `minimig_gamebub.sv` puts its first 24 MB in the second SDRAM chip, beside the
  RTG board's 8 MB, and its last 8 MB in the top of the first, which shares its slots
  with the chipset: that part is slower, and at the board's top, where exec comes
  last.
* `0013`: the A2065's place on the chip bus brought out of `minimig.sv` (select,
  address, data, strobes in; data and the level 2 interrupt back), and `cpu_wrapper`
  offers the board in the autoconfig chain while the top level says it is fitted, with
  a serial number from there.
* `0014`: the Toccata sound card built again (the instance `0002` took out), and
  `cpu_wrapper` offers it in the autoconfig chain, as on MiSTer.
* `0015`: the Toccata's table of attenuation factors written out as constants. Vivado
  2018.3 ignores the loop that fills it ("ignoring non-constant assignment in initial
  block") and leaves out the two multipliers with it: the card would play at no
  attenuation only. `sim/gls/run_toccata_gls.sh` shows it (below).
* `0016`: the Toccata's autocalibration begins whenever the codec's mode change bit is
  taken away with ACAL set, as the AD1848's does, and not only when ACAL is first set.
  `toccata.library` waits for it every time it is loaded, with interrupts off and
  without a limit: loaded a second time without a reset between, it stopped the Amiga.

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

`tools/build_variant.sh ap68040` builds a second core, `apolkosnik.Minimig040`, with the
[AP68040](https://github.com/apolkosnik/AP68040) (a 68040 with its MMU, caches and FPU)
in place of the TG68K and the fx68k: see [variants/ap68040/README.md](variants/ap68040/README.md).

## Simulation

`sim/build.sh` builds a Verilator simulation of the whole core (`minimig_gamebub` with
all of its RTL; the TG68K is converted from VHDL with GHDL) with an SDRAM model, and a
bench (`sim/tb/sim_main.cpp`) that plays the Game Bub around it:

* the release firmware's load sequence (files in `files.json` order, settings,
  `SetupComplete`, `CoreRun`, focus) and its exit sequence (`CoreHalt`, then each
  writable file read back);
* the menu over the running Amiga, where a test asks for it: `--focus` (the focus taken
  as the menu opens, given back as it closes) and `--hwrite` (a setting, or the Reset
  action, written meanwhile);
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
| video, video_ecs, video_aga | `sim/asm/vidtest.s` builds a one bitplane picture with the copper; every pixel of the 720 x 240 frame (the picture and the border either side) is checked, with OCS, ECS and AGA and the picture at the top, middle and bottom |
| diw_l, diw_r, diw_aga | `vidtest.s` with the display window 32 pixels left (with the fetch) and 4 pixels right (without it): the 720 pixels centred on the window, every pixel checked with OCS, ECS and AGA |
| lace | `lacetest.s`: the vidtest picture in interlace, COLOR00 blue in long fields and red in short ones: every frame the core completes is a long field, one every two fields, and the picture exact |
| input | `inptest.s` copies the inputs to memory: D-pad, left stick and fire on port 2, keys (with the keyboard handshake), host mouse motion, buttons and wheel (alone, with motion, and motion and a key after it), the D-pad mouse mode, the right stick mouse, a second controller on port 1, host keyboard events (a key down and up, Caps Lock, a burst, an unknown usage) |
| audio0..3 | `audtest.s` plays on Paula channel 0; left / right levels for each stereo mix |
| floppy | `wrtest.s` writes a track with disk DMA; the bench checks the 11 sectors decoded into the image and the image saved on exit |
| colour, ham, aga256 | `coltest.s` gives every line its own background colour (256 colours a frame), still and then changing every frame; `hamtest.s` is a HAM picture, almost every pixel another colour; `aga256.s` an AGA picture of 256 colours in random pixels (`aga256_h`: on HDMI). Every pixel sent is checked against the chipset's 24 bits: each component one of the two 6 bit values around it (itself if it is one), and the mean over every flat 2 x 2 block the colour to within 1 of 255 |
| toccata, toccata_f | `toccatest.s` drives the Toccata as `toccata.library` does, on the 68000 and on the fastest CPU: autoconfig, the codec's registers, 16 bit stereo at 44100 Hz from the FIFO filled again at every level 6 interrupt; the rate of the interrupts, the status read at each, and the two channels' levels at the core's audio output |
| a2065 | `a2065test.s` drives the A2065 as `a2065.device` does: autoconfig and the station address from the serial number, the LANCE's registers, the board's RAM, the initialisation block, a frame in internal loopback received again with its CRC, a frame in two buffers and one of 20 bytes (padded to 60) sent, level 2 interrupts, and of seven frames the bench brings as the MCU four received (for the station, broadcast, a multicast group of the logical address filter, 600 bytes over three buffers) and three not (another station's, another group's, one with no descriptor left: MISS). Seven changed copies of `gb_a2065` each fail it |
| fb | `sim/fb`: `gb_fb` on its own with the SRAM model and the framework's video side, a new picture every frame, the stream stopping and going on (the menu): every pixel of every frame of the panel and of HDMI, with all 256 lines and with 240 |
| ide_part, ide_rdb, ide_slave | `idetest.s` drives the IDE port like `scsi.device`: identify, read / write sectors and multiple by LBA and CHS, set multiple, 256 sector reads, device parameters, the end of the image, an unknown command. Every byte read, the task file and the image afterwards are checked against what Main_MiSTer's rules give; with a partition image (virtual RDB), an image with an RDB (4 heads, 17 sectors) and the slave drive |
| sdram_ctrl | `sim/sdr`: `gb_sdram_ctrl` on its own with two SDRAM chip models, every port at once at random (chipset slots, CPU words, long words and lines, the host port, the RTG bursts), every word read checked against what was written, with and without the cache. In the AP68040 variant's tree also its code fetches from chip RAM under the chipset's writes: a line must never be answered as it was before a write that had ended |
| vector | `vectest.s` with the AGA chipset, where the chip bus reads a long word of chip RAM in one 32-bit access: the CPU takes its start address from the ROM, at the core's start and after the menu's Reset, whatever long word it read from chip RAM last (the ROM overlaid at 0 after a reset gets no such access: the SDRAM has the second word only for chip RAM) |
| smc | `smctest.s`: a routine in chip RAM run with the instruction cache on, changed (by the CPU: a word in each half of its 16-byte line, a byte, a long word; by the blitter; copied over) and run again seven instructions later: the new code every time. The cache in front of the SDRAM follows every write, and so does the AP68040's own instruction cache in the variant |
| smcstress | `smcstress.s`: sixteen routines in chip RAM, eight of them in one set of the 68040's instruction cache; 3000 rounds of calling one at random or changing it first (a byte write and another routine's call; a byte write and a NOP; the blitter) |
| cart_hrt, cart_ar (and `_c`, `_o`) | `carttest.s` with a cartridge image in the core's Cartridge file: `hrtstub.s` (as HRTmon: the signature, the entry, the configuration block) or `arstub.s` (the Action Replay's layout). The stub counts its entries and copies to chip RAM what it sees. Checked: the upload and HRTmon's configuration (AGA and OCS, PAL and NTSC, with and without a hard disk), the freeze by Help from a USB key and from a button, the level 7 vector given by the cartridge (none taken through the vector in RAM), the cartridge's RAM and its copy of the custom registers, HRTmon hidden until its first entry, and the Action Replay's freezes by the first word written to chip RAM, a read of CIA-A PRA and a write of CIA-B PRB, each with its cause, and its hiding after every entry. `_c`: the instruction cache on and the test in chip RAM; `_o`: the standard machine. `HRTMON=` and `AR5=` (the ROMs, not included) add `ks31_hrtmon` and `ks31_ar5`: Kickstart 3.1 frozen by Help into the real monitor, left with `x`, and frozen again |
| menu_1..4 | the menu opens over a running `z3test.s`, its Reset action, the menu closes, at four moments of the floppy server's poll: the CPU is halted while the menu is open, reset once, runs again when the menu closes, and the ROM passes from its start once more (the boot sequencer waits for the floppy server's poll to end before it takes the IO bus they share) |
| z3_030, z3_020 | `z3test.s`: the 68030 (PMOVE) or the 68020 (F-line), autoconfig of the Zorro III and RTG boards, patterns over the 32 MB board (every 64 KB of it; its three parts in the two SDRAM chips) and the RTG memory, byte and word lanes |
| ram_z3, ram_z2 | `ramtest.s` on the 68030, the Zorro III RAM (or the Zorro II RAM) and the RTG memory: longs, words and bytes written and read back in every combination, a mixed sequence of every size at every alignment (reads of what was just written carried into later writes, MOVEM blocks) compared with the same sequence in chip RAM. The bench counts the long words moved in one transfer and the SDRAM slots with both words of a long written. 16 KB written / read / copied in 14 / 18 / 22 raster lines in Zorro III RAM (19 / 22 / 32 with every long word as two transfers) |
| mmu | `mmutest.s` on the 68030: the MMU with 1 KB pages (as AmigaOS 3.2's mmu.library) maps 120 pages scattered over chip RAM. Reads and writes in scattered orders, reads whose base register is in another page, U and M set in the descriptors, a write protected page faulting after a read (memory unchanged), a remap taking effect after PFLUSHA, code in translated pages and across a page end. Also times four pages of Zorro III RAM through the MMU: 68 raster lines against 67 with the MMU off (85 before upstream's four-entry micro-TLB) |
| rtg | `rtgtest.s` on the 68030: the RTG board's ID at `$B80100` and in its autoconfigured window, the palette written as longs and read back, nine modes (8 bit palette 640 x 480, R5G6B5PC 320 x 240 from an unaligned base, B8G8R8 333 x 111 with odd base and stride, R8G8B8A8 640 x 480, 15 bit 1024 x 768 scaled down, 1100 x 300, 1280 x 720 one to one, 1920 x 1080 scaled down, 2100 x 150 cut at 2048). For each the bench (which plays the framework's HDMI side in `tb_top`) checks every pixel of a whole 1280 x 720 frame against the board's memory in the SDRAM model, and that no line was shown before it was fetched |
| ks31_hdf, ks31_rdb | with `KICK31` and `HDF31`, `HDFRDB31` set (`sim/make_hdf.sh` makes both images from the files of an ADF, with amitools): Kickstart 3.1 booting from a partition image and from an image with an RDB |
| ks13_nodisk, ks13_boot, ks31_aga | with `KICK13`, `KICK31`, `ADF13`, `ADF31` set: Kickstart 1.3 to the insert disk picture, Kickstart 1.3 booting a disk to the CLI, Kickstart 3.1 on AGA with the 68EC020 booting a disk |

`sim/bench.sh` times the loops of `sim/asm/membench.s` (Zorro III RAM read, written and
copied long by long, MOVE16 copies, computing loops, two loops run from chip RAM) on the
tree's CPU, as passes per
100 ms of the simulation; the AP68040 variant's README compares the two CPUs.

Every test of the suite also checks what is on the screen. The bench has the board's
SRAM (`sim/rtl/sram_sim.sv`: a word read is the word's only after the address stood for
three clocks; the write pulse, the address and data around it and the turning of the
data bus are checked in half clocks) and the framework's video side
(`sim/rtl/fw_video_sim.sv`: which of the two frames a picture goes to, when one is
thrown away, the panel as its display driver scans it, or with `--hdmi` the 720p
frame), and every pixel the core shows must be the frame's: on the panel exactly, on
HDMI, which may show a frame while it is written, as the frame has it or had it before.
`sim/fb/run_fb.sh` took ten changed copies of `gb_fb` (a read taken a clock early, no
idle clock where the bus turns, a short write pulse, a line buffer reused a line early,
the colour a clock early, the low bits lost, a thrown away frame written, a scaling
constant, the frame shown ignored, a line that does not end written on into the next):
each fails it. `sim/gls/run_fb_gls.sh` runs the same bench on Vivado's netlist of `gb_fb`.

`sim/hdmi720/run_hdmi720.sh` runs the framework itself: the generated HandheldTop with
the whole core, the SRAM model on its pins and the framework's hdmi module, a pixel
stream with a new picture every frame in place of the Amiga's. `+mode=0` and `1` decode
the TMDS output as a sink would: CEA-861 VIC 4 timing, the AVI InfoFrame, audio clock
regeneration and samples, and every pixel of two frames against the pictures sent (240
lines at 3x; 256 lines fit), the 720 pixels fitted across all 1280 columns, the menu's
overlay on top. `+mode=2` checks the path of the core's own picture (patch `0003`): the
core's colour output is forced to a pattern of the pixel the framework named 12 clocks
before, and every pixel of the screen must be that pattern at its own place. `+mode=3`
and `4` check the panel's pins, as the rev 4 display driver scans it: every pixel of
whole frames is the frame the driver shows (256 lines fit; 240 lines), black outside
the picture's 720 columns, the overlay on top.

`sim/gls/run_cpu_gls.sh` does the same for the AP68040 variant's CPU (see
`variants/ap68040/README.md`): the netlist of the CPU replayed against traces of the RTL
simulation, every output at every CPU clock. Vivado 2018.3 had made separate nets of
signals used in generate blocks before their declaration, and the CPU failed on the FPGA
when its instruction cache was switched on, with every simulation passing.
`tools/decl_before_use.py --check <files>` lists such signals.

`sim/gls/run_sdr_gls.sh [<tree>]` synthesizes `gb_sdram_ctrl` with the tree's CPU cache
and runs the unit test of `sim/sdr` on the netlist (in the AP68040 variant's tree with its
code cache for chip RAM and the chipset writing into the lines it holds).

`sim/gls/run_toccata_gls.sh [<tree>]` synthesizes the Toccata sound card and runs
`toccata_tb.sv` on the RTL and on the netlist: playback in four formats with the half
empty interrupt and all 64 levels of attenuation, and before and after it what
`toccata.library` 9.10 does to the card when it is loaded (`0016`); every change of the card's outputs
must come at the same clock in both. With upstream's `toccata_volume.sv` it fails at
the first level that is not zero (patch `0015`).

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

`+rstmon` prints the steps of a reset as they happen (the boot request, the sequencer
taking the IO bus, the halt and resets sent through userio, the CPU's reset), and
`+busmon=<n>` the CPU's first n bus cycles after every reset with what answered them.

For a program that hangs or crawls: `--pc-prof <ms>` samples the CPU's PC every `clk_sys`
period and prints, with every status line, the interrupt state and the 256-byte blocks
the PC was in most (at the end the addresses, from the given time on); `--watch <addr>`
adds a chip RAM word to the status lines; `--save-ram <ms>:<prefix>` writes both SDRAM
chips to files at that time, to disassemble what is running; `+smcmon=<ms>` lists the
CPU's writes to words it has fetched as code. `--check-pc <ms1>:<ms2>:<lo>:<hi>:<min>:<max>` is the same as a check: the share of the
time the PC was at `lo`..`hi` between the two times must lie within the two percentages
(the real cartridge tests: in the monitor after the freeze, in Kickstart again after it
is left). `--cart <file>` loads a cartridge image as the core's Cartridge file.

## License

GPL-3.0-or-later, as Minimig-AGA_MiSTer (`rtl/minimig/LICENSE-GPL.txt`). The TG68K is
LGPL-3.0-or-later, fx68k (Jorge Cwik) GPL-3.0-or-later. Minimig was written by Dennis van Weeren, extended by
Jakub Bednarski, Rok Krajnc, Sascha Boing, Alexey Melnikov (Sorgelig) and many others;
see the file headers.
