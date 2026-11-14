#!/bin/bash
# Makes two bootable hard disk images from the files of a bootable ADF, for
# the Kickstart boot tests of sim/run_tests.sh (HDF31, HDFRDB31):
#   <out>/part.hdf  a partition image without an RDB (FFS), as most ".hdf"
#                   files are: the core puts a virtual RDB in front of it
#   <out>/rdb.hdf   a disk image with a Rigid Disk Block (4 heads, 17
#                   sectors per track) and one bootable FFS partition DH0
# Needs amitools (pip install amitools): xdftool, rdbtool.
# Usage: sim/make_hdf.sh <bootable.adf> <out directory>
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
ADF=$1
OUT=$2
[ -f "$ADF" ] && [ -n "$OUT" ] || { echo "usage: $0 <bootable.adf> <out directory>" >&2; exit 2; }
mkdir -p "$OUT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
xdftool "$ADF" unpack "$T/files" > /dev/null
fill() {   # fill <image> [open part=DH0 +]
	local img=$1; shift
	(cd "$T/files" && find . -mindepth 1 -type d | sed 's|^\./||' | sort) | while read -r d; do
		xdftool "$img" "$@" makedir "$d"
	done
	(cd "$T/files" && find . -type f | sed 's|^\./||' | sort) | while read -r f; do
		xdftool "$img" "$@" write "$T/files/$f" "$f"
	done
}
rm -f "$OUT/part.hdf" "$OUT/rdb.hdf"
xdftool "$OUT/part.hdf" create size=8M + format HardDisk ffs
fill "$OUT/part.hdf"
rdbtool "$OUT/rdb.hdf" create chs=280,4,17 + init + add size=100% name=DH0 dostype=DOS1 bootable=true
xdftool "$OUT/rdb.hdf" open part=DH0 + format HardDisk ffs
fill "$OUT/rdb.hdf" open part=DH0 +
ls -la "$OUT/part.hdf" "$OUT/rdb.hdf"
