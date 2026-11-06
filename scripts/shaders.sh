#!/bin/sh
# Compile shaders/*.slang to the MSL and SPIR-V committed under crates/verion-gpu-{metal,vulkan}/shaders,
# so building never needs slangc. Each file's compute entry point has the same name as the file.
# SPIR-V is pinned to 1.5 with ray query (Vulkan 1.2 baseline); slangc validates it while compiling.
# `check` compiles into a temp dir and fails when a committed file is stale.
set -eu
mode=${1:-build}
metal=crates/verion-gpu-metal/shaders
vulkan=crates/verion-gpu-vulkan/shaders
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
  case $name in
    # Ray generation shaders with shader execution reordering: Vulkan only (ADR-0014).
    *_ser)
      slangc "$src" -target spirv -profile spirv_1_5 -capability spvRayQueryKHR -capability spvShaderInvocationReorderEXT -entry "$name" -stage raygeneration -o "$vulkan_dest/$name.spv" ;;
    *)
      slangc "$src" -target metal -entry "$name" -stage compute -o "$metal_dest/$name.metal"
      slangc "$src" -target spirv -profile spirv_1_5 -capability spvRayQueryKHR -entry "$name" -stage compute -o "$vulkan_dest/$name.spv" ;;
  esac
done

if [ "$mode" = check ]; then
  status=0
  for f in "$tmp"/metal/*.metal "$tmp"/vulkan/*.spv; do
    case $f in *.metal) out=$metal ;; *) out=$vulkan ;; esac
    cmp -s "$f" "$out/$(basename "$f")" || { echo "stale: $out/$(basename "$f") (run: mise run shaders)" >&2; status=1; }
  done
  rm -rf "$tmp"
  exit $status
fi
