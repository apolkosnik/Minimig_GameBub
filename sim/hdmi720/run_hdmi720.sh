#!/bin/bash
# HDMI 720p test (sim/hdmi720/tb_hdmi720.sv): the framework's generated
# HandheldTop with the whole Minimig core, and the hdmi module instantiated
# as in framework/verilog/handheld/top.sv. Generates the Verilog of the
# current sources first (patched framework, Chisel only, no Vivado) into
# build/hdmi720/generated.
#   sim/hdmi720/run_hdmi720.sh [+mode=0|1] [+frames=<n>]
# (GEN_SKIP=1 reuses the generated Verilog when it is newer than the sources.)
# Needs JAVA_HOME (JDK 11 or later), Python 3.12/3.13, Verilator 5, GHDL
# (sim/build.sh makes sim/gen/tg68k.v) and Vivado's XPM sources.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SIM=$(dirname "$HERE")
ROOT=$(dirname "$SIM")
GEN=$ROOT/build/hdmi720/generated
FW=$ROOT/framework/verilog
XPM=${XILINX_VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}/data/ip/xpm
BUILD=${BUILD:-$ROOT/build/hdmi720}
"$ROOT"/tools/patch_framework.sh > /dev/null
stale=
for f in "$ROOT"/framework/src/main/scala/platform/handheld/HandheldTop.scala \
	"$ROOT"/framework/src/main/scala/net/gamebub/framework/interface/VideoV0.scala "$ROOT"/chisel/src/*.scala; do
	[ -f "$GEN/HandheldTop.sv" ] && [ "$f" -ot "$GEN/HandheldTop.sv" ] || stale=1
done
if [ -n "$stale" ] || [ -z "$GEN_SKIP" ]; then
	rm -rf "$GEN"
	(cd "$ROOT" && framework/mill -i --no-build-lock root.runMain platform.handheld.HandheldTop \
		MinimigCore 4 --target-dir="$GEN") > "$BUILD.chisel.log" 2>&1 \
		|| { tail -20 "$BUILD.chisel.log"; exit 1; }
fi
[ -f "$SIM/gen/tg68k.v" ] || { echo "no sim/gen/tg68k.v: run sim/build.sh first" >&2; exit 1; }
mkdir -p "$BUILD"
# The hdmi instance of top.sv, verbatim
awk '/^[[:space:]]*hdmi #\(/ {p=1} p {print} p && /^[[:space:]]*\);/ {exit}' "$FW/handheld/top.sv" > "$BUILD/hdmi_inst.svh"
grep -q "VIDEO_ID_CODE" "$BUILD/hdmi_inst.svh" || { echo "hdmi instance not found in top.sv" >&2; exit 1; }
# The generated files, with the two xpm_fifo_async parameters the 2018.3 XPM
# library does not know removed from the FIFO wrappers (as
# tools/build_vivado2018.sh does)
rm -rf "$BUILD/gen"
mkdir -p "$BUILD/gen"
GENFILES=()
while read -r f; do
	[ -n "$f" ] || continue
	case "$f" in
		XpmFifoAsync*.sv) sed '/\.CASCADE_HEIGHT(0),/d; /\.SIM_ASSERT_CHK(/d' "$GEN/$f" > "$BUILD/gen/$f" ;;
		*) cp "$GEN/$f" "$BUILD/gen/$f" ;;
	esac
	GENFILES+=("$BUILD/gen/$f")
done < "$GEN/filelist.f"
# The hdmi sources. Verilator cannot fold int'(<real>) in a localparam: the
# copy of audio_clock_regeneration_packet.sv writes the two such casts as
# $rtoi(<real> + 0.5), the same rounding for these positive values.
mkdir -p "$BUILD/hdmi"
HDMI=()
for f in "$FW"/hdmi/src/*.sv; do
	cp "$f" "$BUILD/hdmi/"
	HDMI+=("$BUILD/hdmi/$(basename "$f")")
done
ACR=$BUILD/hdmi/audio_clock_regeneration_packet.sv
sed -i "s|20'(int'(VIDEO_RATE \* int'(N) / 128 / AUDIO_RATE))|20'(\$rtoi(VIDEO_RATE * N / 128 / AUDIO_RATE + 0.5))|; s|20'(int'(real'(CYCLE_TIME_STAMP_COUNTER_IDEAL) \* 1.1))|20'(\$rtoi(real'(CYCLE_TIME_STAMP_COUNTER_IDEAL) * 1.1 + 0.5))|" "$ACR"
[ "$(grep -c 'rtoi' "$ACR")" = 2 ] || { echo "audio_clock_regeneration_packet.sv: casts not found" >&2; exit 1; }
# The Minimig RTL as sim/build.sh compiles it
CORE=("$ROOT/rtl/minimig_gamebub.sv" $(ls "$ROOT"/rtl/gamebub/*.sv "$ROOT"/rtl/gamebub/compat/*.sv "$ROOT"/rtl/minimig/*.sv "$ROOT"/rtl/minimig/fx68k/*.sv))
# ONESPIN: the XPM CDC models without their glbl.GSR power-up forcing (the
# same synchroniser registers; Verilator cannot lower the force of an array).
verilator --binary --timing -j "$(nproc)" -O2 --top-module tb_hdmi720 --Mdir "$BUILD/obj" -o tb_hdmi720 \
	--no-assert-case --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-IMPLICIT \
	-Wno-PROCASSWIRE -Wno-SYNCASYNCNET -Wno-DEFPARAM -Wno-IMPLICITSTATIC -Wno-INITIALDLY \
	-Wno-MULTITOP -Wno-ASCRANGE -Wno-SELRANGE -Wno-ZERODLY \
	--timescale 1ns/1ps +define+TB_TOP=tb_hdmi720 +define+ONESPIN \
	-I"$BUILD" -I"$ROOT/rtl/minimig" -I"$ROOT/rtl/minimig/fx68k" \
	"$XPM/xpm_cdc/hdl/xpm_cdc.sv" "$XPM/xpm_memory/hdl/xpm_memory.sv" "$XPM/xpm_fifo/hdl/xpm_fifo.sv" \
	"${GENFILES[@]}" "${HDMI[@]}" "$FW/handheld/pll_reset_generator.sv" \
	"$SIM/gen/tg68k.v" "$SIM/rtl/xilinx_sim.sv" "${CORE[@]}" "$HERE/tb_hdmi720.sv" \
	> "$BUILD/build.log" 2>&1 || { grep -m20 -E "%Error" "$BUILD/build.log"; tail -5 "$BUILD/build.log"; exit 1; }
"$BUILD/obj/tb_hdmi720" "$@" | tee "$BUILD/run.log"
grep -q '^PASS' "$BUILD/run.log"
