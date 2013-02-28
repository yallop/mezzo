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

exception MzInternalFailure of string

let the_debug_level = ref 0
let debug_level () = !the_debug_level
let enable_debug level = the_debug_level := level

let debug ?level fmt =
  (* If no level is provided, the message is always displayed. *)
  let level = Option.map_none 1 level in
  if level <= !the_debug_level then begin
    MzString.bfprintf ~new_line:() stderr fmt
  end else begin
    MzString.biprintf fmt
  end

let warn_count = ref 0
let warn x = incr warn_count; debug ~level:0 x

let raise_level d f =
  let l = !the_debug_level in
  the_debug_level := !the_debug_level - d;
  let r = f () in
  the_debug_level := l;
  r

let silent f =
  let l = !the_debug_level in
  the_debug_level := 0;
  let r =
    try f ()
    with e ->
      the_debug_level := l;
      raise e
  in
  the_debug_level := l;
  r

let msg fmt =
  Printf.kbprintf (fun buf ->
    Buffer.add_char buf '\n';
    Buffer.contents buf
  ) (Buffer.create 16) fmt

let fail_with_summary buf =
  Buffer.output_buffer stderr buf;
  let c = Buffer.contents buf in
  let summary =
    let i = String.index c '\n' in
    if i >= 0 then String.sub c 0 i else c
  in
  raise (MzInternalFailure summary)

let error fmt =
  let buf = Buffer.create 16 in
  Buffer.add_string buf "Mezzo internal error: ";
  Printf.kbprintf (fun buf ->
    Buffer.add_char buf '\n';
    fail_with_summary buf
  ) buf fmt

let check b fmt =
  let open Printf in
  if b then
    MzString.biprintf fmt
  else begin
    let buf = Buffer.create 16 in
    Buffer.add_string buf "Mezzo internal assert failure: ";
    Buffer.add_string buf Bash.colors.Bash.red;
    kbprintf (fun buf ->
      Buffer.add_string buf (Bash.colors.Bash.default ^ "\n");
      fail_with_summary buf
    ) buf fmt
  end
