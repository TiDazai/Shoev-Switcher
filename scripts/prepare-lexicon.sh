#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
archive="$project_dir/Resources/Lexicon/lexicon.sqlite3.gz"
destination="$project_dir/Sources/ShoevSwitcher/Resources/lexicon.sqlite3"

if [[ ! -f "$archive" ]]; then
  echo "Missing compressed lexicon: $archive" >&2
  exit 1
fi

if [[ -f "$destination" && "$destination" -nt "$archive" ]]; then
  exit 0
fi

temporary_dir="$(mktemp -d "$project_dir/.build/lexicon-prepare.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
gzip -dc "$archive" > "$temporary_dir/lexicon.sqlite3"

if [[ "$(sqlite3 "$temporary_dir/lexicon.sqlite3" 'PRAGMA integrity_check')" != "ok" ]]; then
  echo "Embedded lexicon failed its integrity check" >&2
  exit 1
fi

mv "$temporary_dir/lexicon.sqlite3" "$destination"
