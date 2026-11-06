#!/bin/sh
# Runs the Blender add-on's tests (plugins/blender/tests/test_*.py) under each Blender in
# ~/Applications/Blender/stable (4.5 LTS and 5.x). They render with Verion and Cycles and compare,
# so they need a ray tracing GPU and the extension built by scripts/py_build.sh; not run in CI.
# Optional arguments are test file names (without the directory) to run instead of all of them.
set -eu
[ -d target/py ] || sh scripts/py_build.sh
status=0
for b in "$HOME"/Applications/Blender/stable/*/Blender.app/Contents/MacOS/Blender; do
  echo "== $("$b" --version | head -1)"
  for t in ${@:-plugins/blender/tests/test_*.py}; do
    case $t in */*) ;; *) t=plugins/blender/tests/$t ;; esac
    out=$("$b" -b --factory-startup --python-exit-code 1 --python "$t" 2>&1) && r=ok || { r=FAILED; status=1; }
    echo "$(basename "$t"): $r"
    [ "$r" = ok ] || echo "$out" | grep -a -E "^(FAIL|ERROR)|Error|Traceback|assert" | head -20
  done
done
exit $status
