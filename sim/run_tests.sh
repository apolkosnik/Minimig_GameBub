#!/bin/bash
# Runs the simulation tests of the Game Bub Minimig core (sim/build.sh
# first). Each test prints TEST PASSED / TEST FAILED; the script fails if
# any test fails.
#
# The short tests use the test ROMs in sim/asm (built by asm/build.sh):
#   video   vidtest.rom: a copper-made 1 bitplane picture, every pixel of
#           the 640 pixel wide frame checked; with OCS (all 256 PAL lines,
#           dithered colours), ECS (240 lines, middle, dithered) and AGA with
#           the 68EC020 (240, bottom, palette colours): AGA's picture
#           comes a clock later, and blended every pixel with its neighbour
#           before H_START took that in
#   diw_*   vidtest_l.rom: the display window and the fetch 32 high
#           resolution pixels left of the standard ones; vidtest_r.rom: the
#           window alone 4 pixels right (the line's end allows no more).
#           gb_video centres its 720 pixels on the window: every pixel must
#           be where it belongs (OCS, ECS, and AGA with palette colours)
#   lace    lacetest.rom: the vidtest picture in interlace, the border blue
#           in long fields and red in short ones: every frame the core
#           completes must be a long field, one every two fields
#   colour  coltest.rom: a different background colour on every line (256
#           colours a frame): a still picture must be exact in every pixel;
#           then the colours change every frame, the palette (gb_palette)
#           runs out, and no entry may change while a frame that uses it
#           can still be shown
#   ham     hamtest.rom: a still HAM picture, almost every pixel another
#           colour; every pixel shown in palette mode is checked against the
#           chipset's colour (exact, or the nearest fixed colour)
#   aga256  aga256.rom: a still AGA picture of 256 colours, random pixels:
#           in palette mode (aga256t: never reusing entries) every pixel
#           exact, none in the fixed colours
#   input   inptest.rom: joystick (port 2) from the D-pad and the left stick,
#           fire, keyboard (with handshake), host mouse motion and buttons,
#           D-pad mouse mode, right stick mouse, a second controller on port 1
#           and host keyboard events (USB HID usages): a key down and up,
#           Caps Lock toggling, a burst of four events, an unknown usage
#   audio   audtest.rom: Paula channel 0, the four stereo mix settings
#   mmu     mmutest.rom: the 68030's MMU translating with 1 KB pages (as
#           AmigaOS 3.2): scattered reads and writes over 120 pages, base
#           registers in other pages than the address, U / M bits, write
#           protection, remapping with PFLUSHA, code in translated pages
#   mmu040  (the AP68040 variant's tree) mmu040test.rom: the 68040's MMU
#           with 4 KB pages and its copyback data cache; z3_040 replaces
#           z3_030 / z3_020 there
#   rtg     rtgtest.rom: the RTG board's registers, palette and picture
#           (six modes, every pixel of an HDMI frame)
#   ram_*   ramtest.rom: the CPU's RAM in the SDRAM (Zorro III / Zorro II and
#           the RTG memory): every size and alignment, long words in one
#           transfer, mixed sequences compared with chip RAM; ram040_*
#           (the AP68040 variant) also with the data cache's line pushes
#           and fills; $10A..$10E timings
#   vector  vectest.rom: the start address after a reset with the chip bus's
#           32-bit access on (AGA): at the core's start and after the
#           menu's Reset
#   smc     smctest.rom: code in chip RAM changed by the CPU and by the
#           blitter and run again at once, the instruction cache on: the
#           cache in front of the SDRAM must follow every write
#   smcstress  smcstress.rom: the same at random, 3000 rounds over sixteen
#           routines, more of them in one set of the 68040's instruction
#           cache than it has ways
#   cart_*  carttest.rom with a cartridge image, the file the core takes
#           one from (the stubs hrtstub.rom, as HRTmon, and arstub.rom, in
#           the Action Replay's layout): its upload and HRTmon's
#           configuration block, the Help key's freeze (a USB key, then a
#           button set to Help) with the level 7 vector given by the
#           cartridge, its memory and its copy of the custom registers,
#           and the Action Replay's other freezes (the first word written
#           to chip RAM after a reset, a read of CIA-A PRA, a write of CIA-B
#           PRB) and its hiding again. cart_hrt, cart_ar: AGA; *_c: the
#           instruction cache on and the test in chip RAM (a 68040 caches
#           it: the Action Replay must still see the CPU leave); *_o: the
#           standard machine (the 68000 in the standard core), NTSC and a
#           hard disk for HRTmon's configuration
#   menu_*  the Game Bub menu over a running Amiga: the CPU halted while the
#           menu has the focus, the Reset action, the CPU running again when
#           the menu closes, at four moments of the floppy server's poll
#   floppy  wrtest.rom: a track written with disk DMA, decoded into the
#           image, saved on exit (CoreHalt, FileReadStart/End)
#   ide_*   idetest.rom: the Gayle IDE port with hard disk images served by
#           on-demand file commands: identify, read / write sectors and
#           multiple by LBA and CHS, set multiple, device parameters, the
#           end of the image, an unknown command; every byte read and the
#           image afterwards are checked. ide_part: a partition image
#           (virtual RDB), ide_rdb: an image with an RDB (4 heads, 17
#           sectors), ide_slave: the partition image as the slave drive
#
# Kickstart boots run when the ROMs are given (they are not included):
#   KICK13=<Kickstart 1.3 A500 ROM> KICK31=<Kickstart 3.1 A1200 ROM>
#   ADF13=<OFS bootable ADF> ADF31=<bootable ADF for 3.1>
#   HDF31=<bootable partition image> HDFRDB31=<bootable image with an RDB>
#   (sim/make_hdf.sh makes both from the files of an ADF)
# and with KICK31 the real cartridges (not included):
#   HRTMON=<HRTMON.ROM>  ks31_hrtmon: Help over the insert-disk screen, the
#           CPU in HRTmon until "x" and Return, in Kickstart again, and in
#           HRTmon after the next Help
#   AR5=<AR5.ROM>        ks31_ar5: the same with the Action Replay (Action
#           Replay V, the DeMoN v2 build), left with "x" and Return
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
cd "$(dirname "$0")"
asm/build.sh
B=./obj_dir/Vtb_top
OUT=out/tests
rm -rf $OUT; mkdir -p $OUT
python3 -c "open('$OUT/blank.adf', 'wb').write(bytes(901120))"
# hard disk images for the IDE tests: a partition image and one with an RDB
python3 - $OUT <<'PY'
import random, struct, sys
r = random.Random(1234)
open(sys.argv[1] + '/part.hdf', 'wb').write(bytes(r.getrandbits(8) for _ in range(4 * 1024 * 1024)))
d = bytearray(r.getrandbits(8) for _ in range(3 * 1024 * 1024 + 512 * 5))
rdb = bytearray(512)
rdb[0:4] = b'RDSK'
struct.pack_into('>III', rdb, 64, 0, 17, 4)   # cylinders (not used), sectors, heads
d[0:512] = rdb
open(sys.argv[1] + '/rdb.hdf', 'wb').write(d)
PY
# the SDRAM controller on its own, every port at once (sim/sdr)
sdr/run_sdr.sh > $OUT/sdr.log 2>&1 && echo "sdram_ctrl   TEST PASSED" || { echo "sdram_ctrl   TEST FAILED"; FAILED_SDR=1; }
pids=()
names=()
run() {
	local name=$1; shift
	( "$B" "$@" > $OUT/$name.log 2>&1 ) &
	pids+=($!); names+=($name)
}
run video  --kick asm/vidtest.rom --ms 560 --check-vidtest
run video_ecs --kick asm/vidtest.rom --ms 560 --check-vidtest --set 1044=1 --set 1080=0 --set 107C=8
run video_aga --kick asm/vidtest.rom --ms 560 --check-vidtest --set 1044=2 --set 1048=2 --set 1080=2 --set 107C=10
run diw_l    --kick asm/vidtest_l.rom --ms 560 --check-vidtest
run diw_r    --kick asm/vidtest_r.rom --ms 560 --check-vidtest --vidtest-data-x 36 --set 1044=1 --set 1080=0 --set 107C=8
run diw_aga  --kick asm/vidtest_l.rom --ms 560 --check-vidtest --set 1044=2 --set 1048=2 --set 1080=2 --set 107C=10
run lace     --kick asm/lacetest.rom --ms 1000 --check-vidtest --check-lace
run colour --kick asm/coltest.rom --check-coltest 1100 --ms 4000 --set 1080=3
run ham    --kick asm/hamtest.rom --ms 900 --set 1080=3
run aga256 --kick asm/aga256.rom --ms 1000 --set 1044=2 --set 1080=3 --expect-no-fixed
run aga256t --kick asm/aga256.rom --ms 1000 --set 1044=2 --set 1080=7 --expect-no-fixed
# z3test.rom: the 68030 / 68020, the 16 MB Zorro III board and the RTG
# board's memory in the second SDRAM chip (autoconfig, patterns, lanes)
Z3CHK="--check-word 790:100:FFFF:600D --check-word 790:102:FFFF:0000 --check-word 790:10A:F000:A000 --check-word 790:10C:F000:0000 --check-word 790:10E:F000:8000 --check-word 790:110:F000:0000"
RTGROM=rtgtest.rom
if [ -d ../rtl/ap68040 ]; then
	# a build variant's tree with the AP68040 (tools/stage_variant.sh): the
	# 68040 has no PMOVE (F-line, as the 68020's), and its own MMU test
	run z3_040 --kick asm/z3test.rom --ms 800 --set 1048=4 --set 104C=8 $Z3CHK --check-word 790:104:FFFF:0000
	# mmu040test.rom: the 68040's MMU with 4 KB pages (TTRs, table walk,
	# U / M, write protection, PFLUSHA, code in translated pages) and its
	# copyback data cache through the bus bridge (CINVA, CPUSHA)
	RTGROM=rtgtest040.rom   # the 68040's instruction cache on, as Kickstart has it
	run mmu040 --kick asm/mmu040test.rom --ms 1500 --set 1044=2 --set 1048=4 --set 104C=8 --check-word 1490:100:FFFF:600D --check-word 1490:102:FFFF:0000
	run ram040_z3 --kick asm/ramtest040.rom --ms 1500 --set 1048=4 --set 104C=8 --check-word 1490:100:FFFF:600D --check-word 1490:102:FFFF:0000
	run ram040_z2 --kick asm/ramtest040_z2.rom --ms 1500 --set 1048=4 --set 104C=7 --check-word 1490:100:FFFF:600D --check-word 1490:102:FFFF:0000
else
	run z3_030 --kick asm/z3test.rom --ms 800 --set 1048=4 --set 104C=8 $Z3CHK --check-word 790:104:FFFF:0001
	run z3_020 --kick asm/z3test.rom --ms 800 --set 1048=3 --set 104C=8 $Z3CHK --check-word 790:104:FFFF:0000
	# mmutest.rom: the 68030's MMU with 1 KB pages (micro-TLB, table walk, U / M,
	# write protection, PFLUSHA, code in translated pages); $10A..$10E timings
	run mmu --kick asm/mmutest.rom --ms 1600 --set 1048=4 --set 104C=8 --check-word 1590:100:FFFF:600D --check-word 1590:102:FFFF:0000
	run ram_z3 --kick asm/ramtest.rom --ms 600 --set 1048=4 --set 104C=8 --check-word 590:100:FFFF:600D --check-word 590:102:FFFF:0000
	run ram_z2 --kick asm/ramtest_z2.rom --ms 600 --set 1048=4 --set 104C=7 --check-word 590:100:FFFF:600D --check-word 590:102:FFFF:0000
fi
# vector: vectest.rom with the chipset AGA (the chip bus reads long words
# in one 32-bit access): the CPU must take its start address from the ROM
# at the core's start and after the menu's Reset, whatever long word it
# read from chip RAM last
run vector --kick asm/vectest.rom --ms 720 --set 1044=2 --set 1048=4 --set 104C=8 \
	--check-word 520:100:FFFF:600D --check-word 520:102:FFFF:0000 --check-word 520:104:FFFF:0001 \
	--focus 530.4:0 --hwrite 560.7:1040:1 --focus 600:1 --expect-resets 1 \
	--check-word 710:102:FFFF:0000 --check-word 710:104:FFFF:0002
# smc: smctest.rom: a routine in chip RAM run with the instruction cache on,
# changed (by the CPU: a word, a byte, a long word; by the blitter; copied
# over) and run again at once: the new code every time
run smc --kick asm/smctest.rom --ms 700 --set 1044=2 --set 1048=4 --set 104C=8 \
	--check-word 690:100:FFFF:600D --check-word 690:102:FFFF:0000
# smcstress: smcstress.rom: sixteen routines in chip RAM (eight of them in
# one set of the 68040's instruction cache), 3000 rounds of calling one or
# changing it first (a byte write and another call; a byte write and a NOP;
# the blitter)
run smcstress --kick asm/smcstress.rom --ms 1500 --set 1044=2 --set 1048=4 --set 104C=8 \
	--check-word 1490:100:FFFF:600D --check-word 1490:102:FFFF:0000
# cart_*: carttest.rom and a cartridge image; Help from a USB keyboard
# (Insert) and from the X button set to Help. HRTmon's configuration as its
# stub found it ($130: 22 bytes, then maxchip): ide ($13B), aga ($13D),
# NTSC ($142) and maxchip ($146) follow the machine.
CARTKEYS="--set 106C=5F --hwrite 540:1038:149 --hwrite 560:1038:049 --press 600:4:40"
CARTOK="--check-word 690:100:FFFF:600D --check-word 690:102:FFFF:0000"
# before the first key: HRTmon not entered yet; the Action Replay once, after the reset
CARTHRT="--check-word 480:100:FFFF:0001 --check-word 480:104:FFFF:0000 $CARTOK"
CARTAR="--check-word 480:100:FFFF:0002 --check-word 480:104:FFFF:0001 $CARTOK"
HRTCFG="--check-word 690:130:FFFF:0080 --check-word 690:132:FFFF:0000 --check-word 690:134:FFFF:005A --check-word 690:136:FFFF:0FFF --check-word 690:138:FFFF:FF00 --check-word 690:13E:FFFF:FF0F --check-word 690:140:FFFF:FF00 --check-word 690:144:FFFF:0001 --check-word 690:148:FFFF:0000"
HRTAGA="--check-word 690:13A:FFFF:FF00 --check-word 690:13C:FFFF:FFFF --check-word 690:142:FFFF:00FF --check-word 690:146:FFFF:0020"
HRTOCS="--check-word 690:13A:FFFF:FFFF --check-word 690:13C:FFFF:FF00 --check-word 690:142:FFFF:01FF --check-word 690:146:FFFF:0008"
run cart_hrt   --kick asm/carttest_hrt.rom   --cart asm/hrtstub.rom --ms 700 --set 1044=2 --set 1048=4 --set 104C=8 $CARTKEYS $CARTHRT $HRTCFG $HRTAGA
run cart_hrt_c --kick asm/carttest_hrt_c.rom --cart asm/hrtstub.rom --ms 700 --set 1044=2 --set 1048=4 --set 104C=8 $CARTKEYS $CARTHRT $HRTCFG $HRTAGA
run cart_hrt_o --kick asm/carttest_hrt.rom   --cart asm/hrtstub.rom --ms 700 --set 1050=1 --hdf 0 $OUT/part.hdf $CARTKEYS $CARTHRT $HRTCFG $HRTOCS
run cart_ar    --kick asm/carttest_ar.rom    --cart asm/arstub.rom  --ms 700 --set 1044=2 --set 1048=4 --set 104C=8 $CARTKEYS $CARTAR
run cart_ar_c  --kick asm/carttest_ar_c.rom  --cart asm/arstub.rom  --ms 700 --set 1044=2 --set 1048=4 --set 104C=8 $CARTKEYS $CARTAR
run cart_ar_o  --kick asm/carttest_ar.rom    --cart asm/arstub.rom  --ms 700 $CARTKEYS $CARTAR
# menu_*: the menu opens (the focus goes: the CPU is halted), its Reset
# action, the menu closes, at four moments of the floppy server's poll. The
# CPU must be halted while the menu is open, be reset once and run again
# after it, and z3test.rom must pass from the start once more. (The boot
# sequencer took the IO bus before the floppy server had ended its poll:
# the poll never ended, and neither did the halt or the reset.)
[ -d ../rtl/ap68040 ] && MENU104=0000 || MENU104=0001
MENUN=0
for t in 520.00 521.11 523.29 525.13; do
	MENUN=$((MENUN + 1))
	run menu_$MENUN --kick asm/z3test.rom --ms 1000 --set 1048=4 --set 104C=8 \
		--check-halt 510:0 --focus $t:0 --check-halt 550:1 --hwrite 560.$((MENUN * 23)):1040:1 --check-halt 595:1 \
		--focus 600:1 --check-halt 650:0 --expect-resets 1 ${Z3CHK//790:/990:} --check-word 990:104:FFFF:$MENU104
done
# rtgtest.rom: the RTG board (68030): registers at both addresses, the
# palette, nine modes (8 bit palette, 16 bit 565 and 1555, 24 bit, 32 bit;
# unaligned bases and strides, scaled up and down, 1280 x 720 one to one,
# 1920 x 1080, cut at 2048 pixels), each
# shown on the framework's external picture (HDMI, tb_top) and every pixel
# of a whole 1280 x 720 frame checked
run rtg --kick asm/$RTGROM --ms 2500 --set 1048=4 --set 104C=8 --rtg-check --rtg-modes 9 \
	--check-word 2400:100:FFFF:600D --check-word 2400:104:FFFF:0000
run input  --kick asm/inptest.rom \
	--check-word 500:100:0303:0000 --check-word 500:104:0080:0080 \
	--press 520:80:40 --check-word 545:100:0303:0003 \
	--press 580:10:40 --check-word 605:100:0303:0100 \
	--press 640:1:40 --check-word 665:104:00C0:0040 \
	--press 700:4:40 --check-word 730:108:00FF:0040 --check-word 790:108:00FF:00C0 --check-word 790:10A:FFFF:0002 \
	--mouse 800:20:-10 --check-mouse 795:850:20:-10 \
	--press 860:101:40 --check-word 885:104:00C0:0080 --check-word 885:100:0303:0000 \
	--hwrite 920:1034:2 --check-word 950:106:0400:0000 \
	--stick 960:0:-100:0:0:0:0:30 --check-word 980:100:0303:0100 \
	--stick 1000:0:0:100:-50:0:0:50 --check-mouse 995:1070:60:-40:7 \
	--slot1 --press2 1080:81:40 --check-word 1100:104:0040:0000 --check-word 1100:102:0303:0003 \
	--press2 1130:41:40 --check-word 1150:102:0303:0300 \
	--hwrite 1160:1038:104 --check-word 1200:108:00FF:0020 \
	--hwrite 1210:1038:004 --check-word 1240:108:00FF:00A0 \
	--hwrite 1250:1038:139 --check-word 1280:108:00FF:0062 \
	--hwrite 1290:1038:039 --hwrite 1300:1038:139 --check-word 1340:108:00FF:00E2 \
	--hwrite 1350:1038:1E1 --hwrite 1352:1038:11A --hwrite 1354:1038:01A --hwrite 1356:1038:0E1 \
	--hwrite 1358:1038:1FF --check-word 1420:108:00FF:00E0 --check-word 1420:10A:FFFF:000A \
	--ms 1450
run audio0 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=0 --expect-audio-ratio 0
run audio1 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=1 --expect-audio-ratio 0.142857
run audio2 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=2 --expect-audio-ratio 0.333333
run audio3 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=3 --expect-audio-ratio 1
run floppy --kick asm/wrtest.rom --disk 0 $OUT/blank.adf --ms 1200 --floppy-write-test --exit
run ide_part  --kick asm/idetest.rom --hdf 0 $OUT/part.hdf --ide-test --ms 1800
run ide_rdb   --kick asm/idetest.rom --hdf 0 $OUT/rdb.hdf  --ide-test --ms 1800
run ide_slave --kick asm/idetest.rom --hdf 1 $OUT/part.hdf --ide-test --ms 1800
if [ -n "${KICK13:-}" ]; then
	run ks13_nodisk --kick "$KICK13" --ms 6000 --expect-boot-frame --frames-dir $OUT --shot-every 300
	[ -n "${ADF13:-}" ] && run ks13_boot --kick "$KICK13" --disk 0 "$ADF13" --ms 15000 --expect-sectors 100 --exit
fi
if [ -n "${KICK31:-}" ] && [ -n "${ADF31:-}" ]; then
	run ks31_aga --kick "$KICK31" --disk 0 "$ADF31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-sectors 100
	# the 68030 with the 16 MB Zorro III board (second SDRAM chip)
	mkdir -p $OUT/ks31_030
	run ks31_030 --kick "$KICK31" --disk 0 "$ADF31" --set 1044=2 --set 1048=4 --set 104C=8 --ms 12000 --expect-sectors 100 --frames-dir $OUT/ks31_030 --shot-every 100
fi
if [ -n "${KICK31:-}" ]; then
	# the real cartridges under Kickstart 3.1: where the CPU is (--check-pc)
	# before Help (4.6 s), in the monitor, after "x" and Return, after Help again
	HELP1="--hwrite 4600:1038:149 --hwrite 4650:1038:049"
	[ -n "${HRTMON:-}" ] && run ks31_hrtmon --kick "$KICK31" --cart "$HRTMON" --set 1044=2 --set 1048=4 --set 104C=8 --ms 8400 \
		$HELP1 --hwrite 6400:1038:11B --hwrite 6450:1038:01B --hwrite 6500:1038:128 --hwrite 6550:1038:028 \
		--hwrite 7400:1038:149 --hwrite 7450:1038:049 \
		--check-pc 4000:4500:A00000:B00000:0:0 --check-pc 5300:6300:A00000:A80000:90:100 \
		--check-pc 6900:7300:A00000:B00000:0:2 --check-pc 7700:8300:A00000:A80000:90:100
	# (the Action Replay looks through memory before its prompt: 2.7 s on
	# the 68030, 3.0 s on the 68040, and takes no key before)
	[ -n "${AR5:-}" ] && run ks31_ar5 --kick "$KICK31" --cart "$AR5" --set 1044=2 --set 1048=4 --set 104C=8 --ms 9700 \
		$HELP1 --hwrite 8400:1038:11B --hwrite 8450:1038:01B --hwrite 8500:1038:128 --hwrite 8550:1038:028 \
		--check-pc 4000:4500:A00000:B00000:0:0 --check-pc 5000:8300:A80000:B00000:90:100 \
		--check-pc 9100:9600:A00000:B00000:0:2
	[ -n "${HDF31:-}" ] && run ks31_hdf --kick "$KICK31" --hdf 0 "$HDF31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-hdd-read 60
	[ -n "${HDFRDB31:-}" ] && run ks31_rdb --kick "$KICK31" --hdf 0 "$HDFRDB31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-hdd-read 60
fi
fail=${FAILED_SDR:-0}
for i in "${!pids[@]}"; do
	wait ${pids[$i]}
	r=$(grep -E "TEST (PASSED|FAILED)" $OUT/${names[$i]}.log || echo "TEST DID NOT FINISH")
	printf "%-12s %s\n" ${names[$i]} "$r"
	case "$r" in *PASSED*) ;; *) fail=1 ;; esac
done
exit $fail
