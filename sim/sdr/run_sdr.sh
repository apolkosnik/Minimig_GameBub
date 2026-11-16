#!/bin/sh
# Directed random test of gb_sdram_ctrl with the two SDRAM chip models
# (tb_sdr.sv): several seeds, cache off and on. Exits 1 on any failure.
# R=<repo> picks another source tree (default: this one).
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
R=${R:-$(cd ../.. && pwd)}
OBJ=${OBJ:-obj_sdr}
verilator --binary --timing -j ${JOBS:-16} -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING \
	-Wno-TIMESCALEMOD -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-INITIALDLY \
	-DTB_TOP=tb_sdr --top-module tb_sdr -Mdir $OBJ \
	../rtl/xilinx_sim.sv ../rtl/sdram_sim.sv $R/rtl/gamebub/gb_sdram_ctrl.sv $R/rtl/minimig/cpu_cache_new.sv \
	$R/rtl/gamebub/compat/dpram.sv \
	tb_sdr.sv > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
rc=0
for args in "+seed=1" "+seed=2 +cache" "+seed=3" "+seed=4 +cache" "+seed=5 +cache"; do
	out=$($OBJ/Vtb_sdr $args +windows=${WINDOWS:-20000} 2>&1)
	echo "== $args"
	echo "$out" | grep -E "^(windows|data bus|SDRAM|FAIL|ERROR|TEST|\[sdram\])" | head -20
	echo "$out" | grep -q "TEST PASSED" || rc=1
done
[ $rc = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $rc
