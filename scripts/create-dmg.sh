#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$project_dir/dist/Shoev Switcher.app"
dmg_path="$project_dir/dist/Shoev-Switcher.dmg"
staging_dir="$project_dir/.build/dmg-root"

if [[ ! -d "$app_bundle" ]]; then
  echo "Build the app first: ./scripts/build-app.sh" >&2
  exit 1
fi

mkdir -p "$staging_dir"
ditto "$app_bundle" "$staging_dir/Shoev Switcher.app"
ln -sfn /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Shoev Switcher" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg_path"
fi

echo "$dmg_path"
