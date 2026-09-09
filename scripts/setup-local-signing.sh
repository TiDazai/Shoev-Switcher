#!/bin/bash
set -euo pipefail

# Creates a persistent, Mac-local identity for development builds. The private
# key lives outside the repository and is never shipped in a release.
identity_name="Shoev Switcher Local Development"
signing_dir="${SHOEV_SIGNING_DIR:-$HOME/Library/Application Support/Shoev Switcher Development}"
keychain_path="$signing_dir/LocalSigning.keychain-db"

mkdir -p "$signing_dir"
chmod 700 "$signing_dir"

if [[ -f "$keychain_path" ]] && security find-certificate -c "$identity_name" "$keychain_path" >/dev/null 2>&1; then
  echo "$keychain_path"
  exit 0
fi

if [[ -e "$keychain_path" ]]; then
  echo "Incomplete local signing keychain: $keychain_path" >&2
  exit 1
fi

temporary_dir="$(mktemp -d /tmp/shoev-local-signing.XXXXXX)"
cleanup() {
  find "$temporary_dir" -type f -delete 2>/dev/null || true
  rmdir "$temporary_dir" 2>/dev/null || true
}
trap cleanup EXIT

archive_password="$(openssl rand -hex 24)"
openssl req \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -subj "/CN=$identity_name/O=Shoev Switcher" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$temporary_dir/key.pem" \
  -out "$temporary_dir/certificate.pem" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -out "$temporary_dir/identity.p12" \
  -inkey "$temporary_dir/key.pem" \
  -in "$temporary_dir/certificate.pem" \
  -passout "pass:$archive_password"

security create-keychain -p "" "$keychain_path"
security unlock-keychain -p "" "$keychain_path"
security import "$temporary_dir/identity.p12" \
  -k "$keychain_path" \
  -P "$archive_password" \
  -T /usr/bin/codesign \
  >/dev/null

chmod 600 "$keychain_path"
echo "$keychain_path"
