# Standalone synthetic benchmark

The benchmark compares OCaml **Re**, native **PCRE** and Rust regex through the
OCaml binding using generic, generated inputs. It requires no external project,
website content or downloads. All patterns, inputs and generation code are
included or reproducible from this repository.

## Corpus

Run `python tools/generate-corpus.py` to generate 137 payloads (9,769,954 bytes)
with fixed seed 1729. Categories are synthetic HTML documents, multiline logs,
URL paths, numeric/alphanumeric tokens, headings and arbitrary byte strings.
Large documents have balanced hits/misses and early/middle/late match positions.
Small-input operations use their own categories, not large documents.

There are 13 generic regexes covering literal searches, case folding, word
boundaries, alternation, capture extraction, multiline anchors, numeric validation,
path parsing and NUL-containing byte patterns. Twelve are supported by both Re
and Rust regex. The atomic-group example deliberately uses unsupported Rust
syntax; its PCRE timing is reported without rewriting the pattern.

The tracked manifests record all patterns, flags, categories, hashes and sizes.
Generated payload bodies are ignored by Git and restored by the generator.
See [`corpus/README.md`](../corpus/README.md).

## Reproduce

In addition to the library's normal build tools, install `re` and `pcre` OCaml
packages and Python 3. From the repository root:

```sh
python tools/generate-corpus.py
mkdir -p results
dune exec --profile bench bench/bench.exe -- corpus > results/benchmark.tsv 2> results/unsupported.txt
dune exec --profile bench bench/bench.exe -- corpus captures > results/captures.tsv
dune exec --profile bench bench/semantics.exe > results/semantics.tsv
```

## Example results

Median time per complete **category** pass on AMD Ryzen 9 7950X3D, Linux 6.12.63,
OCaml 5.5.0, Re 1.14.0, ocaml-pcre 8.0.5, rustc 1.91.1, ocaml-rs 1.3.0 and
Rust regex 1.13.1. Rust release builds use LTO and one codegen unit.

| Operation | Baseline | Rust through FFI | Speedup |
|---|---:|---:|---:|
| Literal marker, 24 documents | 6.89 ms | 0.106 ms | 64.76× |
| Case-insensitive literal, 24 documents | 6.82 ms | 0.332 ms | 20.54× |
| Alternation, 24 documents | 6.80 ms | 0.555 ms | 12.26× |
| Attribute capture offsets, 24 documents | 11.35 ms | 0.112 ms | 101.51× |
| Multiline log capture offsets, 16 logs | 0.241 ms | 0.016 ms | 15.20× |
| Arbitrary-byte marker, 8 payloads | 0.278 ms | 0.005 ms | 53.29× |
| Path capture offsets, 71 paths | 5.01 µs | 20.15 µs | 0.25× |

Full results: [`results/benchmark.tsv`](../results/benchmark.tsv) and
[`results/captures.tsv`](../results/captures.tsv). Every supported pattern agreed
on boolean results and first-match capture offsets for its category. Positive
and negative inputs are present for every timed pattern.

## Methodology and limitations

- Compile regexes and load files outside timing. Check result equivalence first,
  including capture ranges in boolean runs.
- Warm up both engines. Target at least 100 ms per sample using full category
  passes; collect five samples and report the median per-pass time. Full OCaml
  major GC occurs before each sample.
- Each Rust search crosses the FFI individually and borrows the input without
  copying. Capture mode materializes offset arrays on both sides.
- Engine order is baseline then Rust. CPU is not pinned. Wall clock is
  `Unix.gettimeofday`, so scheduling and frequency changes affect measurements.
- Allocation columns count OCaml allocations and small harness overhead, not
  Rust heap allocations or engine caches.
- The corpus is intentionally synthetic, with repetitive document padding and
  a small pattern set. Cache effects, data distributions and early matches can
  substantially change results. These numbers are **not a universal performance
  ranking or an application-level speed prediction**.
- On this corpus Rust is much faster for large scans, while Re is faster for
  tiny anchored strings and paths. Always benchmark your own data.
- Fixture agreement does not imply universal semantic equivalence. Re uses
  Latin-1 word/case semantics in some cases; byte-mode Rust uses ASCII classes.
  The independent probes in [`results/semantics.tsv`](../results/semantics.tsv)
  make these differences explicit. Backreferences, look-around, atomic groups
  and possessive quantifiers are unsupported by Rust regex.
