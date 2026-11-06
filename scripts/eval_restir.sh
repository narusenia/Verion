#!/bin/sh
# Time to quality, ReSTIR DI against plain light sampling (REQ-ACC-002, REQ-PERF-001): renders each
# scene with --mode reference and --mode interactive over a ladder of sample counts, and compares
# every image with a high-sample reference render (exr_diff mae/mean and PSNR) next to its GPU time.
# Needs a Metal GPU; not run in CI.
# Usage: eval_restir.sh [reference spp]. Output: target/eval-restir/report.md
set -eu
out=target/eval-restir
ref_spp=${1:-16384}
size="--width 512 --height 384"
mkdir -p "$out"
cargo build --release -q -p verion-render-cli
cargo build --release -q -p verion-render-io --example exr_diff
cli=./target/release/render-cli
diff() { ./target/release/examples/exr_diff "$1" "$2" | grep -o 'mae/mean [^ ]* psnr [^ ]*' | awk '{print $2 " | " $4}'; }
{
  echo "| scene | mode | spp | gpu s | mae/mean | psnr |"
  echo "|---|---|---|---|---|---|"
} > "$out/report.md"
for scene in scenes/many_lights.gltf scenes/many_lights_dark.gltf scenes/cornell_box.gltf scenes/showcase.gltf; do
  name=$(basename "$scene" .gltf)
  extra=
  [ "$name" = showcase ] && extra="--hdri assets/hdri/sunny.hdr"
  [ -f "$out/$name-ref.exr" ] || $cli "$scene" -o "$out/$name-ref.exr" $size --spp "$ref_spp" $extra
  for spp in 1 2 4 8 16 32 64 128 256; do
    for mode in reference interactive; do
      f="$out/$name-$mode-$spp"
      $cli "$scene" -o "$f.exr" $size --spp "$spp" --mode "$mode" $extra --metrics "$f.json"
      echo "| $name | $mode | $spp | $(jq .gpu_s "$f.json" | awk '{printf "%.4f", $1}') | $(diff "$out/$name-ref.exr" "$f.exr") |" >> "$out/report.md"
    done
  done
done
cat "$out/report.md"
