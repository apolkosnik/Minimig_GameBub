#!/bin/bash
# The AP68040 variant's CPU, netlist against RTL: Vivado 2018.3 synthesizes
# ap68040_minimig (the core, its FPU and the bridge, as the build does: the
# default synth_design, the board's part) out of context, and xsim replays
# traces of the RTL simulation on the netlist (cpu_tb.sv): every output at
# every CPU clock must be the RTL's.
#
#   sim/gls/run_cpu_gls.sh <staged variant tree> <trace> [<trace> ...]
#
# A trace comes from the variant tree's simulation:
#   sim/obj_dir/Vtb_top --kick asm/crashtest.rom --ms 600 --set 1048=4 \
#       --set 104C=8 +cputrace=crash.trc [+cputrace_n=<clocks after reset>]
# WORK=<dir> (default <tree>/sim/gls/work_cpu) keeps the netlist; it is made
# again when a source is newer. MAXRST=<n> cuts the reset before the ROM is
# loaded to n clocks (default 100000; 0: all of it).
# Needs Vivado: VIVADO=/opt/tools/Xilinx/Vivado/2018.3 by default.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 2 ] || { sed -n '2,17p' "$0"; exit 1; }
TREE=$(cd "$1" && pwd); shift
A=$TREE/rtl/ap68040
[ -f "$A/ap68040_minimig.sv" ] || { echo "no AP68040 in $TREE (tools/stage_variant.sh ap68040)" >&2; exit 1; }
W=${WORK:-$TREE/sim/gls/work_cpu}
mkdir -p "$W"
TRACES=()
for t in "$@"; do TRACES+=("$(cd "$(dirname "$t")" && pwd)/$(basename "$t")"); done
cd "$W"
source "$VIVADO/settings64.sh"
if [ ! -f net.v ] || [ -n "$(find "$A" -newer net.v -name 'ap*')" ]; then
	cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv $A/ap68040_core.sv $A/ap68040_minimig.sv
read_verilog $A/ap040_fpu.v
synth_design -top ap68040_minimig -part xc7a100tcsg324-1 -mode out_of_context
write_verilog -force -mode funcsim net.tmp.v
TCL
	rm -f net.v
	vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
	mv net.tmp.v net.v
	# signals used before their declaration: Vivado 2018.3 makes them
	# separate one-bit nets (the netlist test below shows what that does)
	if grep -q 'Synth 8-605\]' syn.log; then
		echo "Vivado: implicit nets in place of signals declared later:"
		grep 'Synth 8-605\]' syn.log | sort -u | sed 's/^/  /'
	fi
fi
if [ ! -d xsim.dir/sim ] || [ net.v -nt xsim.dir/sim ] || [ "$HERE/cpu_tb.sv" -nt xsim.dir/sim ]; then
	xvlog net.v > xvlog_net.log
	xvlog -sv "$HERE/cpu_tb.sv" > xvlog.log
	xelab -debug off -L unisims_ver tb glbl -s sim > xelab.log
fi
# the traces side by side (about 1000 clocks a second each), each from its
# own copy of the snapshot: xsim writes the run's script into it
pids=()
for t in "${TRACES[@]}"; do
	n=$(basename "$t" .trc)
	rm -rf "run_$n"; mkdir -p "run_$n"
	cp -r xsim.dir "run_$n/"
	(cd "run_$n" && exec xsim sim -R -testplusarg "trace=$t" -testplusarg "maxrst=${MAXRST:-100000}" > "../xsim_$n.log" 2>&1) &
	pids+=($!)
done
echo "xsim: ${pids[*]}" > pids.txt
wait "${pids[@]}" || true
rc=0
for t in "${TRACES[@]}"; do
	n=$(basename "$t" .trc)
	echo "== $n"
	grep -q "trace=$t " "xsim_$n.log" || { echo "xsim_$n.log: not this trace's run"; rc=1; }
	grep -E 'MISMATCH|RTL |RESULT|TEST' "xsim_$n.log" | head -n 60
	grep -q 'TEST PASSED' "xsim_$n.log" || rc=1
done
exit $rc
