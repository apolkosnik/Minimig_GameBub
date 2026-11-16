#!/bin/bash
# Build with Vivado 2018.3 (the framework targets 2023.2+). Runs the normal
# framework flow, then removes the two xpm_fifo_async parameters that the
# 2018.3 XPM library does not know from the generated wrappers and re-runs
# the generated Vivado flow with timing-driven implementation directives.
# Fails if routed timing is not met. Needs JAVA_HOME (JDK 11 or later) and a
# Python 3.12/3.13 first in PATH, and Vivado's settings64.sh sourced.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
tools/patch_framework.sh
./mill -i root.buildCore --target gamebub_rev4 || true
B=build/MinimigCore-gamebub_rev4
sed -i '/\.CASCADE_HEIGHT(0),/d; /\.SIM_ASSERT_CHK(/d' "$B"/generated/XpmFifoAsync*.sv
PLACE=${PLACE_DIRECTIVE:-ExtraTimingOpt}
RUN_TCL="$B"/MinimigCore-gamebub_rev4_run.tcl
if ! grep -q "STEPS.PLACE_DESIGN.ARGS.DIRECTIVE" "$RUN_TCL"; then
	sed -i '/^  launch_runs impl_1 /i\
  set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE '"$PLACE"' [get_runs impl_1]\
  set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]\
  set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]\
  set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]\
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]\
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]' "$RUN_TCL"
fi
sed -i "s/STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [A-Za-z_]* /STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $PLACE /" "$RUN_TCL"
grep -q "STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $PLACE " "$RUN_TCL"
echo "place_design directive: $PLACE"
rm -rf "$B"/MinimigCore-gamebub_rev4.runs "$B"/MinimigCore-gamebub_rev4.xpr "$B"/MinimigCore-gamebub_rev4.cache
make -C "$B"
ls -la "$B"/MinimigCore-gamebub_rev4.bit
# Timing verdict from the final routed checkpoint, timed again in a fresh
# Vivado session (see the 3DO core's notes on the run's own summary).
IMPL="$B"/MinimigCore-gamebub_rev4.runs/impl_1
RPT="$IMPL"/top_handheld_timing_summary_postroute_physopted.rpt
DCP="$IMPL"/top_handheld_postroute_physopt.dcp
[ -f "$RPT" ] || { RPT="$IMPL"/top_handheld_timing_summary_routed.rpt; DCP="$IMPL"/top_handheld_routed.dcp; }
read -r RWNS RTNS _ _ RWHS _ < <(grep -A2 -m1 "WNS(ns)" "$RPT" | tail -1)
echo "Timing in the run ($(basename "$RPT")): WNS $RWNS ns, TNS $RTNS ns, WHS $RWHS ns"
CHK="$IMPL"/timing_recheck.rpt
rm -f "$CHK"
vivado -mode batch -nojournal -nolog -source "$ROOT"/tools/recheck_timing.tcl -tclargs "$DCP" "$CHK" > "$IMPL"/timing_recheck.log 2>&1
read -r WNS TNS _ _ WHS _ < <(grep -A2 -m1 "WNS(ns)" "$CHK" | tail -1)
echo "Timing ($(basename "$DCP") timed afresh): WNS $WNS ns, TNS $TNS ns, WHS $WHS ns"
if awk -v w="$WNS" -v h="$WHS" 'BEGIN { exit !(w < 0 || h < 0) }'; then
	echo "ERROR: timing not met" >&2
	exit 1
fi
