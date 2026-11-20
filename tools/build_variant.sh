#!/bin/bash
# Builds a build variant (variants/<name>): stages its tree in
# build/variant-<name>/tree (tools/stage_variant.sh) and runs the same
# Vivado 2018.3 flow there (tools/build_vivado2018.sh: fails if timing is
# not met). The core directory for the card ends up in
# build/variant-<name>/core: the bitstream and the variant's core.json,
# files.json and settings.json. Needs what tools/build_vivado2018.sh needs.
#
# Usage: tools/build_variant.sh <name>
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=$1
[ -n "$NAME" ] && [ -d "$ROOT/variants/$NAME" ] || { echo "usage: $0 <variant> (variants: $(ls "$ROOT/variants"))" >&2; exit 1; }
OUT=$ROOT/build/variant-$NAME
"$ROOT"/tools/stage_variant.sh "$NAME" "$OUT/tree"
# a signal an instance is connected to before its declaration: Vivado 2018.3
# may synthesize a net of its own for it, and no simulation shows that
"$ROOT"/tools/decl_before_use.py --check "$OUT/tree/rtl/$NAME"/*.sv "$OUT/tree/rtl/$NAME"/*.v \
	"$OUT/tree"/rtl/minimig_gamebub.sv "$OUT/tree"/rtl/gamebub/*.sv
(cd "$OUT/tree" && tools/build_vivado2018.sh)
B=$OUT/tree/build/MinimigCore-gamebub_rev4
rm -rf "$OUT/core"
mkdir -p "$OUT/core"
cp "$B"/MinimigCore-gamebub_rev4.bit "$OUT/tree"/metadata/core.json "$OUT/tree"/metadata/files.json \
	"$OUT/tree"/metadata/settings.json "$OUT/core/"
ID=$(python3 -c "import json; print(json.load(open('$OUT/core/core.json'))['metadata']['id'])")
# the firmware lists a core only if its metadata fit (and its id is its folder)
"$ROOT"/tools/check_metadata.py "$OUT/core" "$ID"
echo "variant $NAME: $ID in $OUT/core"
ls -la "$OUT/core"
