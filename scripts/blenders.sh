#!/bin/sh
# Prints the Blender executables to test, one per line: $BLENDER (several separated by ':' on macOS and
# Linux, ';' on Windows) or every Blender in ~/Applications/Blender/stable (macOS).
if [ -n "${BLENDER:-}" ]; then
  printf '%s\n' "$BLENDER" | tr ';' '\n' | awk -F: -v OFS=: '{ for (i = 1; i <= NF; i++) { if (length($i) == 1 && $(i+1) ~ /^[\\\/]/) { print $i ":" $(i+1); i++ } else print $i } }'
else
  ls -d "$HOME"/Applications/Blender/stable/*/Blender.app/Contents/MacOS/Blender 2>/dev/null
fi
