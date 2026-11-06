#!/bin/sh
# Builds the Blender add-on as an extension zip for this machine's platform: the `verion` abi3 wheel
# goes into the extension (Blender installs it with the add-on), and `blender --command extension build`
# writes target/blender-extension/verion-<version>-<platform>.zip. Run it on each platform (macOS
# Apple silicon, Windows x64). Needs a Blender 4.5 or later (BLENDER=path overrides the search).
# Open Image Denoise is not bundled: Blender ships its own copy, which the add-on uses (native.py).
set -eu
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=macos-arm64 ;;
  MINGW*|MSYS*|CYGWIN*) platform=windows-x64 ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
blender=${BLENDER:-$(ls -d "$HOME"/Applications/Blender/stable/*/Blender.app/Contents/MacOS/Blender 2>/dev/null | tail -1)}
[ -x "${blender:-}" ] || { echo "set BLENDER to a Blender 4.5+ executable" >&2; exit 1; }

stage=target/blender-extension/stage
out=target/blender-extension
rm -rf "$out"; mkdir -p "$stage/wheels"
maturin build --release -q -m crates/verion-py/Cargo.toml -o "$out/wheel"
wheel=$(basename "$(ls "$out"/wheel/*.whl)")
cp "$out/wheel/$wheel" "$stage/wheels/"
cp plugins/blender/verion_blender/*.py "$stage/"
# The manifest of the source tree has no wheel: add this platform's wheel and platform before its
# [permissions] table.
awk -v platform="$platform" -v wheel="$wheel" '
  /^\[permissions\]/ { printf "platforms = [\"%s\"]\nwheels = [\"./wheels/%s\"]\n\n", platform, wheel }
  { print }' plugins/blender/verion_blender/blender_manifest.toml > "$stage/blender_manifest.toml"
"$blender" --factory-startup --command extension validate "$stage"
"$blender" --factory-startup --command extension build --source-dir "$stage" --output-dir "$out"
ls "$out"/*.zip

# Smoke test: install the zip into an empty Blender profile and render with it. The profile is a temporary
# directory, so the developer's Blender preferences are not touched.
profile=$(mktemp -d)
BLENDER_USER_RESOURCES=$profile "$blender" -b --command extension install-file -r user_default -e "$out"/verion-*.zip
BLENDER_USER_RESOURCES=$profile "$blender" -b --python plugins/blender/tests/smoke_installed.py 2>&1 | grep -E "SMOKE|Error|Traceback" || { rm -rf "$profile"; echo "smoke test failed" >&2; exit 1; }
rm -rf "$profile"
