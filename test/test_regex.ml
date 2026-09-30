open Rust_regex

let invalid f =
  try
    ignore (f ());
    failwith "expected Invalid_argument"
  with Invalid_argument _ -> ()

let error = function Error _ -> () | Ok _ -> failwith "expected Error"
let ranges xs = Array.map Match.range xs
let strings xs = Array.map Match.as_string xs
let get = Option.get

let () =
  error (compile_result "(");
  error (compile_result "\255");
  error (compile_result ~size_limit:(-1) "x");
  error (compile_result ~dfa_size_limit:(-1) "x");
  error (compile_result ~nest_limit:(-1) "x");
  error (compile_result ~nest_limit:0 "((x))");
  invalid (fun () -> compile "(?=x)");
  assert (escape "[a].*" = {|\[a\]\.\*|});
  invalid (fun () -> escape "\255");
  let re = compile ~caseless:true {|\bwsidchk\b|} in
  assert (is_match re "\255WSIDCHK\254");
  assert (not (is_match re "xwsidchk"));
  assert (is_match (clone re) "wsidchk");
  assert (as_str re = {|\bwsidchk\b|});
  assert (is_match (compile "a.b") "a\000b");
  assert (is_match (compile ~dotall:true "a.b") "a\nb");
  let b = Builder.create "x" in
  assert (not (is_match (Builder.build_exn b) "X"));
  assert (is_match (Builder.build_exn (Builder.case_insensitive b true)) "X");
  assert (
    is_match
      (Builder.build_exn (Builder.multi_line (Builder.create "^x$") true))
      "a\nx\ny");
  assert (
    is_match
      (Builder.build_exn
         (Builder.dot_matches_new_line (Builder.create "a.b") true))
      "a\nb");
  assert (
    is_match
      (Builder.build_exn (Builder.unicode (Builder.create {|\p{Greek}+|}) true))
      "α");
  assert (
    is_match
      (Builder.build_exn
         (Builder.crlf (Builder.multi_line (Builder.create "^x$") true) true))
      "x\r\n");
  assert (
    is_match
      (Builder.build_exn
         (Builder.line_terminator
            (Builder.multi_line (Builder.create "^x$") true)
            ';'))
      "a;x;b");
  assert (
    Match.as_string
      (get
         (find
            (Builder.build_exn (Builder.swap_greed (Builder.create "a+") true))
            "aaa"))
    = "a");
  assert (
    is_match
      (Builder.build_exn
         (Builder.ignore_whitespace (Builder.create "a # comment\n b") true))
      "ab");
  assert (
    is_match
      (Builder.build_exn (Builder.octal (Builder.create {|\141|}) true))
      "a");
  error (Builder.build (Builder.size_limit (Builder.create "(a|b|c)+") 0));
  assert (is_match (Builder.build_exn (Builder.dfa_size_limit b 0)) "x");
  error (Builder.build (Builder.nest_limit b (-1)));
  let re = compile "a+" in
  let m = get (find re "zaaa") in
  assert (
    Match.start m = 1
    && Match.end_ m = 4
    && Match.length m = 3
    && not (Match.is_empty m));
  assert (find re "z" = None);
  assert (shortest_match re "zaaa" = Some 2);
  assert (shortest_match_at re "zaaa" 3 = Some 4);
  assert (Match.range (get (find_at re "zaaa" 3)) = (3, 4));
  assert (not (is_match_at (compile "^a") "ba" 1));
  assert (not (is_match_at (compile {|\ba|}) "ba" 1));
  assert (is_match_at (compile "$") "abc" 3);
  invalid (fun () -> is_match_at re "a" (-1));
  invalid (fun () -> find_at re "a" 2);
  invalid (fun () -> captures_at re "a" 2);
  invalid (fun () -> shortest_match_at re "a" 2);
  assert (ranges (find_all (compile "") "ab") = [| (0, 0); (1, 1); (2, 2) |]);
  assert (strings (Array.of_seq (find_iter re "aaa aa")) = [| "aaa"; "aa" |]);
  let re = compile {|(?<first>a)(b)?|} in
  assert (captures_len re = 3);
  assert (capture_names re = [| None; Some "first"; None |]);
  assert (static_captures_len re = None);
  let c = get (captures re "za") in
  assert (Captures.len c = 3);
  assert (Captures.offsets c = [| Some (1, 2); Some (1, 2); None |]);
  assert (Match.as_string (get (Captures.name c "first")) = "a");
  assert (
    Captures.name c "missing" = None
    && Captures.get c (-1) = None
    && Captures.get c 10 = None);
  assert (List.length (List.of_seq (Captures.iter c)) = 3);
  assert (Captures.expand c "${first}-$2-$$-$missing" = "a--$-");
  invalid (fun () -> Captures.extract c ~groups:1);
  let fixed = compile "(a)(b)" in
  assert (static_captures_len fixed = Some 3);
  assert (
    Captures.extract (get (captures fixed "ab")) ~groups:2
    = ("ab", [| "a"; "b" |]));
  invalid (fun () -> Captures.extract (get (captures fixed "ab")) ~groups:1);
  assert (Array.length (captures_all re "a ab") = 2);
  assert (List.length (List.of_seq (captures_iter re "a ab")) = 2);
  let loc = capture_locations re in
  assert (Capture_locations.len loc = 3);
  assert (Capture_locations.get loc 0 = None);
  assert (Match.range (get (captures_read re loc "za")) = (1, 2));
  assert (Capture_locations.offsets loc = [| Some (1, 2); Some (1, 2); None |]);
  assert (Capture_locations.get loc 10 = None);
  assert (captures_read (clone re) loc "ab" <> None);
  assert (captures_read re loc "z" = None);
  assert (Capture_locations.offsets loc = [| None; None; None |]);
  invalid (fun () -> captures_read fixed loc "ab");
  invalid (fun () -> captures_read_at re loc "a" 2);
  assert (split (compile ",") "a,,b," = [| "a"; ""; "b"; "" |]);
  assert (splitn (compile ",") "a,b,c" 2 = [| "a"; "b,c" |]);
  assert (splitn re "a" 0 = [||]);
  invalid (fun () -> splitn re "a" (-1));
  assert (replace re "a ab" "${first}X" = "aX ab");
  assert (replace_all re "a ab" "$2" = " b");
  assert (replacen re "a ab" 1 "x" = "x ab");
  assert (replace_all ~literal:true re "a ab" "$1" = "$1 $1");
  assert (replace_all (compile ".") "\255\254" "\253" = "\253\253");
  invalid (fun () -> replacen re "a" (-1) "x");
  assert (
    replace_all_with re "a ab" (fun caps ->
        String.uppercase_ascii (Match.as_string (Captures.get_match caps)))
    = "A AB");
  assert (
    replace_with re "a ab" (fun _ ->
        Gc.compact ();
        "x")
    = "x ab");
  assert (replacen_with re "a ab" 0 (fun _ -> "$1") = "$1 $1");
  assert (replace_all_with (compile "") "ab" (fun _ -> "-") = "-a-b-");
  invalid (fun () -> replace_with re "a" (fun _ -> invalid_arg "callback"));
  let set = Set.compile [| "a"; "b"; "a"; "c" |] in
  assert (Set.len set = 4 && not (Set.is_empty set));
  assert (Set.patterns (Set.clone set) = [| "a"; "b"; "a"; "c" |]);
  let sm = Set.matches set "ab" in
  assert (
    Set_matches.len sm = 4
    && Set_matches.matched_any sm
    && not (Set_matches.matched_all sm));
  assert (Set_matches.indices sm = [| 0; 1; 2 |]);
  assert (List.of_seq (Set_matches.iter sm) = [ 0; 1; 2 ]);
  assert (Set_matches.matched sm 2 && not (Set_matches.matched sm 3));
  invalid (fun () -> Set_matches.matched sm 4);
  let mask = Array.make 4 true in
  assert (Set.matches_read set mask "ab" && mask = [| true; true; true; false |]);
  assert (
    (not (Set.matches_read set mask "z"))
    && mask = [| false; false; false; false |]);
  assert (Set_matches.matched_all (Set.matches set "abc"));
  assert (not (Set.is_match_at (Set.compile [| "^a" |]) "ba" 1));
  invalid (fun () -> Set.matches_read set [||] "ab");
  invalid (fun () -> Set.is_match_at set "ab" 3);
  invalid (fun () -> Set.matches_at set "ab" (-1));
  error (Set.compile_result [| "x"; "(" |]);
  error (Set.compile_result [| "\255" |]);
  let empty = Set.empty () in
  assert (Set.is_empty empty && not (Set.is_match empty "x"));
  assert (Set_matches.matched_all (Set.matches empty "x"));
  assert (
    Set.is_match
      (Set.Builder.build_exn
         (Set.Builder.case_insensitive (Set.Builder.create [| "x" |]) true))
      "X");
  let unicode = Utf8.compile {|\w+|} in
  assert (Match.as_string (get (Utf8.find unicode "é")) = "é");
  assert (ranges (Utf8.find_all (Utf8.compile "") "é") = [| (0, 0); (2, 2) |]);
  assert (ranges (find_all (compile "") "é") = [| (0, 0); (1, 1); (2, 2) |]);
  assert (Utf8.find_at unicode "é x" 1 |> Option.map Match.range = Some (3, 4));
  error (Utf8.compile_result ~unicode:false ".");
  invalid (fun () -> Utf8.is_match unicode "\255");
  invalid (fun () -> Utf8.find_all unicode "\255");
  invalid (fun () -> Utf8.split unicode "\255");
  invalid (fun () -> Utf8.replace_all unicode "é" "\255");
  invalid (fun () -> Utf8.replace_all_with unicode "é" (fun _ -> "\255"));
  invalid (fun () -> Utf8.Set.matches (Utf8.Set.compile [| "x" |]) "\255");
  let u =
    Utf8.Builder.build_exn
      (Utf8.Builder.case_insensitive (Utf8.Builder.create "É") true)
  in
  assert (Utf8.is_match u "é");
  let uloc = Utf8.capture_locations unicode in
  assert (
    Utf8.captures_read unicode uloc "é" |> Option.map Match.range = Some (0, 2));
  let names = capture_names re in
  names.(1) <- None;
  assert (capture_names re = [| None; Some "first"; None |]);
  for i = 1 to 2000 do
    let temporary = compile "abc" in
    assert (is_match temporary "abc");
    if i mod 50 = 0 then Gc.compact ()
  done;
  Gc.full_major ();
  assert (is_match re "a");
  assert (Captures.expand c "$first" = "a");
  print_endline "all regex API tests passed"
