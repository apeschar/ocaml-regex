type raw
type raw_set
type raw_locations
type range = int * int

type options = {
  caseless : bool;
  multiline : bool;
  dotall : bool;
  unicode : bool;
  crlf : bool;
  line_terminator : int;
  swap_greed : bool;
  ignore_whitespace : bool;
  octal : bool;
  size_limit : int;
  dfa_size_limit : int;
  nest_limit : int;
}

external build_raw : string -> options -> bool -> (raw, string) result
  = "rust_regex_build"

external clone_raw : raw -> raw = "rust_regex_clone"
external pattern_raw : raw -> string = "rust_regex_pattern"
external names_raw : raw -> string option array = "rust_regex_capture_names"
external static_len_raw : raw -> int option = "rust_regex_static_captures_len"
external is_match_raw : raw -> string -> int -> bool = "rust_regex_is_match"
external find_raw : raw -> string -> int -> range option = "rust_regex_find"

external shortest_raw : raw -> string -> int -> int option
  = "rust_regex_shortest_match"

external captures_raw : raw -> string -> int -> range option array option
  = "rust_regex_captures"

external find_all_raw : raw -> string -> range array = "rust_regex_find_all"

external captures_all_raw : raw -> string -> range option array array
  = "rust_regex_captures_all"

external split_raw : raw -> string -> int -> string array = "rust_regex_split"

external replace_raw : raw -> string -> string -> int -> bool -> string
  = "rust_regex_replace"

external expand_raw : raw -> string -> int -> string -> string option
  = "rust_regex_expand"

external escape : string -> string = "rust_regex_escape"
external validate_utf8_raw : string -> unit = "rust_regex_validate_utf8"
external locations_raw : raw -> raw_locations = "rust_regex_locations"

external locations_get_raw : raw_locations -> range option array
  = "rust_regex_locations_get"

external locations_len_raw : raw_locations -> int = "rust_regex_locations_len"

external locations_index_raw : raw_locations -> int -> range option
  = "rust_regex_locations_index"

external captures_read_raw :
  raw -> raw_locations -> string -> int -> range option
  = "rust_regex_captures_read"

external set_build_raw :
  string array -> options -> bool -> (raw_set, string) result
  = "rust_regex_set_build"

external set_clone_raw : raw_set -> raw_set = "rust_regex_set_clone"
external set_patterns_raw : raw_set -> string array = "rust_regex_set_patterns"

external set_is_match_raw : raw_set -> string -> int -> bool
  = "rust_regex_set_is_match"

external set_matches_raw : raw_set -> string -> int -> int array
  = "rust_regex_set_matches"

let get_exn = function
  | Ok value -> value
  | Error message -> invalid_arg message

let options ~unicode =
  {
    caseless = false;
    multiline = false;
    dotall = false;
    unicode;
    crlf = false;
    line_terminator = 10;
    swap_greed = false;
    ignore_whitespace = false;
    octal = false;
    size_limit = 10 * 1024 * 1024;
    dfa_size_limit = 2 * 1024 * 1024;
    nest_limit = 250;
  }

module Match = struct
  type t = { source : string; start : int; stop : int }

  let start t = t.start
  let end_ t = t.stop
  let range t = (t.start, t.stop)
  let length t = t.stop - t.start
  let is_empty t = t.start = t.stop
  let as_string t = String.sub t.source t.start (length t)
  let make source (start, stop) = { source; start; stop }
end

module Captures = struct
  type t = {
    re : raw;
    source : string;
    groups : range option array;
    names : string option array;
    static_len : int option;
  }

  let len t = Array.length t.groups

  let get t i =
    if i < 0 || i >= len t then None
    else Option.map (Match.make t.source) t.groups.(i)

  let get_match t = Option.get (get t 0)

  let name t name =
    let rec loop i =
      if i = Array.length t.names then None
      else if t.names.(i) = Some name then get t i
      else loop (i + 1)
    in
    loop 0

  let offsets t = Array.copy t.groups

  let iter t =
    Array.to_seq t.groups |> Seq.map (Option.map (Match.make t.source))

  let extract t ~groups =
    if t.static_len <> Some (groups + 1) || groups < 0 then
      invalid_arg
        "Rust_regex.Captures.extract: non-static or incorrect capture count";
    let values =
      Array.to_list t.groups |> List.tl
      |> List.filter_map
           (Option.map (fun r -> Match.as_string (Match.make t.source r)))
      |> Array.of_list
    in
    (Match.as_string (get_match t), values)

  let expand t replacement =
    Option.get
      (expand_raw t.re t.source (Match.start (get_match t)) replacement)
end

module Set_matches = struct
  type t = { indices : int array; count : int }

  let len t = t.count
  let matched_any t = Array.length t.indices > 0
  let matched_all t = Array.length t.indices = t.count

  let matched t i =
    if i < 0 || i >= t.count then
      invalid_arg "Rust_regex.Set_matches.matched: index out of bounds";
    Array.exists (( = ) i) t.indices

  let indices t = Array.copy t.indices
  let iter t = Array.to_seq t.indices
end

module type Builder_options = sig
  type t

  val case_insensitive : t -> bool -> t
  val multi_line : t -> bool -> t
  val dot_matches_new_line : t -> bool -> t
  val unicode : t -> bool -> t
  val crlf : t -> bool -> t
  val line_terminator : t -> char -> t
  val swap_greed : t -> bool -> t
  val ignore_whitespace : t -> bool -> t
  val octal : t -> bool -> t
  val size_limit : t -> int -> t
  val dfa_size_limit : t -> int -> t
  val nest_limit : t -> int -> t
end

module type S = sig
  type t

  val compile_result :
    ?caseless:bool ->
    ?multiline:bool ->
    ?dotall:bool ->
    ?unicode:bool ->
    ?crlf:bool ->
    ?line_terminator:char ->
    ?swap_greed:bool ->
    ?ignore_whitespace:bool ->
    ?octal:bool ->
    ?size_limit:int ->
    ?dfa_size_limit:int ->
    ?nest_limit:int ->
    string ->
    (t, string) result

  val compile :
    ?caseless:bool ->
    ?multiline:bool ->
    ?dotall:bool ->
    ?unicode:bool ->
    ?crlf:bool ->
    ?line_terminator:char ->
    ?swap_greed:bool ->
    ?ignore_whitespace:bool ->
    ?octal:bool ->
    ?size_limit:int ->
    ?dfa_size_limit:int ->
    ?nest_limit:int ->
    string ->
    t

  val clone : t -> t
  val as_str : t -> string
  val capture_names : t -> string option array
  val captures_len : t -> int
  val static_captures_len : t -> int option
  val is_match : t -> string -> bool
  val is_match_at : t -> string -> int -> bool
  val find : t -> string -> Match.t option
  val find_at : t -> string -> int -> Match.t option
  val shortest_match : t -> string -> int option
  val shortest_match_at : t -> string -> int -> int option
  val captures : t -> string -> Captures.t option
  val captures_at : t -> string -> int -> Captures.t option
  val captures_offsets : t -> string -> range option array option
  val captures_offsets_at : t -> string -> int -> range option array option
  val find_all : t -> string -> Match.t array
  val find_iter : t -> string -> Match.t Seq.t
  val captures_all : t -> string -> Captures.t array
  val captures_iter : t -> string -> Captures.t Seq.t
  val split : t -> string -> string array
  val splitn : t -> string -> int -> string array
  val replace : ?literal:bool -> t -> string -> string -> string
  val replace_all : ?literal:bool -> t -> string -> string -> string
  val replacen : ?literal:bool -> t -> string -> int -> string -> string
  val replace_with : t -> string -> (Captures.t -> string) -> string
  val replace_all_with : t -> string -> (Captures.t -> string) -> string
  val replacen_with : t -> string -> int -> (Captures.t -> string) -> string

  module Capture_locations : sig
    type t

    val len : t -> int
    val get : t -> int -> range option
    val offsets : t -> range option array
  end

  val capture_locations : t -> Capture_locations.t
  val captures_read : t -> Capture_locations.t -> string -> Match.t option

  val captures_read_at :
    t -> Capture_locations.t -> string -> int -> Match.t option

  module Builder : sig
    type regex = t

    include Builder_options

    val create : string -> t
    val build : t -> (regex, string) result
    val build_exn : t -> regex
  end

  module Set : sig
    type t

    val compile_result :
      ?caseless:bool ->
      ?multiline:bool ->
      ?dotall:bool ->
      ?unicode:bool ->
      ?crlf:bool ->
      ?line_terminator:char ->
      ?swap_greed:bool ->
      ?ignore_whitespace:bool ->
      ?octal:bool ->
      ?size_limit:int ->
      ?dfa_size_limit:int ->
      ?nest_limit:int ->
      string array ->
      (t, string) result

    val compile :
      ?caseless:bool ->
      ?multiline:bool ->
      ?dotall:bool ->
      ?unicode:bool ->
      ?crlf:bool ->
      ?line_terminator:char ->
      ?swap_greed:bool ->
      ?ignore_whitespace:bool ->
      ?octal:bool ->
      ?size_limit:int ->
      ?dfa_size_limit:int ->
      ?nest_limit:int ->
      string array ->
      t

    val empty : unit -> t
    val clone : t -> t
    val len : t -> int
    val is_empty : t -> bool
    val patterns : t -> string array
    val is_match : t -> string -> bool
    val is_match_at : t -> string -> int -> bool
    val matches : t -> string -> Set_matches.t
    val matches_at : t -> string -> int -> Set_matches.t
    val matches_read : t -> bool array -> string -> bool
    val matches_read_at : t -> bool array -> string -> int -> bool

    module Builder : sig
      type regex_set = t

      include Builder_options

      val create : string array -> t
      val build : t -> (regex_set, string) result
      val build_exn : t -> regex_set
    end
  end
end

module Make (Mode : sig
  val utf8 : bool
end) =
struct
  type t = { raw : raw; names : string option array; static_len : int option }

  let wrap raw = { raw; names = names_raw raw; static_len = static_len_raw raw }

  let compile_result ?(caseless = false) ?(multiline = false) ?(dotall = false)
      ?(unicode = Mode.utf8) ?(crlf = false) ?(line_terminator = '\n')
      ?(swap_greed = false) ?(ignore_whitespace = false) ?(octal = false)
      ?(size_limit = 10 * 1024 * 1024) ?(dfa_size_limit = 2 * 1024 * 1024)
      ?(nest_limit = 250) pattern =
    let opts =
      {
        caseless;
        multiline;
        dotall;
        unicode;
        crlf;
        line_terminator = Char.code line_terminator;
        swap_greed;
        ignore_whitespace;
        octal;
        size_limit;
        dfa_size_limit;
        nest_limit;
      }
    in
    Result.map wrap (build_raw pattern opts Mode.utf8)

  let compile ?caseless ?multiline ?dotall ?unicode ?crlf ?line_terminator
      ?swap_greed ?ignore_whitespace ?octal ?size_limit ?dfa_size_limit
      ?nest_limit pattern =
    get_exn
      (compile_result ?caseless ?multiline ?dotall ?unicode ?crlf
         ?line_terminator ?swap_greed ?ignore_whitespace ?octal ?size_limit
         ?dfa_size_limit ?nest_limit pattern)

  let clone re = wrap (clone_raw re.raw)
  let as_str re = pattern_raw re.raw
  let capture_names re = Array.copy re.names
  let captures_len re = Array.length re.names
  let static_captures_len re = re.static_len
  let is_match_at re source pos = is_match_raw re.raw source pos
  let is_match re source = is_match_at re source 0

  let find_at re source pos =
    Option.map (Match.make source) (find_raw re.raw source pos)

  let find re source = find_at re source 0
  let shortest_match_at re source pos = shortest_raw re.raw source pos
  let shortest_match re source = shortest_match_at re source 0
  let captures_offsets_at re source pos = captures_raw re.raw source pos
  let captures_offsets re source = captures_offsets_at re source 0

  let make_captures re source groups =
    {
      Captures.re = re.raw;
      source;
      groups;
      names = re.names;
      static_len = re.static_len;
    }

  let captures_at re source pos =
    Option.map (make_captures re source) (captures_offsets_at re source pos)

  let captures re source = captures_at re source 0

  let find_all re source =
    Array.map (Match.make source) (find_all_raw re.raw source)

  let find_iter re source = Array.to_seq (find_all re source)

  let captures_all re source =
    Array.map (make_captures re source) (captures_all_raw re.raw source)

  let captures_iter re source = Array.to_seq (captures_all re source)
  let splitn re source limit = split_raw re.raw source limit
  let split re source = splitn re source max_int

  let replacen ?(literal = false) re source limit replacement =
    replace_raw re.raw source replacement limit literal

  let replace ?literal re source replacement =
    replacen ?literal re source 1 replacement

  let replace_all ?literal re source replacement =
    replacen ?literal re source 0 replacement

  let replacen_with re source limit replacement =
    if limit < 0 then invalid_arg "Rust_regex: negative replacement limit";
    (* Reuse Rust's iterator to preserve its empty/adjacent match rules. Callbacks
       run in OCaml only after Rust has returned owned capture offsets. *)
    let matches = captures_all re source in
    let count =
      if limit = 0 then Array.length matches
      else min limit (Array.length matches)
    in
    let dst = Buffer.create (String.length source) in
    let previous = ref 0 in
    for i = 0 to count - 1 do
      let caps = matches.(i) in
      let m = Captures.get_match caps in
      Buffer.add_substring dst source !previous (Match.start m - !previous);
      let replacement = replacement caps in
      if Mode.utf8 then validate_utf8_raw replacement;
      Buffer.add_string dst replacement;
      previous := Match.end_ m
    done;
    Buffer.add_substring dst source !previous (String.length source - !previous);
    Buffer.contents dst

  let replace_with re source replacement = replacen_with re source 1 replacement

  let replace_all_with re source replacement =
    replacen_with re source 0 replacement

  module Capture_locations = struct
    type t = raw_locations

    let len = locations_len_raw
    let get = locations_index_raw
    let offsets = locations_get_raw
  end

  let capture_locations re = locations_raw re.raw

  let captures_read_at re loc source pos =
    Option.map (Match.make source) (captures_read_raw re.raw loc source pos)

  let captures_read re loc source = captures_read_at re loc source 0

  module Builder = struct
    type regex = t
    type t = { pattern : string; opts : options }

    let create pattern = { pattern; opts = options ~unicode:Mode.utf8 }

    let case_insensitive t value =
      { t with opts = { t.opts with caseless = value } }

    let multi_line t value = { t with opts = { t.opts with multiline = value } }

    let dot_matches_new_line t value =
      { t with opts = { t.opts with dotall = value } }

    let unicode t value = { t with opts = { t.opts with unicode = value } }
    let crlf t value = { t with opts = { t.opts with crlf = value } }

    let line_terminator t value =
      { t with opts = { t.opts with line_terminator = Char.code value } }

    let swap_greed t value =
      { t with opts = { t.opts with swap_greed = value } }

    let ignore_whitespace t value =
      { t with opts = { t.opts with ignore_whitespace = value } }

    let octal t value = { t with opts = { t.opts with octal = value } }

    let size_limit t value =
      { t with opts = { t.opts with size_limit = value } }

    let dfa_size_limit t value =
      { t with opts = { t.opts with dfa_size_limit = value } }

    let nest_limit t value =
      { t with opts = { t.opts with nest_limit = value } }

    let build t = Result.map wrap (build_raw t.pattern t.opts Mode.utf8)
    let build_exn t = get_exn (build t)
  end

  module Set = struct
    type t = { raw : raw_set; patterns : string array }

    let wrap raw = { raw; patterns = set_patterns_raw raw }

    let compile_result ?(caseless = false) ?(multiline = false)
        ?(dotall = false) ?(unicode = Mode.utf8) ?(crlf = false)
        ?(line_terminator = '\n') ?(swap_greed = false)
        ?(ignore_whitespace = false) ?(octal = false)
        ?(size_limit = 10 * 1024 * 1024) ?(dfa_size_limit = 2 * 1024 * 1024)
        ?(nest_limit = 250) patterns =
      let opts =
        {
          caseless;
          multiline;
          dotall;
          unicode;
          crlf;
          line_terminator = Char.code line_terminator;
          swap_greed;
          ignore_whitespace;
          octal;
          size_limit;
          dfa_size_limit;
          nest_limit;
        }
      in
      Result.map wrap (set_build_raw patterns opts Mode.utf8)

    let compile ?caseless ?multiline ?dotall ?unicode ?crlf ?line_terminator
        ?swap_greed ?ignore_whitespace ?octal ?size_limit ?dfa_size_limit
        ?nest_limit patterns =
      get_exn
        (compile_result ?caseless ?multiline ?dotall ?unicode ?crlf
           ?line_terminator ?swap_greed ?ignore_whitespace ?octal ?size_limit
           ?dfa_size_limit ?nest_limit patterns)

    let empty () = compile [||]
    let clone set = wrap (set_clone_raw set.raw)
    let len set = Array.length set.patterns
    let is_empty set = len set = 0
    let patterns set = Array.copy set.patterns
    let is_match_at set source pos = set_is_match_raw set.raw source pos
    let is_match set source = is_match_at set source 0

    let matches_at set source pos =
      {
        Set_matches.indices = set_matches_raw set.raw source pos;
        count = len set;
      }

    let matches set source = matches_at set source 0

    let matches_read_at set dst source pos =
      if Array.length dst <> len set then
        invalid_arg "Rust_regex.Set.matches_read: wrong array length";
      let result = matches_at set source pos in
      Array.fill dst 0 (Array.length dst) false;
      Array.iter (fun i -> dst.(i) <- true) (Set_matches.indices result);
      Set_matches.matched_any result

    let matches_read set dst source = matches_read_at set dst source 0

    module Builder = struct
      type regex_set = t
      type t = { patterns : string array; opts : options }

      let create patterns =
        { patterns = Array.copy patterns; opts = options ~unicode:Mode.utf8 }

      let case_insensitive t value =
        { t with opts = { t.opts with caseless = value } }

      let multi_line t value =
        { t with opts = { t.opts with multiline = value } }

      let dot_matches_new_line t value =
        { t with opts = { t.opts with dotall = value } }

      let unicode t value = { t with opts = { t.opts with unicode = value } }
      let crlf t value = { t with opts = { t.opts with crlf = value } }

      let line_terminator t value =
        { t with opts = { t.opts with line_terminator = Char.code value } }

      let swap_greed t value =
        { t with opts = { t.opts with swap_greed = value } }

      let ignore_whitespace t value =
        { t with opts = { t.opts with ignore_whitespace = value } }

      let octal t value = { t with opts = { t.opts with octal = value } }

      let size_limit t value =
        { t with opts = { t.opts with size_limit = value } }

      let dfa_size_limit t value =
        { t with opts = { t.opts with dfa_size_limit = value } }

      let nest_limit t value =
        { t with opts = { t.opts with nest_limit = value } }

      let build t = Result.map wrap (set_build_raw t.patterns t.opts Mode.utf8)
      let build_exn t = get_exn (build t)
    end
  end
end

module Bytes = Make (struct
  let utf8 = false
end)

module Utf8 = Make (struct
  let utf8 = true
end)

include Bytes
