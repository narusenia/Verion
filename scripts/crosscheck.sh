#!/bin/sh
# Renders each cross-check scene with Verion (Metal, needs the dev machine's GPU) and Mitsuba 3, and
# fails when any scene is outside the limits in scripts/mitsuba_cornell.py (FLIP is reported only). Not run in CI (no GPU).
set -u
out=target/crosscheck
py="$(mise where pipx:mitsuba)/mitsuba/bin/python"
flip="$(mise where pipx:flip-evaluator)/flip-evaluator/bin/flip"
status=0
for mode in box walls hdri spot normalmap coat; do
  arg=$mode; [ "$mode" = box ] && arg=
  echo "== $mode"
  cargo run --release -q -p verion-gpu-metal --example render_ppm -- "$out/$mode" 512 384 1024 $arg >/dev/null || exit 1
  "$py" scripts/mitsuba_cornell.py "$out/$mode" 512 384 1024 $arg || status=1
  # HDR-FLIP (0 = identical); both renders are noisy, so it is reported only, never gated.
  "$flip" -r "$out/$mode/mitsuba.exr" -t "$out/$mode/verion_rgb.exr" -d "$out/$mode/flip" -nexm -v 2 \
    | grep -E "^ +(Mean|Max):" | tr -s ' ' | sed "s/^/FLIP/"
done
exit $status
