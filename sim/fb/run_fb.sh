#!/bin/sh
# gb_fb with the SRAM model and the framework's video side (tb_fb.sv): the
# panel and HDMI, all 256 lines fitted and the first 240, several phases of
# the screen's clock. Exits 1 on any failure. R=<repo> picks another source
# tree (default: this one); FB=<file> another gb_fb (a changed one that
# must fail).
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
R=${R:-$(cd ../.. && pwd)}
OBJ=${OBJ:-obj_fb}
verilator --binary --timing -j ${JOBS:-16} -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING \
	-Wno-TIMESCALEMOD -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-INITIALDLY \
	-DTB_TOP=tb_fb --top-module tb_fb -Mdir $OBJ -O3 \
	../rtl/xilinx_sim.sv ../rtl/sram_sim.sv ../rtl/fw_video_sim.sv ${FB:-$R/rtl/gamebub/gb_fb.sv} \
	tb_fb.sv > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
rc=0
for args in ${RUNS:-"+seed=1" "+seed=2+nofit" "+seed=3+hdmi" "+seed=4+hdmi+nofit" "+seed=5" "+seed=6+hdmi"}; do
	out=$($OBJ/Vtb_fb $(echo $args | tr '+' ' ' | sed 's/ / +/g') +frames=${FRAMES:-14} 2>&1)
	echo "== $args"
	echo "$out" | grep -E "^(frames|SRAM|FAIL|TEST|\[sram\]|\[video\])" | head -24
	echo "$out" | grep -q "TEST PASSED" || rc=1
done
[ $rc = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $rc
