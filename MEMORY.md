# Native-memory accounting

Compiled regexes, sets and capture locations report conservative external-memory
estimates to OCaml using `caml_alloc_custom_mem`. No periodic GC or allocator
trimming is installed. The abstract OCaml API and high-level matching engine are
unchanged; Cargo.lock retains the existing upstream versions.

## Estimates and ownership

The high-level regex crate hides its meta engine. Construction therefore makes
an additional, temporary meta compilation with the same syntax/build options,
using its public `memory_usage()` and cache-memory APIs. A strategy/metadata
margin is included. This costs an additional construction pass, not a second
matching pass. If estimation fails, a conservative configured-limit fallback
preserves the original builder's acceptance/error contract.

Each handle reserves fixed scratch plus forward/reverse lazy-DFA cache capacity.
Cache-free literal strategies need no lazy-cache reserve. Native atomic counters
track peak concurrent searches. Additional OCaml charge tokens reserve scratch
for extra concurrent users, including the pool's owner-thread optimization.
The OCaml ledger uses CAS so concurrent updates cannot lose persistent charges.
Reservations are estimates, not an exact allocator census, and can substantially
overestimate unused DFA capacity. They intentionally need not decrease as an
idle cache shrinks.

Clones charge their own scratch reserve but not the shared program again. Their
OCaml ownership metadata retains the first charged native wrapper and its cache
ledger. Thus the original cache pool can survive with its clones, but the shared
program is counted once per clone family. Captures and capture-location buffers
retain this ownership metadata too, including when the original public regex
wrapper is collected. Capture-location vectors have their own external charge.
All wrappers/tokens become collectible when their final views disappear.

## Validation

Rust tests cover sharing estimates and monotonic concurrency reserves. Existing
native/bytecode semantic tests and multi-domain stress tests pass. Added tests
cover clone chains, escaped captures/expansion, capture-location reuse through
clones, set clones, and automatic GC under repeated Unicode regex/set compilation.

Local diagnostic: 150 discarded UTF-8 `\\w{10}` compilations, OCaml 5.5,
`s=4M,o=120`. Before: RSS 4.4 -> 93.0 MiB, no intervening major collection.
After: RSS stayed around 9–10 MiB, major collections rose from 6 to 56.
Full GC reduced RSS to 8.4 MiB; diagnostic-only glibc trimming reduced it to
5.2 MiB. These are offline measurements, not proof that production OOMs are
resolved. Allocator retention and legitimately live native working sets remain.
