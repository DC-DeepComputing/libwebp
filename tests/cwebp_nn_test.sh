#!/bin/sh
# Copyright 2026 Google Inc. All Rights Reserved.
#
# Use of this source code is governed by a BSD-style license
# that can be found in the COPYING file in the root of the source
# tree. An additional intellectual property rights grant can be found
# in the file PATENTS. All contributing project authors may
# be found in the AUTHORS file in the root of the source tree.
# -----------------------------------------------------------------------------
#
# Sanity tests for cwebp's '-nn <int>' option (NN-assisted decisions).
#
# Usage: tests/cwebp_nn_test.sh <path/to/cwebp>

set -e

CWEBP=${1:-cwebp}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cwebp_nn.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Synthetic 96x96 image (binary PPM), with some structure to encode.
{
  printf 'P6\n96 96\n255\n'
  LC_ALL=C awk 'BEGIN {
    for (y = 0; y < 96; ++y) for (x = 0; x < 96; ++x) {
      v = int((x * 2 + y + ((x * y) % 17) * 3) % 250) + 1;
      printf "%c%c%c", v, 1 + (v * 3) % 250, 1 + (255 - v) % 250;
    }
  }'
} > "$TMP/in.ppm"

# All valid levels encode successfully.
for nn in 0 1 2 3 4 5 6 7 8 9 10; do
  "$CWEBP" -quiet -q 75 -m 4 -nn "$nn" "$TMP/in.ppm" -o "$TMP/out_$nn.webp"
  test -s "$TMP/out_$nn.webp" || { echo "FAIL: -nn $nn: no output"; exit 1; }
done

# Encoding is deterministic.
"$CWEBP" -quiet -q 75 -m 4 -nn 4 "$TMP/in.ppm" -o "$TMP/again.webp"
cmp -s "$TMP/out_4.webp" "$TMP/again.webp" || {
  echo "FAIL: -nn 4 is not deterministic"; exit 1; }

# Out-of-range values are rejected.
for nn in -1 11; do
  if "$CWEBP" -quiet -nn "$nn" "$TMP/in.ppm" -o "$TMP/bad.webp" 2> /dev/null;
  then
    echo "FAIL: -nn $nn should have been rejected"; exit 1
  fi
done

echo "cwebp -nn: OK"
