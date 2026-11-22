#!/bin/bash
# The Toccata sound card, netlist against RTL: Vivado 2018.3 synthesizes
# toccata (rtl/minimig/fpga-toccata) for the board's FPGA out of context,
# and xsim runs toccata_tb.sv on the RTL and on the netlist: playback in
# four formats with the half empty interrupt and all 64 levels of the DAC's
# attenuation. Every change of the card's outputs (the two channels, the
# interrupt, the data it puts on the bus), with its clock, must be the same
# in both.
#
#   sim/gls/run_toccata_gls.sh [<tree>]      (default: this repository)
#
# WORK=<dir> (default <tree>/sim/gls/work_toccata) keeps the netlist; it is
# made again when a source is newer.
# Needs Vivado: VIVADO=/opt/tools/Xilinx/Vivado/2018.3 by default.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "${1:-$HERE/../..}" && pwd)
W=${WORK:-$TREE/sim/gls/work_toccata}
T=$TREE/rtl/minimig/fpga-toccata
SRC="$T/toccata.sv $T/toccata_capture.sv $T/toccata_fifo.sv $T/toccata_playback.sv $T/toccata_volume.sv"
mkdir -p "$W"
cd "$W"
source "$VIVADO/settings64.sh"
if [ ! -f net.v ] || [ -n "$(find $SRC -newer net.v)" ]; then
	cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv $SRC
synth_design -top toccata -part xc7a100tcsg324-1 -mode out_of_context -generic CLK_FREQUENCY=28375160
report_utilization -file util.rpt
write_verilog -force -mode funcsim net.tmp.v
TCL
	rm -f net.v
	vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
	mv net.tmp.v net.v
	# what Vivado left out or made up
	grep -E 'Synth 8-(605|311|3848|6430|5856)\]' syn.log | sort -u | cut -c1-200 | head -20 || true
	grep -E '^\| (Block RAM Tile|  RAMB36|  RAMB18|Slice LUTs|LUT as Distributed RAM|DSPs)' util.rpt || true
	rm -rf rtl net
fi
if [ ! -d rtl/xsim.dir/sim ] || [ "$HERE/toccata_tb.sv" -nt rtl/xsim.dir/sim ] || [ -n "$(find $SRC -newer rtl/xsim.dir/sim)" ]; then
	rm -rf rtl; mkdir rtl
	# (the bench first: its timescale is the card's sources' too)
	(cd rtl && xvlog -sv "$HERE/toccata_tb.sv" $SRC > xvlog.log && xelab -debug off tb -s sim > xelab.log)
fi
if [ ! -d net/xsim.dir/sim ] || [ "$HERE/toccata_tb.sv" -nt net/xsim.dir/sim ] || [ net.v -nt net/xsim.dir/sim ]; then
	rm -rf net; mkdir net
	(cd net && xvlog ../net.v > xvlog_net.log && xvlog -sv -d NETLIST "$HERE/toccata_tb.sv" > xvlog.log \
		&& xelab -debug off -L unisims_ver tb glbl -s sim > xelab.log)
fi
(cd rtl && exec xsim sim -R -testplusarg "out=$W/rtl.trc" > ../xsim_rtl.log 2>&1) &
p1=$!
(cd net && exec xsim sim -R -testplusarg "out=$W/net.trc" > ../xsim_net.log 2>&1) &
p2=$!
echo "xsim: $p1 $p2" > pids.txt
wait $p1 || true
wait $p2 || true
rc=0
for n in rtl net; do
	echo "== $n"
	grep -E 'FAIL|RESULT|BENCH|^init ' xsim_$n.log | head -n 20
	grep -q 'BENCH DONE' xsim_$n.log || rc=1
done
if cmp -s rtl.trc net.trc; then
	echo "the netlist's outputs are the RTL's: $(wc -l < rtl.trc) changes"
else
	echo "MISMATCH: the first lines that differ (clock, left, right, interrupt, data; < RTL, > netlist):"
	diff rtl.trc net.trc | head -n 20
	rc=1
fi
[ $rc = 0 ] && echo "TEST PASSED" || echo "TEST FAILED"
exit $rc
