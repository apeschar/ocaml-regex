open Rust_regex

let () =
  let re = compile {|(?<word>a+)(b)?|} in
  let set = Set.compile [| "a"; "b"; "c" |] in
  let loc = capture_locations re in
  let start = Atomic.make false in
  let domains =
    List.init 4 (fun _ ->
        Domain.spawn (fun () ->
            while not (Atomic.get start) do
              Domain.cpu_relax ()
            done;
            for i = 1 to 1000 do
              assert (is_match re "aab");
              assert (Set_matches.indices (Set.matches set "ab") = [| 0; 1 |]);
              assert (
                Captures.expand (Option.get (captures re "aa")) "$word" = "aa");
              assert (
                captures_read re loc "aab" |> Option.map Match.range
                = Some (0, 3));
              assert (Capture_locations.get loc 0 = Some (0, 3));
              assert (is_match (clone re) "a");
              if i mod 100 = 0 then Gc.full_major ()
            done))
  in
  Atomic.set start true;
  List.iter Domain.join domains;
  Gc.compact ();
  assert (is_match re "a");
  print_endline "domain sharing tests passed"
