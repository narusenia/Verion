#!/bin/sh
# Opens a Blender window with the add-on loaded from this repository, for the GUI checks in
# docs/handoff/2026-11-06-m6-device-checks.md. Builds the extension first if needed. First Blender in
# scripts/blenders.sh unless $1 is given (a path).
set -eu
[ -d target/py ] || sh scripts/py_build.sh
b=${1:-$(sh scripts/blenders.sh | tail -1)}
exec "$b" --python plugins/blender/dev_launch.py
