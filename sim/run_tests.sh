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
run colour --kick asm/coltest.rom --check-coltest 1100 --ms 4000 --set 1080=3
run ham    --kick asm/hamtest.rom --ms 900 --set 1080=3
run aga256 --kick asm/aga256.rom --ms 1000 --set 1044=2 --set 1080=3 --expect-no-fixed
run aga256t --kick asm/aga256.rom --ms 1000 --set 1044=2 --set 1080=7 --expect-no-fixed
# z3test.rom: the 68030 / 68020, the 16 MB Zorro III board and the RTG
# board's memory in the second SDRAM chip (autoconfig, patterns, lanes)
Z3CHK="--check-word 790:100:FFFF:600D --check-word 790:102:FFFF:0000 --check-word 790:10A:F000:A000 --check-word 790:10C:F000:0000 --check-word 790:10E:F000:8000 --check-word 790:110:F000:0000"
run z3_030 --kick asm/z3test.rom --ms 800 --set 1048=4 --set 104C=8 $Z3CHK --check-word 790:104:FFFF:0001
run z3_020 --kick asm/z3test.rom --ms 800 --set 1048=3 --set 104C=8 $Z3CHK --check-word 790:104:FFFF:0000
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
	[ -n "${HDF31:-}" ] && run ks31_hdf --kick "$KICK31" --hdf 0 "$HDF31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-hdd-read 60
	[ -n "${HDFRDB31:-}" ] && run ks31_rdb --kick "$KICK31" --hdf 0 "$HDFRDB31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-hdd-read 60
fi
fail=0
for i in "${!pids[@]}"; do
	wait ${pids[$i]}
	r=$(grep -E "TEST (PASSED|FAILED)" $OUT/${names[$i]}.log || echo "TEST DID NOT FINISH")
	printf "%-12s %s\n" ${names[$i]} "$r"
	case "$r" in *PASSED*) ;; *) fail=1 ;; esac
done
exit $fail
