# Release checklist

The package is prepared as `rust-regex.0.1.0`; it has **not** been published.
The homepage/dev-repo/issue URLs designate the GitHub repository
[`apeschar/ocaml-regex`](https://github.com/apeschar/ocaml-regex). Confirm that
this repository and its immutable release archive are publicly accessible
before submitting an opam release.

1. Review `CHANGES.md`, version fields in `dune-project`, `rust-regex.opam` and
   `rust/Cargo.toml`, and the Cargo.lock root-package version. Replace the
   unreleased heading with a release date when publishing.
2. If Rust dependencies changed, deliberately refresh the lockfile, run
   `tools/vendor`, and commit both lockfile and `rust/vendor.tar.gz`. All upstream
   license and checksum files are preserved in the archive. Do not edit vendor
   sources or remove files from their checksum manifests.
3. Run `make lint`, `make test`, and `tools/check-install`. Run native/bytecode
   tests with OCaml 4.14 and a current OCaml 5 compiler; on OCaml 5 also run the
   domain-sharing tests (part of `dune runtest`). Current validation covers
   4.14.4, 5.4.1 and 5.5.0 on x86_64 Linux. macOS needs independent validation.
   If native linking needs OCaml's PIC runtime, select it externally for the
   native build, not through Dune link flags. Some OCaml 4 distributions lack a
   PIC bytecode header; do not force that variant for the bytecode test build.
4. Commit the reviewed release tree. Produce a source archive from the commit:

   ```sh
   mkdir -p .release
   git archive --prefix=rust-regex-0.1.0/ HEAD | gzip -n > .release/rust-regex-0.1.0.tar.gz
   sha256sum .release/rust-regex-0.1.0.tar.gz
   sha512sum .release/rust-regex-0.1.0.tar.gz
   ```

5. Extract that archive in a fresh directory. Set `CARGO_HOME` to an empty
   temporary directory and run `dune build -p rust-regex`, `dune runtest -p
   rust-regex --force`, and `tools/check-install`. They must work without a
   prepopulated Cargo cache or the development corpus. Dune explicitly uses
   `--offline --locked`. No executable build products or fixture payloads should
   be included in the archive.
6. Push the reviewed release commit and tag only when release publication is
   approved. Host the immutable source archive on the corresponding GitHub
   release and verify the downloaded archive's checksum. Repository publication
   alone does not publish a release tag or an opam package.
7. In the opam-repository package directory `packages/rust-regex/rust-regex.0.1.0`,
   copy the package opam file and add the immutable source stanza:

   ```opam
   url {
     src: "https://CONFIRMED-RELEASE-URL/rust-regex-0.1.0.tar.gz"
     checksum: "sha256=ACTUAL-ARCHIVE-HASH"
   }
   ```

   Do not submit placeholder URLs or hashes. Run `opam lint` on that file and
   install it with `--with-test` in a clean opam switch before opening the opam
   repository PR. `opam publish` may automate submission after the source is
   publicly available. Rust/Cargo 1.83+ is required; `conf-rust-2021` provides the
   toolchain check, and the Cargo manifest enforces the minimum Rust version.
