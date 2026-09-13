#!/usr/bin/env python3
"""Build Shoev Switcher's compact offline RU/EN lexicon.

The base frequency scores come from wordfreq. Optional sources add OpenCorpora
morphology (through pymorphy3), SCOWL, and focused Kaikki/Wiktionary exports
for names, slang and non-standard language. Run
``scripts/fetch-lexicon-sources.sh`` before this script for the full build.
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sqlite3
import subprocess
import unicodedata
from pathlib import Path
from typing import Iterable, Iterator

from wordfreq import iter_wordlist, zipf_frequency


LANGUAGE_IDS = {"en": 0, "ru": 1}
LANGUAGE_PATTERNS = {
    "en": re.compile(r"^[a-z]+(?:['-][a-z]+)*$"),
    "ru": re.compile(r"^[а-яё]+(?:['-][а-яё]+)*$"),
}
KAIKKI_SCORES = {
    "names": 285,
    "colloquial": 310,
    "informal": 305,
    "proscribed": 305,
    "derogatory": 320,
    "offensive": 320,
    "slang": 320,
    "vulgar": 325,
}
IGNORED_FORM_TAGS = {
    "canonical",
    "class",
    "inflection-template",
    "romanization",
    "table-tags",
    "transliteration",
}


def normalize_word(value: str, language: str) -> str | None:
    decomposed = unicodedata.normalize("NFD", value.casefold())
    if language == "ru":
        # Wiktionary adds stress marks. Preserve the combining marks that are
        # part of actual Russian letters (й and ё) while removing only stress.
        decomposed = decomposed.replace("\N{COMBINING ACUTE ACCENT}", "").replace(
            "\N{COMBINING GRAVE ACCENT}", ""
        )
        normalized = unicodedata.normalize("NFC", decomposed)
    else:
        normalized = "".join(
            char for char in decomposed if not unicodedata.combining(char)
        )
    return normalized if LANGUAGE_PATTERNS[language].fullmatch(normalized) else None


def wordfreq_words(language: str) -> Iterator[tuple[str, int]]:
    for word in iter_wordlist(language, wordlist="best"):
        normalized = normalize_word(word, language)
        if normalized is None:
            continue
        score = max(
            101,
            round(zipf_frequency(normalized, language, wordlist="best") * 100),
        )
        yield normalized, score


def pymorphy_words() -> Iterator[str]:
    try:
        import pymorphy3
    except ImportError as error:
        raise RuntimeError(
            "pymorphy3 is missing; run scripts/fetch-lexicon-sources.sh first"
        ) from error

    dictionary = pymorphy3.MorphAnalyzer().dictionary
    previous: str | None = None
    for word in dictionary.words.iterkeys():
        if word == previous:
            continue
        previous = word
        normalized = normalize_word(word, "ru")
        if normalized is not None:
            yield normalized


def scowl_words(scowl_dir: Path) -> Iterator[str]:
    scowl_dir = scowl_dir.resolve()
    command = [
        str(scowl_dir / "scowl"),
        "word-list",
        "--size", "80",
        "--spellings", "A,B,Z,C,D",
        "--variant-level", "8",
    ]
    process = subprocess.Popen(
        command,
        cwd=scowl_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    assert process.stdout is not None
    for line in process.stdout:
        normalized = normalize_word(line.strip().removesuffix("."), "en")
        if normalized is not None:
            yield normalized
    if process.wait() != 0:
        raise RuntimeError("SCOWL word-list export failed")


def kaikki_words(path: Path, language: str) -> Iterator[str]:
    with path.open(encoding="utf-8") as source:
        for line_number, line in enumerate(source, 1):
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as error:
                raise RuntimeError(f"Invalid Kaikki JSON at {path}:{line_number}") from error

            values = [entry.get("word", "")]
            for form in entry.get("forms", []):
                tags = set(form.get("tags", []))
                if tags & IGNORED_FORM_TAGS:
                    continue
                values.append(form.get("form", ""))

            for value in values:
                normalized = normalize_word(value, language)
                if normalized is not None:
                    yield normalized


def wikipedia_title_words(path: Path, language: str) -> Iterator[str]:
    """Yield single-token titles and capitalized parts of multi-token titles."""
    token_pattern = re.compile(r"[^\W\d_]+(?:['’-][^\W\d_]+)*", re.UNICODE)
    with gzip.open(path, mode="rt", encoding="utf-8", errors="ignore") as source:
        for line_number, line in enumerate(source):
            if line_number == 0 and line.rstrip() == "page_title":
                continue
            tokens = token_pattern.findall(line.replace("_", " "))
            for token in tokens:
                if len(tokens) > 1 and not token[0].isupper():
                    continue
                normalized = normalize_word(token.replace("’", "'"), language)
                if normalized is not None:
                    yield normalized


def add_words(
    connection: sqlite3.Connection,
    language: str,
    source: str,
    words: Iterable[tuple[str, int]],
    protects_original: bool = True,
) -> int:
    before = connection.total_changes
    language_id = LANGUAGE_IDS[language]
    connection.executemany(
        """
        INSERT INTO words(language, word, score, protects_original) VALUES (?, ?, ?, ?)
        ON CONFLICT(language, word) DO UPDATE SET
            score=max(score, excluded.score),
            protects_original=max(protects_original, excluded.protects_original)
        """,
        (
            (language_id, word, score, int(protects_original))
            for word, score in words
        ),
    )
    processed = connection.total_changes - before
    connection.execute(
        "INSERT INTO source_stats(source, language, processed) VALUES (?, ?, ?)",
        (source, language, processed),
    )
    connection.commit()
    print(f"{source} ({language}): {processed:,} records processed", flush=True)
    return processed


def scored(words: Iterable[str], score: int) -> Iterator[tuple[str, int]]:
    for word in words:
        yield word, score


def build_database(output: Path, sources_dir: Path, scowl_dir: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)

    connection = sqlite3.connect(output)
    try:
        connection.executescript(
            """
            PRAGMA page_size=4096;
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA temp_store=MEMORY;
            CREATE TABLE words (
                language INTEGER NOT NULL,
                word TEXT NOT NULL,
                score INTEGER NOT NULL,
                protects_original INTEGER NOT NULL,
                PRIMARY KEY (language, word)
            ) WITHOUT ROWID;
            CREATE TABLE source_stats (
                source TEXT NOT NULL,
                language TEXT NOT NULL,
                processed INTEGER NOT NULL,
                PRIMARY KEY (source, language)
            ) WITHOUT ROWID;
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;
            """
        )

        for language in LANGUAGE_IDS:
            add_words(connection, language, "wordfreq 3.1.1", wordfreq_words(language))

        add_words(
            connection,
            "ru",
            "OpenCorpora 0.92 / pymorphy3-dicts-ru 2.4.417150.4580142",
            scored(pymorphy_words(), 290),
        )

        if not (scowl_dir / "scowl.db").exists():
            raise RuntimeError("SCOWL database is missing; run scripts/fetch-lexicon-sources.sh")
        add_words(connection, "en", "SCOWL v2 3373b9f", scored(scowl_words(scowl_dir), 290))

        for language in LANGUAGE_IDS:
            for category, score in KAIKKI_SCORES.items():
                path = sources_dir / f"{language}-{category}.jsonl"
                if not path.exists():
                    raise RuntimeError(f"Missing {path}; run scripts/fetch-lexicon-sources.sh")
                add_words(
                    connection,
                    language,
                    f"Kaikki/Wiktionary {category} 2026-09-09",
                    scored(kaikki_words(path, language), score),
                )

            wikipedia_path = sources_dir / f"{language}-wikipedia-titles.gz"
            if not wikipedia_path.exists():
                raise RuntimeError(
                    f"Missing {wikipedia_path}; run scripts/fetch-lexicon-sources.sh"
                )
            add_words(
                connection,
                language,
                f"{language} Wikipedia article titles 2026-09",
                scored(wikipedia_title_words(wikipedia_path, language), 280),
                protects_original=False,
            )

        counts = dict(
            connection.execute(
                "SELECT language, count(*) FROM words GROUP BY language"
            ).fetchall()
        )
        metadata = {
            "format": "2",
            "generated": "2026-09-13",
            "english_words": str(counts.get(LANGUAGE_IDS["en"], 0)),
            "russian_words": str(counts.get(LANGUAGE_IDS["ru"], 0)),
            "license": "See LEXICON_LICENSES.md",
        }
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)", metadata.items()
        )
        connection.commit()
        connection.execute("ANALYZE")
        connection.execute("VACUUM")
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--sources-dir", type=Path, default=Path(".build/lexicon-sources"))
    parser.add_argument("--scowl-dir", type=Path, default=Path(".build/scowl"))
    args = parser.parse_args()
    build_database(args.output, args.sources_dir, args.scowl_dir)


if __name__ == "__main__":
    main()
