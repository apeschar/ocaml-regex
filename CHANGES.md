# 0.1.0 (unreleased)

- Complete high-level bindings for Rust Regex/RegexSet and their byte-string equivalents.
- All builder options, positional searches, named/optional captures, match iteration,
  split and replacements (including literal and OCaml callback replacements).
- Reusable capture locations, regex sets and metadata/introspection.
- Explicit Bytes/Utf8 APIs with validated UTF-8 patterns and text inputs.
- Offline vendored Cargo builds, Dune installation, native and bytecode support.
- Functional, GC/compaction, cross-domain and installed-consumer tests.

The original benchmark prototype's `captures` offset arrays are now available as
`captures_offsets`. `captures` returns a `Captures.t` snapshot with named groups,
expansion, extraction and source substring access.
