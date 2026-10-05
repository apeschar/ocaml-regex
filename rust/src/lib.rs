use ocaml::{CamlError, Error, ToValue};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex,
};

mod memory;
use memory::{accounted, estimate, Budget};

type Range = (ocaml::Int, ocaml::Int);
type Groups = Vec<Option<Range>>;
fn invalid(message: &'static str) -> Error {
    CamlError::InvalidArgument(message).into()
}
fn utf8(bytes: &[u8]) -> Result<&str, Error> {
    std::str::from_utf8(bytes).map_err(|_| invalid("Rust_regex: invalid UTF-8"))
}
fn position(start: ocaml::Int, len: usize) -> Result<usize, Error> {
    if start < 0 || start as usize > len {
        Err(invalid("Rust_regex: position out of bounds"))
    } else {
        Ok(start as usize)
    }
}

#[derive(ocaml::FromValue)]
pub struct Options {
    caseless: bool,
    multiline: bool,
    dotall: bool,
    unicode: bool,
    crlf: bool,
    line_terminator: ocaml::Int,
    swap_greed: bool,
    ignore_whitespace: bool,
    octal: bool,
    size_limit: ocaml::Int,
    dfa_size_limit: ocaml::Int,
    nest_limit: ocaml::Int,
}
impl Options {
    fn validate(&self) -> Result<(), String> {
        if !(0..=255).contains(&self.line_terminator)
            || self.size_limit < 0
            || self.dfa_size_limit < 0
            || self.nest_limit < 0
            || self.nest_limit as u64 > u32::MAX as u64
        {
            Err("Rust_regex: invalid builder limit or line terminator".into())
        } else {
            Ok(())
        }
    }
}
macro_rules! configure {
    ($b:expr, $o:expr) => {
        $b.case_insensitive($o.caseless)
            .multi_line($o.multiline)
            .dot_matches_new_line($o.dotall)
            .unicode($o.unicode)
            .crlf($o.crlf)
            .line_terminator($o.line_terminator as u8)
            .swap_greed($o.swap_greed)
            .ignore_whitespace($o.ignore_whitespace)
            .octal($o.octal)
            .size_limit($o.size_limit as usize)
            .dfa_size_limit($o.dfa_size_limit as usize)
            .nest_limit($o.nest_limit as u32)
    };
}

#[derive(Clone)]
enum Engine {
    Bytes(regex::bytes::Regex),
    Utf8(regex::Regex),
}
pub struct Compiled {
    engine: Engine,
    id: u64,
    budget: Budget,
}
ocaml::custom!(Compiled);
static NEXT_ID: AtomicU64 = AtomicU64::new(1);
// Both arms produce owned results before ocaml-rs allocates any OCaml values.
macro_rules! search {
    ($r:expr, $h:expr, |$re:ident, $hay:ident| $body:expr) => {{
        let _memory_guard = $r.budget.enter();
        match &$r.engine {
            Engine::Bytes($re) => {
                let $hay = $h;
                $body
            }
            Engine::Utf8($re) => {
                let $hay = utf8($h)?;
                $body
            }
        }
    }};
}
macro_rules! metadata {
    ($r:expr, |$re:ident| $body:expr) => {
        match &$r.engine {
            Engine::Bytes($re) => $body,
            Engine::Utf8($re) => $body,
        }
    };
}

#[ocaml::func]
pub fn rust_regex_build(
    pattern: &[u8],
    options: Options,
    text: bool,
) -> Result<ocaml::Pointer<Compiled>, String> {
    options.validate()?;
    let pattern = std::str::from_utf8(pattern).map_err(|e| e.to_string())?;
    let engine = if text {
        Engine::Utf8(
            configure!(regex::RegexBuilder::new(pattern), options)
                .build()
                .map_err(|e| e.to_string())?,
        )
    } else {
        Engine::Bytes(
            configure!(regex::bytes::RegexBuilder::new(pattern), options)
                .build()
                .map_err(|e| e.to_string())?,
        )
    };
    let budget = estimate(&[pattern], &options, text, false);
    let bytes = budget.initial(false);
    Ok(accounted(
        Compiled {
            engine,
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            budget,
        },
        bytes,
    ))
}
#[ocaml::func]
pub fn rust_regex_clone(re: &Compiled) -> ocaml::Pointer<Compiled> {
    let budget = re.budget.cloned();
    let bytes = budget.initial(true);
    accounted(
        Compiled {
            engine: re.engine.clone(),
            id: re.id,
            budget,
        },
        bytes,
    )
}
#[ocaml::func]
pub fn rust_regex_cache_extra(re: &Compiled) -> ocaml::Int {
    re.budget.extra() as ocaml::Int
}

#[ocaml::func]
pub fn rust_regex_pattern(re: &Compiled) -> String {
    metadata!(re, |r| r.as_str().to_owned())
}
#[ocaml::func]
pub fn rust_regex_capture_names(re: &Compiled) -> Vec<Option<String>> {
    metadata!(re, |r| r
        .capture_names()
        .map(|s| s.map(str::to_owned))
        .collect())
}
#[ocaml::func]
pub fn rust_regex_static_captures_len(re: &Compiled) -> Option<ocaml::Int> {
    metadata!(re, |r| r.static_captures_len().map(|n| n as ocaml::Int))
}
#[ocaml::func]
pub fn rust_regex_is_match(
    re: &Compiled,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<bool, Error> {
    let start = position(start, payload.len())?;
    Ok(search!(re, payload, |r, h| r.is_match_at(h, start)))
}
#[ocaml::func]
pub fn rust_regex_find(
    re: &Compiled,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<Option<Range>, Error> {
    let start = position(start, payload.len())?;
    Ok(search!(re, payload, |r, h| r
        .find_at(h, start)
        .map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int))))
}
#[ocaml::func]
pub fn rust_regex_shortest_match(
    re: &Compiled,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<Option<ocaml::Int>, Error> {
    let start = position(start, payload.len())?;
    Ok(search!(re, payload, |r, h| r
        .shortest_match_at(h, start)
        .map(|n| n as ocaml::Int)))
}
#[ocaml::func]
pub fn rust_regex_captures(
    re: &Compiled,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<Option<Groups>, Error> {
    let start = position(start, payload.len())?;
    Ok(search!(re, payload, |r, h| r.captures_at(h, start).map(
        |c| c
            .iter()
            .map(|m| m.map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int)))
            .collect()
    )))
}
#[ocaml::func]
pub fn rust_regex_find_all(re: &Compiled, payload: &[u8]) -> Result<Vec<Range>, Error> {
    Ok(search!(re, payload, |r, h| r
        .find_iter(h)
        .map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int))
        .collect()))
}
#[ocaml::func]
pub fn rust_regex_captures_all(re: &Compiled, payload: &[u8]) -> Result<Vec<Groups>, Error> {
    Ok(search!(re, payload, |r, h| r
        .captures_iter(h)
        .map(|c| c
            .iter()
            .map(|m| m.map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int)))
            .collect())
        .collect()))
}

// Vec<u8> normally converts to an OCaml int array; outputs here must be byte strings.
pub struct ByteString(Vec<u8>);
unsafe impl ToValue for ByteString {
    fn to_value(&self, _rt: &ocaml::Runtime) -> ocaml::Value {
        unsafe { ocaml::Value::bytes(&self.0) }
    }
}
#[ocaml::func]
pub fn rust_regex_split(
    re: &Compiled,
    payload: &[u8],
    limit: ocaml::Int,
) -> Result<Vec<ByteString>, Error> {
    if limit < 0 {
        return Err(invalid("Rust_regex: negative split limit"));
    }
    Ok(match &re.engine {
        Engine::Bytes(r) => r
            .splitn(payload, limit as usize)
            .map(|s| ByteString(s.to_vec()))
            .collect(),
        Engine::Utf8(r) => r
            .splitn(utf8(payload)?, limit as usize)
            .map(|s| ByteString(s.as_bytes().to_vec()))
            .collect(),
    })
}
#[ocaml::func]
pub fn rust_regex_replace(
    re: &Compiled,
    payload: &[u8],
    replacement: &[u8],
    limit: ocaml::Int,
    literal: bool,
) -> Result<ByteString, Error> {
    if limit < 0 {
        return Err(invalid("Rust_regex: negative replacement limit"));
    }
    let bytes = match &re.engine {
        Engine::Bytes(r) => {
            if literal {
                r.replacen(payload, limit as usize, regex::bytes::NoExpand(replacement))
                    .into_owned()
            } else {
                r.replacen(payload, limit as usize, replacement)
                    .into_owned()
            }
        }
        Engine::Utf8(r) => {
            let h = utf8(payload)?;
            let replacement = utf8(replacement)?;
            (if literal {
                r.replacen(h, limit as usize, regex::NoExpand(replacement))
                    .into_owned()
            } else {
                r.replacen(h, limit as usize, replacement).into_owned()
            })
            .into_bytes()
        }
    };
    Ok(ByteString(bytes))
}
#[ocaml::func]
pub fn rust_regex_expand(
    re: &Compiled,
    payload: &[u8],
    start: ocaml::Int,
    replacement: &[u8],
) -> Result<Option<ByteString>, Error> {
    let start = position(start, payload.len())?;
    Ok(match &re.engine {
        Engine::Bytes(r) => r.captures_at(payload, start).map(|c| {
            let mut dst = Vec::new();
            c.expand(replacement, &mut dst);
            ByteString(dst)
        }),
        Engine::Utf8(r) => {
            let h = utf8(payload)?;
            let replacement = utf8(replacement)?;
            r.captures_at(h, start).map(|c| {
                let mut dst = String::new();
                c.expand(replacement, &mut dst);
                ByteString(dst.into_bytes())
            })
        }
    })
}
#[ocaml::func]
pub fn rust_regex_validate_utf8(payload: &[u8]) -> Result<(), Error> {
    utf8(payload)?;
    Ok(())
}

#[ocaml::func]
pub fn rust_regex_escape(pattern: &[u8]) -> Result<String, Error> {
    Ok(regex::escape(utf8(pattern)?))
}

// Reusable locations are mutable, so serialize access across OCaml domains.
enum Locations {
    Bytes(regex::bytes::CaptureLocations),
    Utf8(regex::CaptureLocations),
}
pub struct CaptureLocations {
    locations: Mutex<Locations>,
    id: u64,
}
ocaml::custom!(CaptureLocations);
#[ocaml::func]
pub fn rust_regex_locations(re: &Compiled) -> ocaml::Pointer<CaptureLocations> {
    let locations = match &re.engine {
        Engine::Bytes(r) => Locations::Bytes(r.capture_locations()),
        Engine::Utf8(r) => Locations::Utf8(r.capture_locations()),
    };
    let len = match &locations {
        Locations::Bytes(l) => l.len(),
        Locations::Utf8(l) => l.len(),
    };
    let bytes = len
        .saturating_mul(4 * std::mem::size_of::<usize>())
        .saturating_add(128);
    accounted(
        CaptureLocations {
            locations: Mutex::new(locations),
            id: re.id,
        },
        bytes,
    )
}
#[ocaml::func]
pub fn rust_regex_locations_len(loc: &CaptureLocations) -> ocaml::Int {
    let guard = loc.locations.lock().unwrap_or_else(|e| e.into_inner());
    match &*guard {
        Locations::Bytes(l) => l.len() as ocaml::Int,
        Locations::Utf8(l) => l.len() as ocaml::Int,
    }
}
#[ocaml::func]
pub fn rust_regex_locations_index(loc: &CaptureLocations, index: ocaml::Int) -> Option<Range> {
    if index < 0 {
        return None;
    }
    let guard = loc.locations.lock().unwrap_or_else(|e| e.into_inner());
    let result = match &*guard {
        Locations::Bytes(l) => l.get(index as usize),
        Locations::Utf8(l) => l.get(index as usize),
    };
    result.map(|(a, b)| (a as ocaml::Int, b as ocaml::Int))
}
#[ocaml::func]
pub fn rust_regex_locations_get(loc: &CaptureLocations) -> Groups {
    let guard = loc.locations.lock().unwrap_or_else(|e| e.into_inner());
    match &*guard {
        Locations::Bytes(l) => (0..l.len())
            .map(|i| l.get(i).map(|(a, b)| (a as ocaml::Int, b as ocaml::Int)))
            .collect(),
        Locations::Utf8(l) => (0..l.len())
            .map(|i| l.get(i).map(|(a, b)| (a as ocaml::Int, b as ocaml::Int)))
            .collect(),
    }
}
#[ocaml::func]
pub fn rust_regex_captures_read(
    re: &Compiled,
    loc: &CaptureLocations,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<Option<Range>, Error> {
    if re.id != loc.id {
        return Err(invalid("Rust_regex: locations belong to another regex"));
    }
    let start = position(start, payload.len())?;
    let mut guard = loc.locations.lock().unwrap_or_else(|e| e.into_inner());
    let _memory_guard = re.budget.enter();
    let range = match (&re.engine, &mut *guard) {
        (Engine::Bytes(r), Locations::Bytes(l)) => r
            .captures_read_at(l, payload, start)
            .map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int)),
        (Engine::Utf8(r), Locations::Utf8(l)) => r
            .captures_read_at(l, utf8(payload)?, start)
            .map(|m| (m.start() as ocaml::Int, m.end() as ocaml::Int)),
        _ => return Err(invalid("Rust_regex: incompatible locations")),
    };
    Ok(range)
}

#[derive(Clone)]
enum SetEngine {
    Bytes(regex::bytes::RegexSet),
    Utf8(regex::RegexSet),
}
pub struct Set {
    engine: SetEngine,
    budget: Budget,
}
ocaml::custom!(Set);
#[ocaml::func]
pub fn rust_regex_set_build(
    patterns: Vec<ByteStringInput>,
    options: Options,
    text: bool,
) -> Result<ocaml::Pointer<Set>, String> {
    options.validate()?;
    let patterns: Vec<&str> = patterns
        .iter()
        .map(|s| std::str::from_utf8(&s.0))
        .collect::<Result<_, _>>()
        .map_err(|e| e.to_string())?;
    let engine = if text {
        SetEngine::Utf8(
            configure!(regex::RegexSetBuilder::new(&patterns), options)
                .build()
                .map_err(|e| e.to_string())?,
        )
    } else {
        SetEngine::Bytes(
            configure!(regex::bytes::RegexSetBuilder::new(&patterns), options)
                .build()
                .map_err(|e| e.to_string())?,
        )
    };
    let budget = estimate(&patterns, &options, text, true);
    let bytes = budget.initial(false);
    Ok(accounted(Set { engine, budget }, bytes))
}
// Own pattern bytes when converting an OCaml array, including invalid UTF-8.
pub struct ByteStringInput(Vec<u8>);
unsafe impl ocaml::FromValue for ByteStringInput {
    fn from_value(value: ocaml::Value) -> Self {
        Self(<&[u8]>::from_value(value).to_vec())
    }
}
#[ocaml::func]
pub fn rust_regex_set_clone(set: &Set) -> ocaml::Pointer<Set> {
    let budget = set.budget.cloned();
    let bytes = budget.initial(true);
    accounted(
        Set {
            engine: set.engine.clone(),
            budget,
        },
        bytes,
    )
}
#[ocaml::func]
pub fn rust_regex_set_cache_extra(set: &Set) -> ocaml::Int {
    set.budget.extra() as ocaml::Int
}
#[ocaml::func]
pub fn rust_regex_set_patterns(set: &Set) -> Vec<String> {
    match &set.engine {
        SetEngine::Bytes(s) => s.patterns().to_vec(),
        SetEngine::Utf8(s) => s.patterns().to_vec(),
    }
}
#[ocaml::func]
pub fn rust_regex_set_is_match(
    set: &Set,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<bool, Error> {
    let start = position(start, payload.len())?;
    let _memory_guard = set.budget.enter();
    Ok(match &set.engine {
        SetEngine::Bytes(s) => s.is_match_at(payload, start),
        SetEngine::Utf8(s) => s.is_match_at(utf8(payload)?, start),
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handles_are_send_and_sync() {
        fn check<T: Send + Sync>() {}
        check::<Compiled>();
        check::<Set>();
        check::<CaptureLocations>();
    }
    #[test]
    fn byte_mode_and_empty_iteration() {
        let re = regex::bytes::RegexBuilder::new(r"\bwsidchk\b")
            .unicode(false)
            .build()
            .unwrap();
        assert!(re.is_match(b"\xffwsidchk\xfe"));
        let bytes = regex::bytes::RegexBuilder::new("")
            .unicode(false)
            .build()
            .unwrap();
        assert_eq!(bytes.find_iter("é".as_bytes()).count(), 3);
        assert_eq!(regex::Regex::new("").unwrap().find_iter("é").count(), 2);
    }
}

#[ocaml::func]
pub fn rust_regex_set_matches(
    set: &Set,
    payload: &[u8],
    start: ocaml::Int,
) -> Result<Vec<ocaml::Int>, Error> {
    let start = position(start, payload.len())?;
    let _memory_guard = set.budget.enter();
    Ok(match &set.engine {
        SetEngine::Bytes(s) => s
            .matches_at(payload, start)
            .iter()
            .map(|n| n as ocaml::Int)
            .collect(),
        SetEngine::Utf8(s) => s
            .matches_at(utf8(payload)?, start)
            .iter()
            .map(|n| n as ocaml::Int)
            .collect(),
    })
}
