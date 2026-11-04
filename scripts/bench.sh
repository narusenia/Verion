#!/bin/sh
# Renders each benchmarks/*.gltf and the generated scale scene at a fixed size and spp, and compares gpu_s with the baseline recorded
# for this chip and power source (benchmarks/baseline/<chip>-<ac|battery>.json; battery runs ~25% slower); exits 1 when any scene is more than 10% slower.
# `bench.sh record` writes the baseline instead. Needs a Metal GPU; not run in CI.
set -eu
out=target/bench
runs=5
chip=$(sysctl -n machdep.cpu.brand_string | tr 'A-Z ' 'a-z-')
# GPU clocks differ with the power source, so each source has its own baseline.
pmset -g batt | grep -q "AC Power" && power=ac || power=battery
chip=$chip-$power
base=benchmarks/baseline/$chip.json
mkdir -p "$out" benchmarks/baseline
cargo build --release -q -p verion-render-cli
# REQ-PERF-003 scale scene (5M triangles, four 4K textures) is too big to commit; generated once.
[ -f "$out/scale/scale.gltf" ] || python3 -I scripts/gen_scale_scene.py "$out/scale"
result="{}"
for scene in benchmarks/*.gltf "$out/scale/scale.gltf"; do
  name=$(basename "$scene" .gltf)
  best=
  for i in $(seq "$runs"); do
    ./target/release/render-cli "$scene" -o "$out/$name.exr" --width 1024 --height 768 --spp 1024 --metrics "$out/$name.json"
    t=$(jq .gpu_s "$out/$name.json")
    best=$(echo "$t ${best:-$t}" | awk '{print ($1 < $2) ? $1 : $2}')  # min of runs: noise only adds time
  done
  result=$(echo "$result" | jq --arg n "$name" --argjson t "$best" '.[$n] = {gpu_s: $t}')
done
echo "$result" > "$out/result.json"
if [ "${1:-}" = record ]; then
  cp "$out/result.json" "$base"
  echo "baseline recorded: $base"; cat "$base"; exit 0
fi
[ -f "$base" ] || { echo "no baseline for $chip; run: scripts/bench.sh record" >&2; exit 1; }
jq -r --slurpfile b "$base" 'to_entries[] | "\(.key) \(.value.gpu_s) \($b[0][.key].gpu_s // "none")"' "$out/result.json" |
while read -r n now was; do
  [ "$was" = none ] && { echo "$n: ${now}s (no baseline)"; continue; }
  echo "$n: ${now}s vs ${was}s" | awk -v n="$now" -v w="$was" '{print $0, sprintf("(%+.1f%%)", (n/w-1)*100)}'
  echo "$now $was" | awk '{exit !($1 > $2 * 1.10)}' && echo "WARN $n: regression over 10%" >&2
done 2>&1 | tee "$out/report.txt"
! grep -q '^WARN' "$out/report.txt"
