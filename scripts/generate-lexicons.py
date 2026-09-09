#!/usr/bin/env python3
"""Build the embedded read-only RU/EN frequency lexicon.

The resulting database is a derived redistribution of wordfreq data. Keep
Sources/ShoevSwitcher/Resources/LEXICON_LICENSES.md beside it in the bundle.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
from pathlib import Path

from wordfreq import iter_wordlist, zipf_frequency


LANGUAGES = {
    "en": re.compile(r"^[a-z]+(?:['-][a-z]+)*$"),
    "ru": re.compile(r"^[а-яё]+(?:['-][а-яё]+)*$"),
}


def words_for(language: str):
    pattern = LANGUAGES[language]
    for word in iter_wordlist(language, wordlist="best"):
        normalized = word.casefold()
        if not pattern.fullmatch(normalized):
            continue
        score = round(zipf_frequency(normalized, language, wordlist="best") * 100)
        yield normalized, score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)

    connection = sqlite3.connect(args.output)
    try:
        connection.execute("PRAGMA page_size = 4096")
        connection.execute("PRAGMA journal_mode = OFF")
        connection.execute("PRAGMA synchronous = OFF")
        connection.execute(
            """
            CREATE TABLE words (
                language TEXT NOT NULL,
                word TEXT NOT NULL,
                score INTEGER NOT NULL,
                PRIMARY KEY (language, word)
            ) WITHOUT ROWID
            """
        )
        for language in LANGUAGES:
            connection.executemany(
                "INSERT INTO words(language, word, score) VALUES (?, ?, ?)",
                ((language, word, score) for word, score in words_for(language)),
            )
        connection.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID")
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            [
                ("format", "1"),
                ("source", "wordfreq 3.1.1"),
                ("license", "CC BY-SA 4.0; see LEXICON_LICENSES.md"),
            ],
        )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
