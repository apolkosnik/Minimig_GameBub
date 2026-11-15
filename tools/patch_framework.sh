#!/bin/bash
# Applies patches/framework/*.patch (in order) to the framework submodule.
# Does nothing when the framework already is its commit with exactly these
# patches; applies them to an unmodified framework; stops (changing nothing)
# when the framework has other changes, such as another branch's patches:
# `git -C framework checkout -- .` and run again. Run before building.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FW=$ROOT/framework
PATCHES=("$ROOT"/patches/framework/*.patch)
# The patched framework, built in a temporary index
IDX=$(mktemp)
trap 'rm -f "$IDX"' EXIT
GIT_INDEX_FILE=$IDX git -C "$FW" read-tree HEAD
for p in "${PATCHES[@]}"; do
	GIT_INDEX_FILE=$IDX git -C "$FW" apply --cached "$p"
done
if GIT_INDEX_FILE=$IDX git -C "$FW" diff --quiet; then
	echo "framework: patches already applied: $(cd "$ROOT/patches/framework" && echo *.patch)"
elif git -C "$FW" diff --quiet HEAD; then
	for p in "${PATCHES[@]}"; do
		git -C "$FW" apply "$p"
		echo "framework: applied $(basename "$p")"
	done
else
	echo "framework: has changes other than patches/framework (another branch's patches?):" >&2
	git -C "$FW" diff --stat HEAD >&2
	echo "reset it with: git -C framework checkout -- .   and run again" >&2
	exit 1
fi
