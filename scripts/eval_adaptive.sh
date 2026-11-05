#!/bin/sh
# Adaptive vs uniform sampling at equal GPU time (REQ-ACC-007): renders each scene with adaptive
# sampling, then uniform samples for the same GPU time, and compares both with a
# high-sample reference (exr_diff mae/mean and PSNR). Needs a Metal GPU; not run in CI.
# Usage: eval_adaptive.sh [threshold] [max spp] [reference spp]. Output: target/eval-adaptive/report.md
set -eu
out=target/eval-adaptive
threshold=${1:-0.02}
max_spp=${2:-2048}
ref_spp=${3:-8192}
size="--width 512 --height 384"
mkdir -p "$out"
cargo build --release -q -p verion-render-cli
cargo build --release -q -p verion-render-io --example exr_diff
cli=./target/release/render-cli
diff() { ./target/release/examples/exr_diff "$1" "$2" | grep -o 'mae/mean [^ ]* psnr [^ ]*' | awk '{print $2 " | " $4}'; }
{
  echo "| scene | adaptive mean spp | gpu s | uniform spp | adaptive mae/mean | adaptive psnr | uniform mae/mean | uniform psnr |"
  echo "|---|---|---|---|---|---|---|---|"
} > "$out/report.md"
for case in scenes/cornell_box.gltf:none scenes/showcase.gltf:sunny scenes/glass_compare.gltf:sunny; do
  scene=${case%%:*}; light=${case#*:}
  name=$(basename "$scene" .gltf)
  extra=
  [ "$light" = none ] || extra="--hdri assets/hdri/$light.hdr"
  [ -f "$out/$name-ref.exr" ] || $cli "$scene" -o "$out/$name-ref.exr" $size --spp "$ref_spp" $extra
  $cli "$scene" -o "$out/$name-adaptive.exr" $size --spp "$max_spp" --adaptive "$threshold" $extra --metrics "$out/$name-adaptive.json"
  t=$(jq .gpu_s "$out/$name-adaptive.json")
  # Uniform time per sample from a short run, then the sample count that fits the adaptive time.
  $cli "$scene" -o "$out/$name-probe.exr" $size --spp 256 $extra --metrics "$out/$name-probe.json"
  spp=$(echo "$t $(jq .gpu_s "$out/$name-probe.json")" | awk '{printf "%d", 256 * $1 / $2}')
  $cli "$scene" -o "$out/$name-uniform.exr" $size --spp "$spp" $extra --metrics "$out/$name-uniform.json"
  echo "| $name | $(jq .mean_spp "$out/$name-adaptive.json" | awk '{printf "%.0f", $1}') | $(printf '%.2f' "$t") | $spp | $(diff "$out/$name-ref.exr" "$out/$name-adaptive.exr") | $(diff "$out/$name-ref.exr" "$out/$name-uniform.exr") |" >> "$out/report.md"
done
cat "$out/report.md"
