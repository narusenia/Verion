#!/bin/sh
# Stylization evaluation, first version (REQ-QA-003; M2 item 11). For each Toon scene and light it renders a
# 1024 spp stylized reference and a low-sample render without denoising, with OIDN on the Pass input
# (lighting AOVs) and with OIDN on the stylized output, then scores them with the style_eval example
# (Toon band edges kept, noise on flat areas) and exr_diff (mean and block deviation). Needs a Metal GPU
# and OIDN for the denoised rows; not run in CI. Results: target/style-eval/report.txt.
set -eu
out=target/style-eval
spp=${1:-16}
mkdir -p "$out"
cargo build --release -q -p verion-render-cli
cargo build --release -q -p verion-render-io --example style_eval --example exr_diff
cli=./target/release/render-cli
status=0
: > "$out/report.txt"
for case in toon_compare:sunny toon_compare:softbox lights_compare:none; do
  scene=${case%%:*}; light=${case#*:}
  name=$scene-$light
  hdri=; [ "$light" = none ] || hdri="--hdri assets/hdri/$light.hdr"
  run() { $cli "scenes/$scene.gltf" --mode stylized --width 512 --height 384 $hdri "$@"; }
  run --spp 1024 -o "$out/$name-ref.exr"
  run --spp "$spp" -o "$out/$name-raw.exr"
  run --spp "$spp" --denoise --denoise-stage input -o "$out/$name-input.exr" --metrics "$out/$name-input.json"
  run --spp "$spp" --denoise --denoise-stage output -o "$out/$name-output.exr" --metrics "$out/$name-output.json"
  {
    echo "== $name ($spp spp vs 1024 spp)"
    ./target/release/examples/style_eval "$out/$name-ref.exr" "$out/$name-raw.exr" "$out/$name-input.exr" "$out/$name-output.exr" || status=1
    ./target/release/examples/exr_diff "$out/$name-ref.exr" "$out/$name-raw.exr" "$out/$name-input.exr" "$out/$name-output.exr" || true
    echo "denoise_s input $(jq .denoise_s "$out/$name-input.json") output $(jq .denoise_s "$out/$name-output.json")"
  } | tee -a "$out/report.txt"
done
exit $status
