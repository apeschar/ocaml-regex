let probes =
  [
    ("dollar-final-newline", "^x$", false, "x\n");
    ("ascii-word-boundary", {|\bwsidchk\b|}, false, "\255wsidchk\254");
    ("latin1-case-fold", "\195\137", true, "\195\169");
    ("latin1-single-byte-case-fold", "\192", true, "\224");
    ("unicode-word-boundary", {|\bwsidchk\b|}, false, "\195\169wsidchk");
    ("ascii-whitespace", {|x\s+y|}, false, "x\011y");
    ("non-ascii-whitespace", {|x\s+y|}, false, "x\160y");
  ]

let () =
  List.iter
    (fun (name, pattern, caseless, payload) ->
      let baseline =
        Re.execp
          (Re.Pcre.regexp
             ~flags:(if caseless then [ `CASELESS ] else [])
             pattern)
          payload
      in
      match
        try Ok (Rust_regex.compile ~caseless pattern)
        with Invalid_argument msg -> Error msg
      with
      | Ok re ->
          Printf.printf "%s\tRe=%b\tRust=%b\n" name baseline
            (Rust_regex.is_match re payload)
      | Error _ ->
          Printf.printf "%s\tRe=%b\tRust=unsupported-pattern\n" name baseline)
    probes
