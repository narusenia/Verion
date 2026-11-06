#!/bin/sh
# Compares the images of two scripts/backend_render.sh runs file by file (REQ-GPU-007):
#   scripts/backend_diff.sh REFERENCE_DIR TEST_DIR
# Uses the exr_diff gates at the REQ-GPU-007 thresholds (worst channel mean 0.1%, worst 4x4 block
# mean 0.5%), set from the first Metal/Vulkan measurement.
set -eu
export EXR_DIFF_CHANNEL=0.001 EXR_DIFF_BLOCK=0.005
ref=${1:?usage: backend_diff.sh REFERENCE_DIR TEST_DIR}
test=${2:?usage: backend_diff.sh REFERENCE_DIR TEST_DIR}
status=0
for r in "$ref"/*.exr; do
  name=$(basename "$r")
  [ -f "$test/$name" ] || { echo "missing: $test/$name" >&2; status=1; continue; }
  cargo run --release -q -p verion-render-io --example exr_diff -- "$r" "$test/$name" || status=1
done
exit $status
