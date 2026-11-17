#!/bin/sh
# Assembles the test ROMs (vasm, Motorola syntax) into 256 KB images.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
for t in vidtest lacetest inptest audtest wrtest idetest coltest hamtest aga256 z3test rtgtest mmutest; do
	vasmm68k_mot -Fbin -quiet -o $t.bin $t.s
	python3 -c "import sys; d = open('$t.bin', 'rb').read(); open('$t.rom', 'wb').write(d + b'\xff' * (262144 - len(d)))"
	rm $t.bin
done
# vidtest with the display window moved: 16 low resolution pixels left
# with the fetch, 2 right without it
for v in "vidtest_l -DDIWH=-16 -DDDF=\$30" "vidtest_r -DDIWH=2"; do
	set -- $v
	t=$1; shift
	vasmm68k_mot -Fbin -quiet "$@" -o $t.bin vidtest.s
	python3 -c "import sys; d = open('$t.bin', 'rb').read(); open('$t.rom', 'wb').write(d + b'\xff' * (262144 - len(d)))"
	rm $t.bin
done
