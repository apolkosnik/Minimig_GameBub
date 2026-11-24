#!/bin/sh
# Assembles the test ROMs (vasm, Motorola syntax) into 256 KB images.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
for t in vidtest lacetest inptest audtest wrtest idetest coltest hamtest aga256 z3test rtgtest mmutest mmu040test ramtest movectest crashtest resettest vectest smctest smcdist smcstress a2065test toccatest todtest; do
	vasmm68k_mot -Fbin -quiet -o $t.bin $t.s
	python3 -c "import sys; d = open('$t.bin', 'rb').read(); open('$t.rom', 'wb').write(d + b'\xff' * (262144 - len(d)))"
	rm $t.bin
done
# the cartridge images of carttest: as they are (no padding), an even size
for t in hrtstub arstub; do
	vasmm68k_mot -Fbin -quiet -o $t.rom $t.s
	python3 -c "d = open('$t.rom', 'rb').read(); assert len(d) % 2 == 0 and len(d) >= 8, len(d)"
done
# vidtest with the display window moved: 16 low resolution pixels left
# with the fetch, 2 right without it; rtgtest with the 68040's instruction
# cache on (the AP68040 variant); ramtest for the Zorro II RAM and for the
# 68040; membench's loops (sim/bench.sh); carttest for HRTmon and for the
# Action Replay, with the instruction cache off and on
for v in "vidtest_l -DDIWH=-16 -DDDF=\$30" "vidtest_r -DDIWH=2" "rtgtest040 -DCACHE040" \
         "ramtest_z2 -DZTWO" "ramtest040 -DCPU040" "ramtest040_z2 -DCPU040 -DZTWO" \
         "mb_rd -DRD" "mb_wr -DWR" "mb_cp -DCP" "mb_alu -DALU" "mb_mix -DMIX" \
         "mb_chip -DCHIP" "mb_chipalu -DCHIPALU" "mb40_chip -DCPU040 -DCHIP" "mb40_chipalu -DCPU040 -DCHIPALU" \
         "mb40_rd -DCPU040 -DRD" "mb40_wr -DCPU040 -DWR" "mb40_cp -DCPU040 -DCP" "mb40_m16 -DCPU040 -DM16" \
         "mb40_rd_dc -DCPU040 -DDC -DRD" "mb40_wr_dc -DCPU040 -DDC -DWR" "mb40_cp_dc -DCPU040 -DDC -DCP" \
         "mb40_m16_dc -DCPU040 -DDC -DM16" "mb40_alu -DCPU040 -DDC -DALU" "mb40_mix -DCPU040 -DDC -DMIX" \
         "z3diag -DDIAG" "romtest" "systest" "systest256 -DROM256" \
         "carttest_hrt" "carttest_ar -DAR" "carttest_hrt_c -DCACHE" "carttest_ar_c -DAR -DCACHE"; do
	set -- $v
	t=$1; shift
	src=vidtest.s; case $t in rtg*) src=rtgtest.s;; ram*) src=ramtest.s;; mb*) src=membench.s;; z3*) src=z3test.s;; rom*) src=romtest.s;; sys*) src=systest.s;; cart*) src=carttest.s;; esac
	vasmm68k_mot -Fbin -quiet "$@" -o $t.bin $src
	size=262144; [ $t = systest ] && size=524288   # systest: a 512 KB ROM at $F80000
	python3 -c "import sys; d = open('$t.bin', 'rb').read(); open('$t.rom', 'wb').write(d + b'\xff' * ($size - len(d)))"
	# romtest, systest: the long at $FFFFF8 makes the ROM's longs add up to zero
	if [ $t = romtest ] || [ $t = systest ] || [ $t = systest256 ]; then python3 -c "
import struct
d = bytearray(open('$t.rom', 'rb').read())
n = len(d) // 4
d[-8:-4] = bytes(4)
s = sum(struct.unpack('>%dL' % n, bytes(d))) & 0xFFFFFFFF
d[-8:-4] = struct.pack('>L', (-s) & 0xFFFFFFFF)
assert sum(struct.unpack('>%dL' % n, bytes(d))) & 0xFFFFFFFF == 0
open('$t.rom', 'wb').write(d)"; fi
	rm $t.bin
done
# netdrv: an AmigaDOS program (the real a2065.device's test, ks31_a2065)
vasmm68k_mot -Fhunkexe -quiet -nosym -o netdrv.exe netdrv.s
vasmm68k_mot -Fhunkexe -quiet -nosym -o netdown.exe netdown.s
# mark, envram: for the boot disks of the tests with real software
vasmm68k_mot -Fhunkexe -quiet -nosym -o mark.exe mark.s
vasmm68k_mot -Fhunkexe -quiet -nosym -o envram.exe envram.s
