#!/bin/sh
# Time to quality, ReSTIR against plain path tracing (REQ-ACC-002, REQ-PERF-001): renders each scene
# in reference mode, in interactive mode with ReSTIR DI only (--restir-gi=false) and in interactive
# mode with DI and GI, over a ladder of sample counts, and compares
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
    for variant in reference interactive interactive+gi; do
      mode=${variant%+gi}; flag=--restir-gi=false
      [ "$variant" = interactive+gi ] && flag=--restir-gi
      [ "$variant" = reference ] && flag=
      f="$out/$name-$variant-$spp"
      $cli "$scene" -o "$f.exr" $size --spp "$spp" --mode "$mode" $flag $extra --metrics "$f.json"
      echo "| $name | $variant | $spp | $(jq .gpu_s "$f.json" | awk '{printf "%.4f", $1}') | $(diff "$out/$name-ref.exr" "$f.exr") |" >> "$out/report.md"
    done
  done
done
cat "$out/report.md"
# Time each variant needs to reach the error of reference at 128 spp (log-log interpolation).
python3 -I - "$out/report.md" <<'PY' | tee "$out/speedup.md"
import math, sys
rows = {}
for line in open(sys.argv[1]).read().splitlines()[2:]:
    c = [x.strip() for x in line.strip("|").split("|")]
    rows.setdefault((c[0], c[1]), []).append((float(c[3]), float(c[4])))
print("| scene | variant | time to the error of reference at 128 spp (s) | speedup |")
print("|---|---|---|---|")
for scene in sorted({k[0] for k in rows}):
    target = next(e for t, e in rows[(scene, "reference")][7:8])
    base = rows[(scene, "reference")][7][0]
    for variant in ("reference", "interactive", "interactive+gi"):
        pts = rows[(scene, variant)]
        t = None
        for (t0, e0), (t1, e1) in zip(pts, pts[1:]):
            if e0 >= target >= e1:
                f = (math.log(e0) - math.log(target)) / (math.log(e0) - math.log(e1))
                t = math.exp(math.log(t0) + f * (math.log(t1) - math.log(t0)))
                break
        print(f"| {scene} | {variant} | {t:.3f} | {base / t:.2f}x |" if t else f"| {scene} | {variant} | not reached | |")
PY
