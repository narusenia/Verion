#!/bin/sh
# Builds the `verion` Python extension (release, abi3) and unpacks the wheel into target/py, where
# the Blender add-on's tests find it (plugins/blender/verion_blender/native.py).
set -eu
rm -rf target/py target/py-wheel
maturin build --release -q -m crates/verion-py/Cargo.toml -o target/py-wheel
mkdir -p target/py
python3 -m zipfile -e target/py-wheel/*.whl target/py
