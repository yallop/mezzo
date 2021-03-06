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

val try_finally : (unit -> 'a) -> (unit -> unit) -> 'a
val with_open_in : string -> (in_channel -> 'a) -> 'a
val with_open_out : string -> (out_channel -> 'a) -> 'a

val dont_inline: 'a -> 'a
val fresh_name: string -> string
val fresh_var: string -> Variable.name
val read: in_channel -> string
val ptag: Buffer.t -> 'a -> unit

val same_absolute_path: string -> string -> bool

val file_get_contents: string -> string

val get_number_of_cores: unit -> int
