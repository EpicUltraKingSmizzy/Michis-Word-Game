"""Builds assets/dict/words.txt.gz from a SCOWL word list.

Usage: python3 tool/build_dictionary.py path/to/scowl70_us_gb.txt

The input is SCOWL size 70, American + British (one word per line). Only
lowercase a-z words of 3+ letters are kept, and the words listed in
tool/dict/removed_words.txt (obscure words, proper nouns and their inflections)
are left out. The slur blocklist is NOT applied here; it lives in
assets/dict/blocklist.txt and is applied when the game loads.

The other word lists (assets/dict/slang.txt.gz, profanity.txt.gz,
places.txt.gz and person_names.txt.gz) are maintained by hand (gzip of a
sorted one-word-per-line list) and are not touched by this script. Any word
already in one of them is left out of words.txt.gz, so every word stays in
exactly one file. Run tool/dict/check_duplicates.py afterwards.
"""
import gzip, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
removed = {l.strip() for l in open(os.path.join(here, 'dict', 'removed_words.txt'), encoding='utf-8')
           if l.strip() and not l.startswith('#')}
others = set()
for name in ('slang', 'profanity', 'places', 'person_names'):
    others |= {w.strip() for w in gzip.open(f'assets/dict/{name}.txt.gz', 'rt', encoding='utf-8') if w.strip()}
words = sorted({w.strip() for w in open(sys.argv[1], encoding='utf-8')
                if re.fullmatch(r'[a-z]{3,}', w.strip())} - removed - others)
with gzip.GzipFile('assets/dict/words.txt.gz', 'wb', compresslevel=9, mtime=0) as f:
    f.write('\n'.join(words).encode())
print(len(words), 'words')
