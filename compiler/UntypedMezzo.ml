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

(* This is the definition of Untyped Mezzo. *)

(* This intermediate language differs from Surface Mezzo in a few (minor)
   ways, as follows. *)

(* Untyped Mezzo is untyped. *)

(* In Untyped Mezzo, the adopter fields are explicit, and the adoption and
   abandon operations are replaced with ordinary read and write operations. *)

(* In Untyped Mezzo, the overloading of field names is resolved: fields are
   unambiguously identified by a pair of a data constructor and a field
   name. *)

(* In Untyped Mezzo, the evaluation order is not guaranteed to be left-to-right.
   Where necessary, the translation of Mezzo to Untyped Mezzo introduces explicit
   sequencing constructs. *)

(* ---------------------------------------------------------------------------- *)

(* The patterns of Untyped Mezzo are those of Surface Mezzo. *)

(* A few constructors, such as [PLocated] and [PConstraint], are of no use,
   but we do not bother defining a new type of patterns for Untyped Mezzo. *)

(* In a [PConstruct] pattern, the adopter field never appears explicitly. *)

type pattern =
    SurfaceSyntax.pattern

(* ---------------------------------------------------------------------------- *)

(* Expressions. *)

type rec_flag =
    SurfaceSyntax.rec_flag

type field =
    SurfaceSyntax.field

type previous_and_new_datacon =
    SurfaceSyntax.previous_and_new_datacon

type expression =
  | EVar of Variable.name
  | EQualified of Module.name * Variable.name
  | EBuiltin of string
  | ELet of rec_flag * (pattern * expression) list * expression
  | EFun of pattern * expression
  | EAssign of expression * field * expression
    (* The expression carried by [EAssignTag] must be a value. *)
  | EAssignTag of expression * previous_and_new_datacon
  | EAccess of expression * field
  | EApply of expression * expression
  | EMatch of expression * (pattern * expression) list
  | ETuple of expression list
  | EConstruct of (Datacon.name * (Variable.name * expression) list)
  | EIfThenElse of expression * expression * expression
  | ESequence of expression * expression
  | EInt of int
  | EFail of string (* cause and location of failure *)
  | ENull

(* ---------------------------------------------------------------------------- *)

(* Top-level declarations. *)

(* Algebraic data type definitions. *)

type data_type_def_branch =
    (* data constructor, field names *)
    Datacon.name * Variable.name list
      
type data_type_def =
    (* type constructor, branches *)
    Variable.name * data_type_def_branch list

(* Value definitions. *)

type definition =
    rec_flag * (pattern * expression) list

(* Top-level items. *)

type toplevel_item =
  | DataType of data_type_def         (* in interfaces and implementations *)
  | ValueDefinition of definition     (* in implementations only *)
  | ValueDeclaration of Variable.name (* in interfaces only *)
  | OpenDirective of Module.name      (* in implementations only *)

type implementation =
  toplevel_item list

type interface =
  toplevel_item list
