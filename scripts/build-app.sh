#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_dir/.build/distribution"
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/Shoev Switcher.app"
arm_scratch="$build_root/arm64"
x86_scratch="$build_root/x86_64"

mkdir -p "$build_root" "$dist_dir"

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --triple arm64-apple-macosx13.0 \
  --scratch-path "$arm_scratch"
arm_bin="$(swift build --package-path "$project_dir" --configuration release --triple arm64-apple-macosx13.0 --scratch-path "$arm_scratch" --show-bin-path)"

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --triple x86_64-apple-macosx13.0 \
  --scratch-path "$x86_scratch"
x86_bin="$(swift build --package-path "$project_dir" --configuration release --triple x86_64-apple-macosx13.0 --scratch-path "$x86_scratch" --show-bin-path)"

if [[ "$app_bundle" != "$dist_dir/Shoev Switcher.app" ]]; then
  echo "Unexpected app bundle path" >&2
  exit 1
fi
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

lipo -create \
  "$arm_bin/ShoevSwitcher" \
  "$x86_bin/ShoevSwitcher" \
  -output "$app_bundle/Contents/MacOS/ShoevSwitcher"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"

resource_bundle="$(find "$arm_bin" -maxdepth 1 -type d -name 'ShoevSwitcher_*.bundle' -print -quit)"
if [[ -n "$resource_bundle" ]]; then
  cp -R "$resource_bundle" "$app_bundle/Contents/Resources/"
fi

build_number="${BUILD_NUMBER:-1}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_bundle/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$project_dir/Resources/ShoevSwitcher.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$app_bundle"
else
  local_keychain="${SHOEV_LOCAL_KEYCHAIN:-$HOME/Library/Application Support/Shoev Switcher Development/LocalSigning.keychain-db}"
  local_identity="Shoev Switcher Local Development"
  if [[ -f "$local_keychain" ]] && security find-certificate -c "$local_identity" "$local_keychain" >/dev/null 2>&1; then
    security unlock-keychain -p "" "$local_keychain"
    certificate_sha="$({ security find-certificate -c "$local_identity" -Z "$local_keychain" || true; } | awk '/SHA-1/{print $3; exit}')"
    if [[ -z "$certificate_sha" ]]; then
      echo "Could not resolve local signing certificate" >&2
      exit 1
    fi
    codesign --force --deep --sign "$certificate_sha" --keychain "$local_keychain" "$app_bundle"
  else
    codesign --force --deep --sign - "$app_bundle"
  fi
fi

codesign --verify --deep --strict --verbose=2 "$app_bundle"
echo "$app_bundle"
