#!/bin/bash
# Applies patches/framework/*.patch to the framework submodule (once: a patch
# that is already applied is skipped). Run before building the core.
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for p in "$ROOT"/patches/framework/*.patch; do
	if git -C "$ROOT/framework" apply --reverse --check "$p" 2>/dev/null; then
		echo "framework: $(basename "$p") already applied"
	else
		git -C "$ROOT/framework" apply "$p"
		echo "framework: applied $(basename "$p")"
	fi
done
