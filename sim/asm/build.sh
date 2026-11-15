#!/bin/sh
# Assembles the test ROMs (vasm, Motorola syntax) into 256 KB images.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
cd "$(dirname "$0")"
for t in vidtest inptest audtest wrtest idetest coltest hamtest; do
	vasmm68k_mot -Fbin -quiet -o $t.bin $t.s
	python3 -c "import sys; d = open('$t.bin', 'rb').read(); open('$t.rom', 'wb').write(d + b'\xff' * (262144 - len(d)))"
	rm $t.bin
done
