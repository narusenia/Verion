#!/bin/sh
# Renders each cross-check scene with Verion (Metal, needs the dev machine's GPU) and Mitsuba 3, and
# fails when any scene is outside the limits in scripts/mitsuba_cornell.py. Not run in CI (no GPU).
set -u
out=target/crosscheck
py="$(mise where pipx:mitsuba)/mitsuba/bin/python"
status=0
for mode in box walls hdri spot normalmap; do
  arg=$mode; [ "$mode" = box ] && arg=
  echo "== $mode"
  cargo run --release -q -p verion-gpu-metal --example render_ppm -- "$out/$mode" 512 384 1024 $arg >/dev/null || exit 1
  "$py" scripts/mitsuba_cornell.py "$out/$mode" 512 384 1024 $arg || status=1
done
exit $status
