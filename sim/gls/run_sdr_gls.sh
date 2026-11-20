#!/bin/bash
# The SDRAM controller with its CPU cache, as a netlist: Vivado 2018.3
# synthesizes gb_sdram_ctrl (with the tree's cpu_cache_new: in a build
# variant's tree the AP68040's line buffers and chip RAM code cache, with
# the variant's parameters) for the board's FPGA out of context, and xsim
# runs the unit test of sim/sdr (tb_sdr.sv: every port at random, every
# word read checked) on the netlist with the same seeds as sim/sdr/run_sdr.sh.
#
#   sim/gls/run_sdr_gls.sh [<tree>]      (default: this repository)
#
# WORK=<dir> (default <tree>/sim/gls/work_sdr) keeps the netlist; it is made
# again when a source is newer. WINDOWS=<n> as for run_sdr.sh.
# Needs Vivado: VIVADO=/opt/tools/Xilinx/Vivado/2018.3 by default.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "${1:-$HERE/../..}" && pwd)
W=${WORK:-$TREE/sim/gls/work_sdr}
SRC="$TREE/rtl/gamebub/gb_sdram_ctrl.sv $TREE/rtl/minimig/cpu_cache_new.sv $TREE/rtl/gamebub/compat/dpram.sv"
GEN=
DEFS=
if [ -d "$TREE/rtl/ap68040" ]; then   # as the variant's gb_sdram_ctrl (minimig_gamebub.sv)
	GEN="-generic CPU_LINE16=1 -generic WQN=8"
	DEFS="-d LINE16 -d WQN_N=8"
fi
mkdir -p "$W"
cd "$W"
source "$VIVADO/settings64.sh"
new=0
for f in $SRC; do [ net.v -nt "$f" ] || new=1; done
if [ ! -f net.v ] || [ $new = 1 ]; then
	cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv $SRC
synth_design -top gb_sdram_ctrl -part xc7a100tcsg324-1 -mode out_of_context $GEN
write_verilog -force -mode funcsim net.tmp.v
TCL
	rm -f net.v
	vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
	mv net.tmp.v net.v
	if grep -q 'Synth 8-605\]' syn.log; then
		echo "Vivado: implicit nets in place of signals declared later:"
		grep 'Synth 8-605\]' syn.log | sort -u | sed 's/^/  /'
	fi
	grep -E '^\|.*(c_mem|c_v_reg|RAMB|RAM[0-9]+X)' syn.log | sort -u | cut -c1-140 || true
	rm -rf xsim.dir
fi
if [ ! -d xsim.dir/sim ] || [ "$TREE/sim/sdr/tb_sdr.sv" -nt xsim.dir/sim ] || [ "$TREE/sim/rtl/sdram_sim.sv" -nt xsim.dir/sim ]; then
	xvlog net.v > xvlog_net.log
	xvlog -sv -d GLS $DEFS "$TREE/sim/rtl/sdram_sim.sv" "$TREE/sim/sdr/tb_sdr.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps -L unisims_ver tb_sdr glbl -s sim > xelab.log
fi
rc=0
n=0
pids=()
for args in "seed=1" "seed=2 cache" "seed=3" "seed=4 cache" "seed=5 cache"; do
	n=$((n + 1))
	rm -rf "run_$n"; mkdir -p "run_$n"
	cp -r xsim.dir "run_$n/"
	plus=
	for a in $args; do plus="$plus -testplusarg $a"; done
	# (xsim seeds every process's random numbers from -sv_seed)
	plus="$plus -sv_seed $n"
	(cd "run_$n" && exec xsim sim -R $plus -testplusarg "windows=${WINDOWS:-20000}" > "../xsim_$n.log" 2>&1) &
	pids+=($!)
done
echo "xsim: ${pids[*]}" > pids.txt
wait "${pids[@]}" || true
n=0
for args in "seed=1" "seed=2 cache" "seed=3" "seed=4 cache" "seed=5 cache"; do
	n=$((n + 1))
	echo "== netlist, $args"
	grep -E "^(windows|data bus|SDRAM|FAIL|ERROR|TEST|\[sdram\])" "xsim_$n.log" | head -n 20
	grep -q "TEST PASSED" "xsim_$n.log" || rc=1
done
[ $rc = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $rc
