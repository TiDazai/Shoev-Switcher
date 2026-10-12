#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$project_dir/dist/Shoev Switcher.app"
dmg_path="$project_dir/dist/Shoev-Switcher.dmg"
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$project_dir/scripts/build-app.sh"
fi
codesign --verify --deep --strict "$app_bundle"
staging_dir="$(mktemp -d "$project_dir/.build/dmg-root.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_bundle" "$staging_dir/Shoev Switcher.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Shoev Switcher" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg_path"
fi
hdiutil verify "$dmg_path"

echo "$dmg_path"
