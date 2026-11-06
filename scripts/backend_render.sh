#!/bin/sh
# Renders the Backend comparison set (REQ-GPU-007) with this machine's backend into DIR:
#   scripts/backend_render.sh DIR [SPP]
# Run it on each machine (Metal on the Mac, Vulkan on the RTX 3080), then compare the two
# directories with scripts/backend_diff.sh. High spp keeps the Monte Carlo noise below the
# Backend difference being measured.
set -eu
dir=${1:?usage: backend_render.sh DIR [SPP]}
spp=${2:-4096}
mkdir -p "$dir"
cargo build --release -q -p verion-render-cli
cli=target/release/render-cli
# Reference mode: the physical beauty. Stylized mode: the Stylization Pass output, which reads the
# lighting AOVs, the normals and the albedo, so a Backend difference in any of them shows up there.
$cli scenes/cornell_box.gltf -o "$dir/cornell_reference.exr" --spp "$spp" --metrics "$dir/cornell_reference.json"
$cli scenes/cornell_box.gltf -o "$dir/cornell_wavefront.exr" --spp "$spp" --integrator wavefront
$cli scenes/toon_compare.gltf -o "$dir/toon_stylized.exr" --mode stylized --spp "$spp"
$cli scenes/lights_compare.gltf -o "$dir/lights_reference.exr" --spp "$spp"
$cli scenes/showcase.gltf -o "$dir/showcase_stylized.exr" --mode stylized --spp "$spp"
