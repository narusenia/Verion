#!/bin/sh
# Builds the `verion` Python extension (release, abi3) and runs the GPU tests under a plain Python
# and under the Python of each Blender in ~/Applications/Blender/stable (Blender 4.5 LTS: Python
# 3.11 and numpy 1.x; 5.x: Python 3.13 and numpy 2.x). Needs maturin and a ray tracing GPU; not run in CI.
# `blender-only` skips the plain Python.
set -eu
out=target/py
rm -rf "$out" target/py-wheel
maturin build --release -q -m crates/verion-py/Cargo.toml -o target/py-wheel
mkdir -p "$out"
unzip -q target/py-wheel/*.whl -d "$out"
export PYTHONPATH="$PWD/$out"
tests=crates/verion-py/tests
if [ "${1:-}" != blender-only ]; then
  echo "== plain Python"
  uv run --quiet --python 3.12 --with numpy python -m unittest discover -s "$tests" -p 'test_*.py' 2>&1 | tail -5
fi
cat > "$out/run_tests.py" <<PY
import sys, unittest
sys.path.insert(0, "$PWD/$out")
r = unittest.TextTestRunner().run(unittest.defaultTestLoader.discover("$PWD/$tests", "test_*.py"))
sys.exit(not r.wasSuccessful())
PY
for b in "$HOME"/Applications/Blender/stable/*/Blender.app/Contents/MacOS/Blender; do
  echo "== $("$b" --version | head -1)"
  "$b" -b --factory-startup --python-exit-code 1 --python "$out/run_tests.py" 2>&1 | grep -E "^(Ran|OK|FAIL|ERROR)|Error|Traceback" || true
done
