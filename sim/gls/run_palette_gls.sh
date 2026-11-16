#!/bin/bash
# gb_palette: Vivado 2018.3 synthesis (out of context, the board's part),
# then the RTL and the netlist side by side in xsim (palette_tb.sv).
# Needs Vivado: VIVADO=/opt/tools/Xilinx/Vivado/2018.3 by default.
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../../rtl/gamebub/gb_palette.sv
W=${WORK:-$HERE/work}
rm -rf "$W"; mkdir -p "$W"; cd "$W"
source "$VIVADO/settings64.sh"
cat > syn.tcl <<TCL
read_verilog -sv $RTL
synth_design -top gb_palette -part xc7a100tcsg324-1 -mode out_of_context
write_verilog -force -mode funcsim net.v
TCL
vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
# the netlist's module under another name, next to the RTL's
sed -i 's/^module gb_palette\b/module net_gb_palette/' net.v
grep -q '^module net_gb_palette' net.v
(echo '`timescale 1ns/1ps'; cat "$RTL") > rtl.sv
xvlog -sv rtl.sv "$HERE/palette_tb.sv" > xvlog.log
xvlog net.v > xvlog_net.log
xelab -debug off -L unisims_ver tb glbl -s sim > xelab.log
xsim sim -R > xsim.log
grep -E 'MISMATCH|RESULT|TEST' xsim.log | head -n 20
grep -q 'TEST PASSED' xsim.log
