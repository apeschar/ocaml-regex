# Synthetic benchmark corpus

Generate with `python tools/generate-corpus.py` from the repository root.
No external project, network access or downloaded fixtures are involved.
All generated content is covered by this repository's MIT license.

The generator uses seed 1729 and Python's standard library. It creates 137
payloads totaling 9,769,954 bytes, with these categories:

- 24 synthetic HTML documents at roughly 4 KiB, 64 KiB and 1 MiB; balanced
  positive/negative samples and early/middle/late matches.
- 16 synthetic multiline logs at roughly 4 KiB and 64 KiB.
- 71 generic URL paths, including case, locale, trailing-slash and negative cases.
- 11 short numeric/alphanumeric tokens.
- 7 short headings, including whitespace/case/negative cases.
- 8 arbitrary byte strings with NUL and invalid UTF-8; balanced marker hits/misses.

`patterns.tsv` contains generic patterns, engine selection, flags and category.
`payloads.tsv` maps category and sample name to a SHA-256 filename.
`manifest.json` records the seed, pattern definitions, payload hashes and sizes.
These manifests are tracked; generated payload bodies are ignored by Git.
Regeneration after cloning restores the complete corpus. Pattern categories keep
short-string operations separate from large-document scans.

Twelve patterns work in both Re and Rust regex. A thirteenth pattern uses an
atomic group and is intentionally PCRE-only, demonstrating unsupported syntax
without altering the expression. Benchmarks check boolean results and capture
ranges before timing. See `doc/benchmark.md` for limitations and results.
