(*****************************************************************************)
(*  Mezzo, a programming language based on permissions                       *)
(*  Copyright (C) 2011, 2012 Jonathan Protzenko and François Pottier         *)
(*                                                                           *)
(*  This program is free software: you can redistribute it and/or modify     *)
(*  it under the terms of the GNU General Public License as published by     *)
(*  the Free Software Foundation, either version 3 of the License, or        *)
(*  (at your option) any later version.                                      *)
(*                                                                           *)
(*  This program is distributed in the hope that it will be useful,          *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of           *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            *)
(*  GNU General Public License for more details.                             *)
(*                                                                           *)
(*  You should have received a copy of the GNU General Public License        *)
(*  along with this program.  If not, see <http://www.gnu.org/licenses/>.    *)
(*                                                                           *)
(*****************************************************************************)

(** This module analyzes data type declarations to synthesize facts about
    data types. *)

open TypeCore

(** [analyze_data_types env vars] assumes that [vars] forms a group of
    mutually recursive algebraic data type definitions. It assumes that
    the members of [vars] which are *abstract* data types have already
    received a fact in [env]. It synthesizes a fact for the members of
    [vars] which are *concrete* data types, and adds these facts to the
    environment, producing a new environment. *)
val analyze_data_types: env -> var list -> env

(** [analyze_type env ty] produces a fact for the type [ty], using the
    information stored in [env] about the ambient type definitions. In
    short, this fact indicates whether [ty] is duplicable, exclusive,
    or affine. *)
val analyze_type: env -> typ -> fact

(** A specialized version of [analyze_type]. *)
val is_duplicable: env -> typ -> bool

(** A specialized version of [analyze_type]. *)
val is_exclusive: env -> typ -> bool