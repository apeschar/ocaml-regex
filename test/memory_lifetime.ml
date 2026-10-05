let collect () = Gc.full_major (); Gc.full_major ()
let check label expected actual =
  if expected <> actual then failwith label

let clone_lifetime () =
  let clone = let original = Rust_regex.Utf8.compile "(?P<word>\\w+)" in
    Rust_regex.Utf8.clone (Rust_regex.Utf8.clone original) in
  collect ();
  let caps = Option.get (Rust_regex.Utf8.captures clone "hello") in
  check "clone after original GC" "hello" (Rust_regex.Match.as_string (Rust_regex.Captures.get_match caps));
  check "clone captures expand" "hello!" (Rust_regex.Captures.expand caps "$word!")

let captures_lifetime () =
  let caps =
    let original = Rust_regex.Bytes.compile "(?P<word>[a-z]+)" in
    let clone = Rust_regex.Bytes.clone original in
    Option.get (Rust_regex.Bytes.captures clone "hello") in
  collect ();
  check "captures preserve charged program" "hello!" (Rust_regex.Captures.expand caps "$word!")

let locations_lifetime () =
  let clone, locations =
    let original = Rust_regex.Bytes.compile "(a+)(b+)" in
    (Rust_regex.Bytes.clone original, Rust_regex.Bytes.capture_locations original) in
  collect ();
  ignore (Rust_regex.Bytes.captures_read clone locations "aaabbb");
  check "location after original GC" (Some (0,3))
    (Rust_regex.Bytes.Capture_locations.get locations 1)

let set_lifetime () =
  let clone = let original = Rust_regex.Bytes.Set.compile [|"a+";"b+"|] in
    Rust_regex.Bytes.Set.clone (Rust_regex.Bytes.Set.clone original) in
  collect ();
  check "set clone after original GC" true (Rust_regex.Bytes.Set.is_match clone "bbb")

let pressure compile () =
  collect ();
  let before = Gc.quick_stat () in
  for _ = 1 to 150 do ignore (Sys.opaque_identity (compile ())) done;
  let after = Gc.quick_stat () in
  check "native compilation triggers GC" true
    (after.major_collections > before.major_collections);
  collect ()

let () = List.iter (fun (name, test) -> test (); Printf.printf "ok: %s\n%!" name)
  [ "clones", clone_lifetime;
    "escaped captures", captures_lifetime;
    "capture locations", locations_lifetime;
    "set clones", set_lifetime;
    "Unicode regex pressure", pressure (fun () -> Rust_regex.Utf8.compile "\\w{10}");
    "Unicode set pressure", pressure (fun () -> Rust_regex.Utf8.Set.compile [|"\\w{10}";"\\d{10}"|]) ]
