.PHONY: build test bench clean vendor lint
build:
	dune build -p rust-regex

test:
	dune runtest -p rust-regex --force

bench:
	dune exec --profile bench bench/bench.exe -- corpus

vendor:
	tools/vendor

lint:
	opam lint rust-regex.opam
	cd rust && cargo fmt --check

clean:
	dune clean
