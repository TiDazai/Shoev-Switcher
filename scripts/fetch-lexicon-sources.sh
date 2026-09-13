#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
tools_dir="$project_dir/.build/dictionary-tools"
sources_dir="$project_dir/.build/lexicon-sources"
scowl_dir="$project_dir/.build/scowl"

mkdir -p "$tools_dir" "$sources_dir"
python3 -m pip install --quiet --target "$tools_dir" \
  "wordfreq==3.1.1" \
  "pymorphy3==2.0.6" \
  "pymorphy3-dicts-ru==2.4.417150.4580142"

scowl_commit="3373b9f12dce7016c9df2713ef733131e9022bc1"
if [[ ! -d "$scowl_dir/.git" ]]; then
  git clone --quiet https://github.com/engramtech/scowl.git "$scowl_dir"
fi
git -C "$scowl_dir" fetch --quiet origin "$scowl_commit"
git -C "$scowl_dir" checkout --quiet --detach "$scowl_commit"
make --silent -C "$scowl_dir"

download() {
  local output="$1"
  local url="$2"
  [[ -s "$output" ]] || curl -LsS --fail --retry 3 -o "$output" "$url"
}

for language in Russian English; do
  if [[ "$language" == "Russian" ]]; then
    code="ru"
  else
    code="en"
  fi

  download "$sources_dir/$code-names.jsonl" \
    "https://kaikki.org/dictionary/$language/pos-name/kaikki.org-dictionary-$language-by-pos-name.jsonl"

  while read -r bucket category; do
    download "$sources_dir/$code-$category.jsonl" \
      "https://kaikki.org/dictionary/$language/tags/$bucket/$category/kaikki.org-dictionary-$language-tag-$category.jsonl"
  done <<'EOF'
f- colloquial
Fy derogatory
ij informal
lS offensive
T~ proscribed
AH slang
hR vulgar
EOF
done

download "$sources_dir/en-wikipedia-titles.gz" \
  "https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-all-titles-in-ns0.gz"
download "$sources_dir/ru-wikipedia-titles.gz" \
  "https://dumps.wikimedia.org/ruwiki/latest/ruwiki-latest-all-titles-in-ns0.gz"

echo "Dictionary sources are ready in $sources_dir"
