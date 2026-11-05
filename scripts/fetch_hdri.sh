#!/bin/sh
# Downloads the real-world HDRIs listed in assets/hdri/SOURCES.md (Poly Haven, CC0) into assets/hdri/real/ and
# checks their md5. The files are not committed (about 1.5 MB each); run this when you need them.
# Usage: scripts/fetch_hdri.sh
set -eu
dir=assets/hdri/real
mkdir -p "$dir"
# id md5 (1k resolution .hdr)
while read -r id md5; do
  f="$dir/$id.hdr"
  if [ -f "$f" ] && [ "$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)" = "$md5" ]; then
    echo "ok      $id"; continue
  fi
  curl -fsSL "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/${id}_1k.hdr" -o "$f"
  got=$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)
  [ "$got" = "$md5" ] || { echo "md5 mismatch for $id: $got" >&2; rm -f "$f"; exit 1; }
  echo "fetched $id"
done <<LIST
kloofendal_48d_partly_cloudy_puresky c69498687e876bf68d2a8b8a62234eb9
venice_sunset a5ec4d30fc3421c214a17b208fb66d5f
studio_small_08 de3ba64222895aca876b1d1c2e0cf81a
overcast_soil_puresky 7fbca6264f4618a787092b9e1679a578
LIST
