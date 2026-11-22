#!/bin/bash
# The picture's frame store as a netlist: Vivado 2018.3 synthesizes gb_fb
# for the board's FPGA out of context, and xsim runs the unit test of
# sim/fb (tb_fb.sv with the SRAM model and the framework's video side:
# every pixel shown on the panel and on HDMI compared with the frames
# written, the SRAM pins' timing checked) on the netlist.
#
#   sim/gls/run_fb_gls.sh [<tree>]      (default: this repository)
#
# WORK=<dir> (default <tree>/sim/gls/work_fb) keeps the netlist; it is made
# again when a source is newer. FRAMES=<n> as for run_fb.sh (default 6: the netlist runs slowly).
# Needs Vivado: VIVADO=/opt/tools/Xilinx/Vivado/2018.3 by default.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "${1:-$HERE/../..}" && pwd)
W=${WORK:-$TREE/sim/gls/work_fb}
SRC="$TREE/rtl/gamebub/gb_fb.sv"
mkdir -p "$W"
cd "$W"
source "$VIVADO/settings64.sh"
if [ ! -f net.v ] || [ ! net.v -nt "$SRC" ]; then
	cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv $SRC
synth_design -top gb_fb -part xc7a100tcsg324-1 -mode out_of_context
report_utilization -file util.rpt
write_verilog -force -mode funcsim net.tmp.v
TCL
	rm -f net.v
	vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
	mv net.tmp.v net.v
	if grep -q 'Synth 8-605\]' syn.log; then
		echo "Vivado: implicit nets in place of signals declared later:"
		grep 'Synth 8-605\]' syn.log | sort -u | sed 's/^/  /'
	fi
	grep -E 'Synth 8-(3295|3848|6430|5856)\]' syn.log | sort -u | cut -c1-160 | head -20 || true
	grep -E '^\| (Block RAM Tile|  RAMB36|  RAMB18|Slice LUTs|LUT as Distributed RAM)' util.rpt || true
	rm -rf xsim.dir
fi
if [ ! -d xsim.dir/sim ] || [ "$TREE/sim/fb/tb_fb.sv" -nt xsim.dir/sim ] || [ "$TREE/sim/rtl/sram_sim.sv" -nt xsim.dir/sim ] ||
   [ "$TREE/sim/rtl/fw_video_sim.sv" -nt xsim.dir/sim ]; then
	xvlog net.v > xvlog_net.log
	xvlog -sv -d GLS "$TREE/sim/rtl/sram_sim.sv" "$TREE/sim/rtl/fw_video_sim.sv" "$TREE/sim/fb/tb_fb.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps -L unisims_ver tb_fb glbl -s sim > xelab.log
fi
rc=0
n=0
pids=()
RUNS=("seed=1" "seed=2 nofit" "seed=3 hdmi" "seed=4 hdmi nofit")
for args in "${RUNS[@]}"; do
	n=$((n + 1))
	rm -rf "run_$n"; mkdir -p "run_$n"
	cp -r xsim.dir "run_$n/"
	plus=
	for a in $args; do plus="$plus -testplusarg $a"; done
	(cd "run_$n" && exec xsim sim -R $plus -testplusarg "frames=${FRAMES:-6}" > "../xsim_$n.log" 2>&1) &
	pids+=($!)
done
echo "xsim: ${pids[*]}" > pids.txt
wait "${pids[@]}" || true
n=0
for args in "${RUNS[@]}"; do
	n=$((n + 1))
	echo "== netlist, $args"
	grep -E "^(frames|SRAM|FAIL|TEST|\[sram\]|\[video\])" "xsim_$n.log" | head -n 20
	grep -q "TEST PASSED" "xsim_$n.log" || rc=1
done
[ $rc = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $rc
