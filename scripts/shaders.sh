#!/bin/sh
# Compile shaders/*.slang to the MSL committed under crates/verion-gpu-metal/shaders.
# Each file's compute entry point has the same name as the file.
# `check` compiles into a temp dir and fails when the committed MSL is stale.
set -eu
mode=${1:-build}
out=crates/verion-gpu-metal/shaders
dest=$out
[ "$mode" = check ] && dest=$(mktemp -d)

for src in shaders/*.slang; do
  name=$(basename "$src" .slang)
  slangc "$src" -target metal -entry "$name" -stage compute -o "$dest/$name.metal"
done

if [ "$mode" = check ]; then
  status=0
  for f in "$dest"/*.metal; do
    cmp -s "$f" "$out/$(basename "$f")" || { echo "stale: $out/$(basename "$f") (run: mise run shaders)" >&2; status=1; }
  done
  rm -rf "$dest"
  exit $status
fi
