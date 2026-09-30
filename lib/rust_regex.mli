type range = int * int
(** OCaml bindings to Rust's [regex] crate. All positions are byte offsets.
    [Bytes] accepts arbitrary byte strings and defaults to ASCII classes; [Utf8]
    validates UTF-8 and defaults to Unicode classes. The top-level API aliases
    [Bytes]. Patterns must always be UTF-8, including byte-mode patterns.

    Search operations borrow the input while holding the OCaml runtime lock.
    Iteration APIs materialize Rust's iterator into arrays before returning
    repeatable OCaml sequences. No borrowed Rust object outlives an FFI call.
    Compiled regexes can be shared between domains; reusable capture locations
    are synchronized, but read/get pairs are not atomic transactions.

    Invalid UTF-8, negative limits, out-of-bounds positions and incompatible
    locations raise [Invalid_argument]. Builder errors are returned as [Error]
    or raised by [compile]/[build_exn]. Look-around and backreferences are not
    supported. Compiled handles cannot be marshalled or structurally compared.
*)

val escape : string -> string
(** Escape a UTF-8 string so it can be used as a literal regex. *)

module Match : sig
  type t

  val start : t -> int
  val end_ : t -> int
  val range : t -> range
  val length : t -> int
  val is_empty : t -> bool
  val as_string : t -> string
end

module Captures : sig
  type t

  val len : t -> int
  val get : t -> int -> Match.t option
  val get_match : t -> Match.t
  val name : t -> string -> Match.t option
  val offsets : t -> range option array
  val iter : t -> Match.t option Seq.t

  val extract : t -> groups:int -> string * string array
  (** Return the full match and participating capture strings. Requires a static
      capture count equal to [groups + 1], as Rust's [Captures::extract] does.
  *)

  val expand : t -> string -> string
  (** Rust replacement syntax: [$1], [$name], [${name}], [$$]. Missing groups
      expand to the empty string. *)
end

module Set_matches : sig
  type t

  val len : t -> int
  (** Number of patterns in the set, not number of matching patterns. *)

  val matched_any : t -> bool
  val matched_all : t -> bool
  val matched : t -> int -> bool
  val indices : t -> int array
  val iter : t -> int Seq.t
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
  (** Defaults match Rust's builders except [Bytes] defaults [unicode=false].
      Builders are immutable; each option setter returns a new builder. *)

  val clone : t -> t
  val as_str : t -> string
  val capture_names : t -> string option array
  val captures_len : t -> int
  val static_captures_len : t -> int option
  val is_match : t -> string -> bool
  val is_match_at : t -> string -> int -> bool
  val find : t -> string -> Match.t option

  val find_at : t -> string -> int -> Match.t option
  (** [_at] searches preserve the entire input's anchor/boundary context; they
      do not search a sliced string. Positions in [0, String.length input] are
      accepted, including non-character-boundary positions in UTF-8 mode,
      following Rust's API. *)

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
  (** Iteration follows Rust's empty/adjacent match rules, not a naive [_at]
      loop. Sequences are eager snapshots and retain the source string. *)

  val split : t -> string -> string array

  val splitn : t -> string -> int -> string array
  (** [splitn re input n] returns at most [n] fields; zero returns no fields. *)

  val replace : ?literal:bool -> t -> string -> string -> string
  val replace_all : ?literal:bool -> t -> string -> string -> string

  val replacen : ?literal:bool -> t -> string -> int -> string -> string
  (** [replacen re input n replacement]: zero means unlimited replacements.
      [literal=true] disables capture interpolation (Rust's [NoExpand]). *)

  val replace_with : t -> string -> (Captures.t -> string) -> string
  val replace_all_with : t -> string -> (Captures.t -> string) -> string

  val replacen_with : t -> string -> int -> (Captures.t -> string) -> string
  (** Callbacks run in OCaml after captures have been snapshotted; exceptions
      propagate normally. [Utf8] validates callback outputs as UTF-8. *)

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
  (** Reuse locations allocated for this regex or its clone. Locations retain no
      source string. After a miss all offsets are [None]. *)

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
    (** Overwrite a caller-owned boolean array of exactly [len set] entries.
        These OCaml arrays are not synchronized across domains. *)

    module Builder : sig
      type regex_set = t

      include Builder_options

      val create : string array -> t
      val build : t -> (regex_set, string) result
      val build_exn : t -> regex_set
    end
  end
end

module Bytes : S
module Utf8 : S

include
  S
    with type t = Bytes.t
     and type Capture_locations.t = Bytes.Capture_locations.t
     and type Builder.t = Bytes.Builder.t
     and type Set.t = Bytes.Set.t
     and type Set.Builder.t = Bytes.Set.Builder.t
