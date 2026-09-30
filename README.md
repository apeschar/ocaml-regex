# rust-regex

OCaml bindings to Rust's [`regex`](https://docs.rs/regex/) crate, using
[`ocaml-rs`](https://github.com/zshipko/ocaml-rs). Package and findlib name:
**`rust-regex`**. OCaml module: **`Rust_regex`**. MIT licensed.

## Build / install

Requires OCaml **4.14+**, Dune **3.11+**, Rust/Cargo **1.83+**, and a C toolchain.
The source distribution includes all Cargo dependencies in a deterministic
vendor archive. Dune builds with `--locked --offline`; no Cargo downloads occur
during installation. Native and bytecode libraries are installed.

```sh
opam install . --with-test     # from this checkout; not yet published on opam
# Or without installing:
make build
make test
make lint
tools/check-install           # temporary install + consumers; needs ocamlfind
```

No OCaml runtime dependencies beyond the standard library. Linux is validated;
macOS link flags/library naming are included but not yet validated. Windows is
not currently supported.

## Usage

```ocaml
let re = Rust_regex.compile {|(?<word>[a-z]+)|}
let () =
  assert (Rust_regex.is_match re "hello");
  let caps = Option.get (Rust_regex.captures re "hello") in
  assert (Rust_regex.Captures.expand caps "${word}!" = "hello!");
  assert (Rust_regex.replace_all re "hello world" "[$word]" = "[hello] [world]")
```

The top-level API aliases `Rust_regex.Bytes`: arbitrary byte strings, ASCII
classes and ASCII case folding by default. Use `Rust_regex.Utf8` for validated
UTF-8 inputs and Unicode classes/case folding:

```ocaml
let re = Rust_regex.Utf8.compile {|\p{Greek}+|}
let () = assert (Rust_regex.Utf8.is_match re "Ελληνικά")
```

Both modes accept only UTF-8 **patterns**; use regex `\xNN` escapes for arbitrary
pattern bytes. Byte mode can opt into Unicode with `~unicode:true`; unlike UTF-8
mode, it still accepts non-UTF-8 haystacks. UTF-8 mode can disable Unicode only
where Rust's text regex guarantees matches remain valid UTF-8.

Immutable builders expose all Rust builder options:

```ocaml
let re =
  let module B = Rust_regex.Builder in
  B.create "^hello$"
  |> fun b -> B.case_insensitive b true
  |> fun b -> B.multi_line b true
  |> B.build_exn
```

A regex set searches many patterns at once:

```ocaml
let detectors = Rust_regex.Set.compile [|"_cf_chl_opt"; "wsidchk"; "anubis_challenge"|]
let detect html =
  Rust_regex.Set.matches detectors html |> Rust_regex.Set_matches.indices
```

## API coverage

See [`lib/rust_regex.mli`](lib/rust_regex.mli) for complete signatures/contracts.
Both `Bytes` and `Utf8` implement the same `S` interface:

- Regex and RegexSet construction, fallible compilation, cloning and metadata.
- All builder flags and size/DFA/nesting limits, including CRLF and custom line terminators.
- Boolean, first-match, shortest-match and capture searches, including `_at` variants.
- Match ranges, source substrings, named/optional captures, expansion and static extraction.
- All-match and all-capture iteration, preserving Rust's empty-match behavior.
- Split/splitn; first/all/limited replacements; literal (`NoExpand`) replacements;
  OCaml capture callbacks.
- Reusable capture locations with `captures_read`/`captures_read_at`.
- Set matches, ascending indices, membership/all/any predicates and reusable boolean arrays.

Rust lifetimes, const generics and replacer traits are represented by owned OCaml
snapshots, checked extraction counts and OCaml functions. Deprecated Rust aliases
are not duplicated. `find_iter`/`captures_iter` return repeatable **eager snapshot**
sequences, not streaming Rust iterators; `find_all`/`captures_all` expose arrays.
Split results are arrays. Locations' `offsets` returns a coherent snapshot;
individual read/get calls on shared locations are not an atomic transaction.

## Semantics / safety

- All ranges use **byte offsets**, with an exclusive end, even in UTF-8 mode.
- `_at` searches keep full-input boundary/anchor context. Positions must be
  between zero and the input byte length, inclusive.
- Missing optional groups are `None`; unknown captures return `None`.
- `splitn` with zero returns no fields; `replacen` with zero replaces all matches.
- Replacement interpolation is Rust's `$name`, `${name}`, `$1`, `$$` syntax.
  Callback outputs are literal and are UTF-8-validated in UTF-8 mode.
- Invalid input/arguments raise `Invalid_argument`. Builders and `compile_result`
  return detailed errors; `compile` and `build_exn` raise them.
- Regex/set handles can be shared across domains; mutable Rust capture locations
  are mutex-protected. Caller-owned OCaml boolean arrays require caller synchronization.
- Search borrows the OCaml input without copying and keeps the runtime lock.
  Results are owned before any OCaml allocation; captures retain their input.
  Compiled Rust handles are GC-finalized, not serializable or structurally comparable.
- Backreferences, look-around, atomic groups and possessive quantifiers are unsupported.
  Byte-mode ASCII classes **differ from Re's Latin-1 semantics**; verify character
  classes and case folding when migrating between engines.

## Development / release

`tools/vendor` refreshes the deterministic vendor archive after deliberate
Cargo.lock changes (GNU tar is needed for regeneration, not ordinary builds).
The archive preserves hidden upstream files required by Cargo checksums, which
Dune's directory traversal otherwise omits. Third-party source/license files
are retained unchanged inside it. `rust/vendor/` is only a local unpacked cache.

```sh
(cd rust && cargo fmt --check)
make test
make lint
tools/check-install
# Optional synthetic benchmark; requires additional re/pcre packages:
python tools/generate-corpus.py
dune exec --profile bench bench/bench.exe -- corpus
```

Validation: native + bytecode tests on Linux with OCaml **4.14.4, 5.4.1, 5.5.0**;
shared-domain stress tests on both OCaml 5 compilers. See
[`RELEASING.md`](RELEASING.md) for source-archive/offline/release checks. Publishing,
tagging and final release URLs are intentionally separate steps. Source is hosted
at [apeschar/ocaml-regex](https://github.com/apeschar/ocaml-regex).
The standalone synthetic corpus and benchmark methodology are documented in
[`doc/benchmark.md`](doc/benchmark.md). No external fixtures or downloads are required.
