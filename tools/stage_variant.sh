#!/bin/bash
# Assembles the source tree of a build variant (variants/<name>) in <dir>:
# a copy of this repository (without .git, build/ and the simulation's
# outputs; framework/ a link to this repository's, patches applied as for
# the standard build) with the variant's changes:
#   - variants/<name>/patches/rtl/*.patch applied (in sorted order),
#   - the files of variants/<name>/remove.txt removed (paths in the tree),
#   - variants/<name>/rtl/ copied to rtl/<name>/,
#   - variants/<name>/src/ copied over the files of the same name under rtl/
#     (each must replace exactly one),
#   - variants/<name>/metadata/* over metadata/.
# The framework's build takes every file under rtl/, so the tree holds only
# the variant's own. Used by tools/build_variant.sh and sim/build_variant.sh.
#
# Usage: tools/stage_variant.sh <name> <dir>
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=$1
DIR=$2
V=$ROOT/variants/$NAME
[ -n "$NAME" ] && [ -n "$DIR" ] && [ -d "$V" ] || { echo "usage: $0 <variant> <dir> (variants: $(ls "$ROOT/variants"))" >&2; exit 1; }

"$ROOT"/tools/patch_framework.sh
rm -rf "$DIR"
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
tar -C "$ROOT" --exclude=./.git --exclude=./build --exclude=./framework --exclude=./out \
	--exclude=./variants --exclude='./sim/obj_dir*' --exclude=./sim/out --exclude=./sim/gen -cf - . | tar -C "$DIR" -xf -
ln -s "$ROOT/framework" "$DIR/framework"

for p in "$V"/patches/rtl/*.patch; do
	[ -e "$p" ] || continue
	echo "variant $NAME: applying $(basename "$p")"
	# GNU patch: the tree may lie inside this repository (build/), where git
	# apply would take the paths from the repository's top
	patch -p1 -d "$DIR" --forward --no-backup-if-mismatch -s < "$p"
done

if [ -f "$V/remove.txt" ]; then
	grep -v '^\s*#' "$V/remove.txt" | while read -r f; do
		[ -n "$f" ] || continue
		[ -e "$DIR/$f" ] || { echo "variant $NAME: $f (remove.txt) is not in the tree" >&2; exit 1; }
		rm -rf "${DIR:?}/$f"
	done
fi

mkdir -p "$DIR/rtl/$NAME"
cp -a "$V"/rtl/. "$DIR/rtl/$NAME/"

if [ -d "$V/src" ]; then
	for f in "$V"/src/*; do
		b=$(basename "$f")
		hits=$(find "$DIR/rtl" -name "$b" -not -path "$DIR/rtl/$NAME/*")
		[ "$(echo "$hits" | grep -c .)" = 1 ] || { echo "variant $NAME: src/$b must replace exactly one file under rtl/ (found: $hits)" >&2; exit 1; }
		cp "$f" "$hits"
		echo "variant $NAME: $b replaces ${hits#$DIR/}"
	done
fi

[ -d "$V/metadata" ] && cp "$V"/metadata/* "$DIR/metadata/"
echo "variant $NAME staged in $DIR"
