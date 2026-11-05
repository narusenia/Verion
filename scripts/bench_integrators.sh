#!/bin/sh
# Megakernel vs wavefront (REQ-GPU-005; M3): renders each scene with both integrators, alternating so clock drift
# hits both alike, keeps the best gpu_s of `runs`, checks the images match (exr_diff) and prints a markdown table.
# Scenes run from a cube to the 5M-triangle scale scene. Needs a Metal GPU; not run in CI.
# Usage: bench_integrators.sh [spp] [runs]. Output: target/bench-integrators/report.md
set -eu
out=target/bench-integrators
spp=${1:-256}
runs=${2:-3}
mkdir -p "$out"
cargo build --release -q -p verion-render-cli
cargo build --release -q -p verion-render-io --example exr_diff
[ -f target/bench/scale/scale.gltf ] || python3 -I scripts/gen_scale_scene.py target/bench/scale
cli=./target/release/render-cli
tris() { # triangles in a glTF's index accessors (instances counted once per mesh)
  python3 -I -c 'import json,sys; g=json.load(open(sys.argv[1])); print(sum(g["accessors"][p["indices"]]["count"]//3 for m in g["meshes"] for p in m["primitives"]))' "$1"
}
{
  echo "| scene | triangles | light | megakernel s | wavefront s | wavefront / megakernel | image |"
  echo "|---|---|---|---|---|---|---|"
} > "$out/report.md"
for case in benchmarks/cube.gltf:none scenes/cornell_box.gltf:none scenes/showcase.gltf:sunny scenes/glass_compare.gltf:sunny \
            scenes/toon_compare.gltf:stylized target/bench/scale/scale.gltf:none; do
  scene=${case%%:*}; light=${case#*:}
  name=$(basename "$scene" .gltf)
  extra=
  case $light in
    none) ;;
    stylized) extra="--mode stylized --hdri assets/hdri/sunny.hdr" ;;
    *) extra="--hdri assets/hdri/$light.hdr" ;;
  esac
  best_m=; best_w=
  for i in $(seq "$runs"); do
    for integ in megakernel wavefront; do
      $cli "$scene" -o "$out/$name-$integ.exr" --width 1024 --height 768 --spp "$spp" --integrator $integ $extra --metrics "$out/$name-$integ.json"
      t=$(jq .gpu_s "$out/$name-$integ.json")
      if [ $integ = megakernel ]; then best_m=$(echo "$t ${best_m:-$t}" | awk '{print ($1 < $2) ? $1 : $2}')
      else best_w=$(echo "$t ${best_w:-$t}" | awk '{print ($1 < $2) ? $1 : $2}'); fi
    done
  done
  same=$(./target/release/examples/exr_diff "$out/$name-megakernel.exr" "$out/$name-wavefront.exr" | grep -o 'psnr [^ ]* dB [A-Z]*')
  echo "| $name | $(tris "$scene") | $light | $best_m | $best_w | $(echo "$best_w $best_m" | awk '{printf "%.2f", $1 / $2}') | $same |" >> "$out/report.md"
done
cat "$out/report.md"
