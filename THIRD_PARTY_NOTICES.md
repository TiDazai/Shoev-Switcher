# Third-party notices

Shoev Switcher includes a transformed English/Russian offline lexicon derived
from [wordfreq 3.1.1](https://github.com/rspeer/wordfreq),
[OpenCorpora](https://opencorpora.org/?page=downloads),
[SCOWL](https://github.com/engramtech/scowl), focused Wiktionary exports from
[Kaikki](https://kaikki.org/dictionary/), and English/Russian Wikipedia article
title dumps.

The wordfreq software is licensed under Apache License 2.0. Its combined
word-frequency data may be redistributed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) with the
source credits maintained by the project. The copy packaged inside the app is
filtered, case-folded, frequency-quantized and indexed as SQLite. Full bundled
attribution is in `Sources/ShoevSwitcher/Resources/LEXICON_LICENSES.md`.

Suggested citation: Robyn Speer (2022), *wordfreq v3.0*,
[Zenodo](https://doi.org/10.5281/zenodo.7199437).

OpenCorpora data is CC BY-SA 3.0. Wiktionary and Wikipedia text is CC BY-SA
4.0. SCOWL is distributed under its MIT-like permission notice and retains the
copyright of Kevin Atkinson and its upstream sources. Exact versions,
transformation details, links and required notices are bundled in
`Sources/ShoevSwitcher/Resources/LEXICON_LICENSES.md`.
