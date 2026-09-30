let read path =
  let channel = open_in_bin path in
  let text = really_input_string channel (in_channel_length channel) in
  close_in channel;
  text

let lines path =
  String.split_on_char '\n' (read path) |> List.filter (( <> ) "")

let median xs =
  List.sort compare xs |> fun xs -> List.nth xs (List.length xs / 2)

let sink = ref 0

(* Inputs and compilation are outside timing. Each invocation crosses the FFI,
   not one batch call per corpus. Report median time per complete corpus pass. *)
let measure f payloads =
  let pass () =
    Array.iter (fun (_, text) -> if f text then incr sink) payloads
  in
  pass ();
  let start = Unix.gettimeofday () in
  pass ();
  let elapsed = Unix.gettimeofday () -. start in
  let count = max 1 (int_of_float (0.1 /. max 0.000001 elapsed)) in
  let samples =
    List.init 5 (fun _ ->
        Gc.full_major ();
        let before = Gc.allocated_bytes () in
        let start = Unix.gettimeofday () in
        for _ = 1 to count do
          pass ()
        done;
        ( (Unix.gettimeofday () -. start) /. float count,
          (Gc.allocated_bytes () -. before) /. float count ))
  in
  (median (List.map fst samples), median (List.map snd samples))

let offsets groups =
  Array.init (Re.Group.nb_groups groups) (fun i ->
      try Some (Re.Group.offset groups i) with Not_found -> None)

let () =
  let corpus = if Array.length Sys.argv > 1 then Sys.argv.(1) else "corpus" in
  let capture_mode = Array.length Sys.argv > 2 && Sys.argv.(2) = "captures" in
  let capture_patterns =
    [
      "path_capture";
      "attribute_capture";
      "assignment_capture";
      "multiline_log_capture";
    ]
  in
  let fixtures =
    lines (Filename.concat corpus "payloads.tsv")
    |> List.map (fun line ->
        match String.split_on_char '\t' line with
        | [ scope; name; hash ] ->
            (scope, name, read (Filename.concat corpus hash))
        | _ -> failwith "invalid payload manifest")
  in
  Printf.printf
    "pattern\tscope\tpayloads\tbytes\tpositives\tbaseline\tbaseline_ms\trust_ms\tspeedup\tbaseline_alloc_bytes\trust_alloc_bytes\n\
     %!";
  List.iter
    (fun line ->
      match String.split_on_char '\t' line with
      | [ name; engine; flags; scope; pattern ] ->
          let has flag =
            List.mem flag
              (String.split_on_char ';' flags |> List.map String.trim)
          in
          let caseless = has "`CASELESS"
          and multiline = has "`MULTILINE"
          and dotall = has "`DOTALL" in
          let flags =
            (if caseless then [ `CASELESS ] else [])
            @ (if multiline then [ `MULTILINE ] else [])
            @ if dotall then [ `DOTALL ] else []
          in
          let payloads =
            List.filter_map
              (fun (category, name, data) ->
                if category = scope then Some (name, data) else None)
              fixtures
            |> Array.of_list
          in
          if Array.length payloads = 0 then failwith "empty benchmark scope";
          let re =
            if engine = "Re" then Some (Re.Pcre.regexp ~flags pattern) else None
          in
          let baseline =
            match re with
            | Some re when capture_mode ->
                fun text ->
                  Option.is_some (Option.map offsets (Re.exec_opt re text))
            | Some re -> Re.execp re
            | None ->
                let re = Pcre.regexp ~flags pattern in
                fun text -> Pcre.pmatch ~rex:re text
          in
          let rust =
            try Some (Rust_regex.compile ~caseless ~multiline ~dotall pattern)
            with Invalid_argument message ->
              Printf.eprintf "UNSUPPORTED %s: %s\n%!" name message;
              None
          in
          let positives = ref 0 in
          Array.iter
            (fun (file, text) ->
              let expected = baseline text in
              if expected then incr positives;
              match rust with
              | Some rust -> (
                  if Rust_regex.is_match rust text <> expected then
                    failwith
                      (Printf.sprintf "match mismatch: %s / %s" name file);
                  (* Verify capture ranges in boolean runs too, wherever the
                     original engine supports the same pattern. *)
                  match re with
                  | Some re ->
                      let expected = Option.map offsets (Re.exec_opt re text) in
                      if expected <> Rust_regex.captures_offsets rust text then
                        failwith
                          (Printf.sprintf "capture mismatch: %s / %s" name file)
                  | None -> ())
              | None -> ())
            payloads;
          let seconds, alloc = measure baseline payloads in
          let bytes =
            Array.fold_left
              (fun total (_, text) -> total + String.length text)
              0 payloads
          in
          let rust_ms, speedup, rust_alloc =
            match rust with
            | None -> ("NA", "NA", "NA")
            | Some rust ->
                let search =
                  if capture_mode then fun text ->
                    Option.is_some (Rust_regex.captures_offsets rust text)
                  else Rust_regex.is_match rust
                in
                let time, allocated = measure search payloads in
                ( Printf.sprintf "%.6f" (time *. 1000.),
                  Printf.sprintf "%.2f" (seconds /. time),
                  Printf.sprintf "%.0f" allocated )
          in
          Printf.printf "%s\t%s\t%d\t%d\t%d\t%s\t%.6f\t%s\t%s\t%.0f\t%s\n%!"
            name scope (Array.length payloads) bytes !positives
            (if capture_mode then "Re-capture-offsets" else engine)
            (seconds *. 1000.) rust_ms speedup alloc rust_alloc
      | _ -> failwith "invalid pattern manifest")
    (lines (Filename.concat corpus "patterns.tsv")
    |> List.filter (fun line ->
        (not capture_mode)
        || List.mem (List.hd (String.split_on_char '\t' line)) capture_patterns)
    )
