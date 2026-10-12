#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
archive="$project_dir/Resources/Lexicon/lexicon.sqlite3.gz"
destination="$project_dir/Sources/ShoevSwitcher/Resources/lexicon.sqlite3"

mkdir -p "$project_dir/.build"
archive_sha="493b2b9e1ac83d755a77b24d031affb6a0ba05ac5cfeea0c9aff16ad054a4025"
database_sha="f1844bb92d2204c669803f2336e514e5b40eb6559e00c3ecd163c081ffa24b32"

if [[ -f "$destination" && "$(shasum -a 256 "$destination" | awk '{print $1}')" == "$database_sha" ]]; then
  exit 0
fi

if [[ ! -f "$archive" ]]; then
  echo "Missing compressed lexicon: $archive" >&2
  exit 1
fi

if [[ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$archive_sha" ]]; then
  echo "Compressed lexicon checksum mismatch" >&2
  exit 1
fi

temporary_dir="$(mktemp -d "$project_dir/.build/lexicon-prepare.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
gzip -dc "$archive" > "$temporary_dir/lexicon.sqlite3"
if [[ "$(shasum -a 256 "$temporary_dir/lexicon.sqlite3" | awk '{print $1}')" != "$database_sha" ]]; then
  echo "Embedded lexicon checksum mismatch" >&2
  exit 1
fi

if [[ "$(sqlite3 "$temporary_dir/lexicon.sqlite3" 'PRAGMA integrity_check')" != "ok" ]]; then
  echo "Embedded lexicon failed its integrity check" >&2
  exit 1
fi

mv "$temporary_dir/lexicon.sqlite3" "$destination"
