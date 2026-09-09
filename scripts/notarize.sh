#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
dmg_path="$project_dir/dist/Shoev-Switcher.dmg"

: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"

xcrun notarytool submit "$dmg_path" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
