(** This module implements a persistent store: in other words, it
   is a purely functional implementation of references, with an
   explicit store. *)

type location

type 'a store

(* The empty store. *)

val empty: 'a store

(* Allocation. *)

val make: 'a -> 'a store -> location * 'a store

(* Read access. *)

val get: location -> 'a store -> 'a

(* Write access. *)

val set: location -> 'a -> 'a store -> 'a store

(* Iterating on all locations. *)

val iter: ('a -> unit) -> 'a store -> unit

(* Folding *)

val fold: ('acc -> location -> 'a -> 'acc) -> 'acc -> 'a store -> 'acc

(* Address comparison. *)

val eq: location -> location -> bool
val neq: location -> location -> bool
val compare: location -> location -> int
