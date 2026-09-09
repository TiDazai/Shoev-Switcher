#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_logo="$project_dir/Resources/Brand/sswitcher-logo.png"
menu_master="$project_dir/Resources/Brand/MenuBarIcon-master.png"
iconset_dir="$project_dir/.build/generated-icons/AppIcon.iconset"

mkdir -p "$iconset_dir" "$project_dir/Sources/ShoevSwitcher/Resources"

for specification in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  size="${specification%% *}"
  filename="${specification#* }"
  sips -z "$size" "$size" "$source_logo" --out "$iconset_dir/$filename" >/dev/null
done

iconutil -c icns "$iconset_dir" -o "$project_dir/Resources/AppIcon.icns"
sips -z 36 36 "$menu_master" \
  --out "$project_dir/Sources/ShoevSwitcher/Resources/MenuBarIcon.png" >/dev/null

echo "$project_dir/Resources/AppIcon.icns"
echo "$project_dir/Sources/ShoevSwitcher/Resources/MenuBarIcon.png"
