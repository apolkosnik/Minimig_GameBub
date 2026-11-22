#!/bin/sh
# Builds the full-system simulation (Verilator): minimig_gamebub with all of
# its RTL as Vivado synthesises it, the TG68K converted from VHDL by GHDL
# (or, in a build variant's tree, the variant's CPU: tools/stage_variant.sh),
# the SDRAM model and the bench (sim/tb). OBJ=<dir> picks the object
# directory (default sim/obj_dir).
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
R=$(cd .. && pwd)
mkdir -p gen
T=$R/rtl/minimig/tg68k
if [ -d "$T" ]; then
CPUSRC="gen/tg68k.v $(ls $R/rtl/minimig/fx68k/*.sv)"
if [ ! -f gen/tg68k.v ] || [ -n "$(find $T -name '*.vhdl' -newer gen/tg68k.v)" ]; then
	# cpu_wrapper's generics; the module takes them as parameters again
	ghdl --synth --std=08 -fsynopsys --latches --out=verilog \
		-gsr_read=2 -gvbr_stackframe=2 -gextaddr_mode=2 -gmul_mode=2 -gdiv_mode=2 -gbitfield=2 \
		$T/TG68K_Pack.vhdl $T/TG68K_ALU.vhdl $T/TG68K_MMU030.vhdl $T/TG68KdotC_Kernel.vhdl \
		-e TG68KdotC_Kernel > gen/tg68k.tmp 2> gen/ghdl.log
	# VHDL names are case-insensitive: the kernel's ports as cpu_wrapper
	# names them (lower case), and its generics as parameters
	python3 - <<'PY'
import re
s = open('gen/tg68k.tmp').read()
i = s.index('module TG68KdotC_Kernel')
j = s.index('endmodule', i)
m = s[i:j]
hdr = m[:m.index(');')]
for name in set(re.findall(r'(?:input|output|inout)\s+(?:\[[^\]]*\]\s*)?(\w+)', hdr)):
	if name != name.lower():
		m = re.sub(r'\b' + name + r'\b', name.lower(), m)
m = m.replace('module TG68KdotC_Kernel', 'module TG68KdotC_Kernel\n  #(parameter sr_read = 2, vbr_stackframe = 2, extaddr_mode = 2, mul_mode = 2, div_mode = 2, bitfield = 2)', 1)
open('gen/tg68k.v', 'w').write(s[:i] + m + s[j:])
PY
	rm gen/tg68k.tmp
fi
else
# a build variant's tree (tools/stage_variant.sh): the AP68040 in rtl/ap68040
A=$R/rtl/ap68040
[ -d "$A" ] || { echo "no CPU: neither $T nor $A" >&2; exit 1; }
CPUSRC="$(ls $A/*.sv $A/*.v)"   # the core in one file, its packages first
CPUDEF=-DAP68040                 # tb_top: the bridge's line requests counted
fi
SRC="$R/rtl/minimig_gamebub.sv $(ls $R/rtl/gamebub/*.sv $R/rtl/gamebub/compat/*.sv $R/rtl/minimig/*.sv $R/rtl/minimig/fpga-toccata/*.sv) $CPUSRC"
verilator --cc --exe --build --no-timing --no-assert-case -j ${JOBS:-16} -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
	-Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-IMPLICIT -Wno-PINCONNECTEMPTY \
	-Wno-PROCASSWIRE -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-SYNCASYNCNET \
	--top-module tb_top -Mdir ${OBJ:-obj_dir} ${CPUDEF:-} \
	-CFLAGS "-O2 -march=native" \
	-I$R/rtl/minimig -I$R/rtl/minimig/fx68k \
	rtl/xilinx_sim.sv rtl/sdram_sim.sv rtl/sram_sim.sv rtl/fw_video_sim.sv $SRC tb/tb_top.sv tb/sim_main.cpp "$@"
echo "built ${OBJ:-obj_dir}/Vtb_top"
