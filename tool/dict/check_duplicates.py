"""Checks the bundled word lists for duplicates.

Usage: python3 tool/dict/check_duplicates.py   (run from the repo root)

Fails (exit code 1) if a word appears twice in one file, or in more than one
of the files below. Every word has to live in exactly one file so that
switching a list off (WordListOptions) removes exactly that list's words.
When a word fits more than one list, it goes in the most specific one:
profanity > slang > places > person_names > surnames > words (see DESIGN_QUESTIONS.md).
It also fails if a word in assets/dict/rejected_words.txt.gz (known
non-words) is in any of the word lists.
The same checks run in test/dictionary_test.dart, so CI enforces them.
"""
import collections, gzip, sys

FILES = [
    'assets/dict/words.txt.gz',
    'assets/dict/slang.txt.gz',
    'assets/dict/profanity.txt.gz',
    'assets/dict/places.txt.gz',
    'assets/dict/person_names.txt.gz',
    'assets/dict/surnames.txt.gz',
]

REJECTED = 'assets/dict/rejected_words.txt.gz'

def main():
    where = collections.defaultdict(list)
    problems = 0
    for path in FILES:
        words = [w.strip() for w in gzip.open(path, 'rt', encoding='utf-8') if w.strip()]
        counts = collections.Counter(words)
        for w, n in sorted(counts.items()):
            if n > 1:
                print(f'repeated {n}x in {path}: {w}')
                problems += 1
        for w in counts:
            where[w].append(path)
        print(f'{path}: {len(counts):,} words')
    for w, paths in sorted(where.items()):
        if len(paths) > 1:
            print(f'in more than one file: {w} -> {", ".join(paths)}')
            problems += 1
    # The rejected-words list (known non-words) must not overlap any word list.
    rejected = [w.strip() for w in gzip.open(REJECTED, 'rt', encoding='utf-8') if w.strip()]
    for w, n in sorted(collections.Counter(rejected).items()):
        if n > 1:
            print(f'repeated {n}x in {REJECTED}: {w}')
            problems += 1
    for w in sorted(set(rejected)):
        if w in where:
            print(f'rejected word is in the dictionary: {w} -> {", ".join(where[w])}')
            problems += 1
    print(f'{REJECTED}: {len(set(rejected)):,} words')
    print(f'{len(where):,} distinct words, {problems} duplicate problem(s)')
    return 1 if problems else 0

if __name__ == '__main__':
    sys.exit(main())
