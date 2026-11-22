#!/bin/bash
# Speed benchmark (sim/asm/membench.s): each loop on this tree's CPU (the
# 68030, or the AP68040 in a build variant's tree) with the "2M + 32M Z3
# fast" memory preset; prints the loop's passes per 100 ms of the
# simulation (the count at 600 ms less the count at 500 ms). Needs the
# simulation built (sim/build.sh). Higher is faster; loops that run on both
# CPUs compare directly (the variant's README has both cores' results).
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
OUT=out/bench
mkdir -p $OUT
if [ -d ../rtl/ap68040 ]; then
	CPU=68040
	LOOPS="rd wr cp m16 rd_dc wr_dc cp_dc m16_dc alu mix chip chipalu"
	P=mb40_
else
	CPU=68030
	LOOPS="rd wr cp alu mix chip chipalu"
	P=mb_
fi
for l in $LOOPS; do
	./obj_dir/Vtb_top --kick asm/$P$l.rom --ms 610 --set 1048=4 --set 104C=8 \
		--check-word 500:200:FFFF:0000 --check-word 600:200:FFFF:0000 > $OUT/$l.log 2>&1 &
done
wait
echo "$CPU: passes per 100 ms (rd / wr / cp / m16: 16 KB of Zorro III RAM, m16 64 KB; _dc: the data cache on; alu / mix: 1024 rounds; chip / chipalu: 1024 rounds of a loop run from chip RAM)"
for l in $LOOPS; do
	set -- $(grep -o 'chip word 000200 = [0-9A-F]*' $OUT/$l.log | awk '{print $5}')
	[ $# = 2 ] || { echo "$l: no result (see $OUT/$l.log)"; exit 1; }
	printf "  %-7s %5d\n" $l $((16#$2 - 16#$1))
done
