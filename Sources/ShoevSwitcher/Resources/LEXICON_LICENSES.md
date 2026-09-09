# Embedded lexicon notices

The `lexicon.sqlite3` file distributed with Shoev Switcher is a transformed,
indexed subset of the English and Russian frequency data from **wordfreq 3.1.1**.
It remains accompanied by this attribution file in the application bundle.

wordfreq code is Copyright © 2015–2024 Luminoso Technologies, Inc., Robyn
Speer, and contributors, and is licensed under the Apache License 2.0.

The word-frequency data combines multiple attributed sources and may be
redistributed under the Creative Commons Attribution-ShareAlike 4.0
International license (CC BY-SA 4.0). Relevant data sources include Wikipedia;
Google Books Ngrams and Syntactic Ngrams; the Leeds Internet Corpus; ParaCrawl;
OPUS OpenSubtitles 2018 (with attribution to OpenSubtitles); SUBTLEX-US and
SUBTLEX-UK; NewsCrawl; GlobalVoices; OSCAR; Twitter; and Reddit.

- Project and source credits: https://github.com/rspeer/wordfreq
- Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0
- CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Citation: Robyn Speer (2022), *wordfreq v3.0*, Zenodo,
  https://doi.org/10.5281/zenodo.7199437

The embedded lists credit the authors of the SUBTLEX resources, which are
freely available data. Key citations for the English and Russian source mix:

- Brysbaert, M. & New, B. (2009). Moving beyond Kucera and Francis: A Critical
  Evaluation of Current Word Frequency Norms and the Introduction of a New and
  Improved Word Frequency Measure for American English. *Behavior Research
  Methods*, 41(4), 977–990.
- van Heuven, W. J., Mandera, P., Keuleers, E., & Brysbaert, M. (2014).
  SUBTLEX-UK: A new and improved word frequency database for British English.
  *The Quarterly Journal of Experimental Psychology*, 67(6), 1176–1190.
- Lison, P. & Tiedemann, J. (2016). OpenSubtitles2016: Extracting Large Parallel
  Corpora from Movie and TV Subtitles. *LREC 2016*.
- Lin, Y., Michel, J.-B., Aiden, E. L., Orwant, J., Brockman, W., & Petrov, S.
  (2012). Syntactic annotations for the Google Books Ngram Corpus. *ACL 2012*,
  169–174.
- Ortiz Suárez, P. J., Sagot, B., & Romary, L. (2019). Asynchronous pipelines
  for processing huge corpora on medium to low resource infrastructures.
  *CMLC-7 2019*.

Changes made for Shoev Switcher: the complete `best` English and Russian lists
were filtered to single alphabetic words (allowing internal apostrophes and
hyphens), case-folded, assigned a quantized Zipf frequency score, and stored in
a read-only SQLite index. No original source text or corpus content is included.
