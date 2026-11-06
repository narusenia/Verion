#!/bin/sh
# Compares the images of two scripts/backend_render.sh runs file by file (REQ-GPU-007):
#   scripts/backend_diff.sh REFERENCE_DIR TEST_DIR
# Uses the exr_diff gates (worst channel mean 1%, worst 4x4 block mean 2%); the thresholds for
# Backend differences are set from the first measurement, see docs/implementation/M4-vulkan.
set -eu
ref=${1:?usage: backend_diff.sh REFERENCE_DIR TEST_DIR}
test=${2:?usage: backend_diff.sh REFERENCE_DIR TEST_DIR}
status=0
for r in "$ref"/*.exr; do
  name=$(basename "$r")
  [ -f "$test/$name" ] || { echo "missing: $test/$name" >&2; status=1; continue; }
  cargo run --release -q -p verion-render-io --example exr_diff -- "$r" "$test/$name" || status=1
done
exit $status
