#!/bin/bash
# Runs the simulation tests of the Game Bub Minimig core (sim/build.sh
# first). Each test prints TEST PASSED / TEST FAILED; the script fails if
# any test fails.
#
# The short tests use the test ROMs in sim/asm (built by asm/build.sh):
#   video   vidtest.rom: a copper-made 1 bitplane picture, every pixel of
#           the 320 x 240 frame checked
#   input   inptest.rom: joystick (port 2) from the D-pad and the left stick,
#           fire, keyboard (with handshake), host mouse motion and buttons,
#           D-pad mouse mode, right stick mouse, a second controller on port 1
#   audio   audtest.rom: Paula channel 0, the four stereo mix settings
#   floppy  wrtest.rom: a track written with disk DMA, decoded into the
#           image, saved on exit (CoreHalt, FileReadStart/End)
#
# Kickstart boots run when the ROMs are given (they are not included):
#   KICK13=<Kickstart 1.3 A500 ROM> KICK31=<Kickstart 3.1 A1200 ROM>
#   ADF13=<OFS bootable ADF> ADF31=<bootable ADF for 3.1>
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
cd "$(dirname "$0")"
asm/build.sh
B=./obj_dir/Vtb_top
OUT=out/tests
rm -rf $OUT; mkdir -p $OUT
python3 -c "open('$OUT/blank.adf', 'wb').write(bytes(901120))"
pids=()
names=()
run() {
	local name=$1; shift
	( "$B" "$@" > $OUT/$name.log 2>&1 ) &
	pids+=($!); names+=($name)
}
run video  --kick asm/vidtest.rom --ms 560 --check-vidtest
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
	--ms 1180
run audio0 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=0 --expect-audio-ratio 0
run audio1 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=1 --expect-audio-ratio 0.142857
run audio2 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=2 --expect-audio-ratio 0.333333
run audio3 --kick asm/audtest.rom --ms 450 --set 1064=0 --set 1068=3 --expect-audio-ratio 1
run floppy --kick asm/wrtest.rom --disk 0 $OUT/blank.adf --ms 1200 --floppy-write-test --exit
if [ -n "${KICK13:-}" ]; then
	run ks13_nodisk --kick "$KICK13" --ms 6000 --expect-boot-frame --frames-dir $OUT --shot-every 300
	[ -n "${ADF13:-}" ] && run ks13_boot --kick "$KICK13" --disk 0 "$ADF13" --ms 15000 --expect-sectors 100 --exit
fi
if [ -n "${KICK31:-}" ] && [ -n "${ADF31:-}" ]; then
	run ks31_aga --kick "$KICK31" --disk 0 "$ADF31" --set 1044=2 --set 1048=2 --set 104C=4 --ms 12000 --expect-sectors 100
fi
fail=0
for i in "${!pids[@]}"; do
	wait ${pids[$i]}
	r=$(grep -E "TEST (PASSED|FAILED)" $OUT/${names[$i]}.log || echo "TEST DID NOT FINISH")
	printf "%-12s %s\n" ${names[$i]} "$r"
	case "$r" in *PASSED*) ;; *) fail=1 ;; esac
done
exit $fail
