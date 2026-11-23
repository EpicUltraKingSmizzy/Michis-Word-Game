"""Builds assets/dict/words.txt.gz from a SCOWL word list.

Usage: python3 tool/build_dictionary.py path/to/scowl70_us_gb.txt

The input is SCOWL size 70, American + British (one word per line). Only
lowercase a-z words of 3+ letters are kept. The slur blocklist is NOT applied
here; it lives in assets/dict/blocklist.txt and is applied when the game loads.
"""
import gzip, re, sys
words = sorted({w.strip() for w in open(sys.argv[1], encoding='utf-8')
                if re.fullmatch(r'[a-z]{3,}', w.strip())})
with gzip.GzipFile('assets/dict/words.txt.gz', 'wb', compresslevel=9, mtime=0) as f:
    f.write('\n'.join(words).encode())
print(len(words), 'words')
