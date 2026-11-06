#!/bin/sh
# Compile shaders/*.slang to the MSL and SPIR-V committed under crates/verion-gpu-{metal,vulkan}/shaders,
# so building never needs slangc. Each file's compute entry point has the same name as the file.
# SPIR-V is pinned to 1.5 with ray query (Vulkan 1.2 baseline); slangc validates it while compiling.
# `check` compiles into a temp dir (so a shader that no longer compiles fails) and fails when a committed
# file is stale. MSL is compared byte for byte. SPIR-V is not: slangc orders constants differently on
# macOS and Windows, so the same source gives different bytes there. Its staleness is judged by a
# checksum of the Slang sources (line endings ignored) kept in sources.cksum next to the SPIR-V.
set -eu
mode=${1:-build}
metal=crates/verion-gpu-metal/shaders
vulkan=crates/verion-gpu-vulkan/shaders
sources_sum() {
  for f in shaders/*.slang shaders/include/*.slang; do
    printf '%s ' "$f"
    tr -d '\r' < "$f" | cksum
  done
}

tmp=
if [ "$mode" = check ]; then
  tmp=$(mktemp -d)
  mkdir "$tmp/metal" "$tmp/vulkan"
  metal_dest=$tmp/metal
  vulkan_dest=$tmp/vulkan
else
  mkdir -p "$vulkan"
  metal_dest=$metal
  vulkan_dest=$vulkan
fi

for src in shaders/*.slang; do
  name=$(basename "$src" .slang)
  slangc "$src" -target metal -entry "$name" -stage compute -o "$metal_dest/$name.metal"
  slangc "$src" -target spirv -profile spirv_1_5 -capability spvRayQueryKHR -entry "$name" -stage compute -o "$vulkan_dest/$name.spv"
done

[ "$mode" = check ] || sources_sum > "$vulkan/sources.cksum"

if [ "$mode" = check ]; then
  status=0
  for f in "$tmp"/metal/*.metal; do
    cmp -s "$f" "$metal/$(basename "$f")" || { echo "stale: $metal/$(basename "$f") (run: mise run shaders)" >&2; status=1; }
  done
  [ "$(sources_sum)" = "$(tr -d '\r' < "$vulkan/sources.cksum")" ] || { echo "stale: $vulkan/*.spv (run: mise run shaders)" >&2; status=1; }
  rm -rf "$tmp"
  exit $status
fi
