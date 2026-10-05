//! GC pressure estimates, deliberately separate from the matching engine.
//! Mirror upstream's public builder configuration to inspect the meta engine's
//! memory_usage without replacing high-level regex APIs or their semantics.
use crate::Options;
use ocaml::{Custom, FromValue, Pointer};
use regex_automata::{meta, nfa::thompson::WhichCaptures, util::syntax, MatchKind};
use std::sync::atomic::{AtomicUsize, Ordering};

pub(super) fn accounted<T: Custom>(value: T, bytes: usize) -> Pointer<T> {
    unsafe {
        let raw = ocaml::sys::caml_alloc_custom_mem(
            T::ops() as *const _ as *mut ocaml::sys::custom_operations,
            std::mem::size_of::<T>(),
            bytes,
        );
        let mut result = Pointer::<T>::from_value(ocaml::Value::new(raw));
        result.set(value);
        result
    }
}

pub struct CacheCharge;
ocaml::custom!(CacheCharge);

pub(super) struct Budget {
    pub program: usize,
    pub cache: usize,
    active: AtomicUsize,
    peak: AtomicUsize,
}
impl Budget {
    fn new(program: usize, cache: usize) -> Self {
        Self {
            program,
            cache,
            active: AtomicUsize::new(0),
            peak: AtomicUsize::new(0),
        }
    }
    pub fn cloned(&self) -> Self {
        Self::new(self.program, self.cache)
    }
    pub fn initial(&self, shared_program: bool) -> usize {
        let program = if shared_program { 0 } else { self.program };
        // The pool has an owner-thread fast path plus the general scratch pool.
        program.saturating_add(self.cache.saturating_mul(2))
    }
    pub fn enter(&self) -> Guard<'_> {
        let count = self.active.fetch_add(1, Ordering::Relaxed) + 1;
        self.peak.fetch_max(count, Ordering::Relaxed);
        Guard(self)
    }
    pub fn extra(&self) -> usize {
        self.cache
            .saturating_mul(self.peak.load(Ordering::Relaxed).saturating_sub(1))
            .min((isize::MAX as usize) >> 1)
    }
}
pub(super) struct Guard<'a>(&'a Budget);
impl Drop for Guard<'_> {
    fn drop(&mut self) {
        self.0.active.fetch_sub(1, Ordering::Relaxed);
    }
}

pub(super) fn estimate(patterns: &[&str], options: &Options, text: bool, set: bool) -> Budget {
    let syntax = syntax::Config::new()
        .utf8(text)
        .case_insensitive(options.caseless)
        .multi_line(options.multiline)
        .dot_matches_new_line(options.dotall)
        .unicode(options.unicode)
        .crlf(options.crlf)
        .line_terminator(options.line_terminator as u8)
        .swap_greed(options.swap_greed)
        .ignore_whitespace(options.ignore_whitespace)
        .octal(options.octal)
        .nest_limit(options.nest_limit as u32);
    let mut config = meta::Config::new()
        .utf8_empty(text)
        .match_kind(if set {
            MatchKind::All
        } else {
            MatchKind::LeftmostFirst
        })
        .nfa_size_limit(Some(options.size_limit as usize))
        .hybrid_cache_capacity(options.dfa_size_limit as usize);
    if set {
        config = config.which_captures(WhichCaptures::None);
    }
    let pattern_bytes = patterns
        .iter()
        .map(|s| s.len())
        .fold(0usize, usize::saturating_add);
    match meta::Builder::new()
        .configure(config)
        .syntax(syntax)
        .build_many(patterns)
    {
        Ok(re) => {
            let initial_cache = re.create_cache().memory_usage();
            // memory_usage describes the strategy, not all metadata/allocator
            // overhead. Include a modest margin, source storage and headers.
            let program = re
                .memory_usage()
                .saturating_mul(2)
                .saturating_add(pattern_bytes.saturating_mul(2))
                .saturating_add(1024);
            // Include fixed VM scratch and a bounded forward/reverse lazy-DFA
            // reserve. No reserve is needed for cache-free literal strategies.
            let cache = if initial_cache == 0 {
                0
            } else {
                initial_cache
                    .saturating_mul(2)
                    .saturating_add((options.dfa_size_limit as usize).saturating_mul(2))
            };
            Budget::new(program, cache)
        }
        Err(_) => {
            // Never change acceptance/error contracts solely for accounting.
            Budget::new(
                (options.size_limit as usize)
                    .saturating_mul(4)
                    .saturating_add(pattern_bytes)
                    .saturating_add(1024),
                (options.dfa_size_limit as usize)
                    .saturating_mul(4)
                    .saturating_add(1024),
            )
        }
    }
}

#[ocaml::func]
pub fn rust_regex_memory_charge(bytes: ocaml::Int) -> Pointer<CacheCharge> {
    accounted(CacheCharge, bytes.max(0) as usize)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clones_do_not_charge_shared_program() {
        let b = Budget::new(1_000_000, 100);
        assert_eq!(b.initial(false), 1_000_200);
        assert_eq!(b.cloned().initial(true), 200);
    }
    #[test]
    fn concurrency_reserve_is_monotonic() {
        let b = Budget::new(1000, 100);
        let a = b.enter();
        let c = b.enter();
        assert_eq!(b.extra(), 100);
        drop(a);
        drop(c);
        assert_eq!(b.extra(), 100);
        let _next = b.enter();
        assert_eq!(b.extra(), 100);
    }
}
