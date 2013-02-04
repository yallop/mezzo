open SurfaceSyntax
open UntypedMezzo
module O = UntypedOCaml

(* This is the translation of Untyped Mezzo to Untyped OCaml. *)

(* TEMPORARY think about [open]: when we mention a data constructor
   or field name in OCaml, is it always in scope? or must we qualify
   it? can we use qualified names everywhere? *)

(* ---------------------------------------------------------------------------- *)

let datacon_arity (_d : Datacon.name) : int =
  (* including the hidden adopter field *)
  assert false

let datacon_tag (_d : Datacon.name) : int =
  assert false

let field_index (_d : Datacon.name) (_f : Variable.name) : int =
  (* accounting for the hidden adopter field *)
  assert false

let make_field_name (_f : field) : string =
  (* combine datacon name and field name *)
  assert false

let sort_by_index ixs =
  List.sort (fun (i1, _) (i2, _) ->
    Pervasives.compare i1 i2
  ) ixs

(* ---------------------------------------------------------------------------- *)

(* Patterns. *)

(* OCaml does not have type casts within patterns, so we must produce
   well-typed patterns, and furthermore, if several patterns are
   type-compatible in Mezzo, then their OCaml counterparts must be
   type-compatible in OCaml. *)

(* The translation of [PConstruct] patterns is somewhat tricky. When there
   exist multiple tags (i.e., the pattern is refutable), we must translate it
   to a [PConstruct] pattern, because that is the only way of examining the
   tag within an OCaml pattern. When there exists just one tag, we could
   translate to a [PRecord] pattern; but, for simplicity, we will avoid
   distinguishing a special case. Now, in OCaml, data constructors carry
   anonymous fields, so we are forced to drop the field names and rely purely
   on field offsets. *)

(* For this translation to work, we will have to translate a Mezzo algebraic
   data type to a corresponding OCaml algebraic data type, with the same data
   constructors, same arity (plus one, for the adopter field), and use a
   distinct type variable as the type of each argument. *)

let rec translate_pattern (p : pattern) : O.pattern =
  match p with
  | PVar x ->
      O.PVar (Variable.print x)
  | PTuple ps ->
      O.PTuple (List.map translate_pattern ps)
  | PConstruct (datacon, fields) ->
      (* Build a list of (field index, pattern) pairs. *)
      let fields =
	List.map (fun (f, p) ->
	  field_index datacon f,
	  translate_pattern p
	) fields
      in
      (* Sort this list by index. *)
      let fields = sort_by_index fields in
      (* Complete any missing entries, up to this data constructor's arity,
	 with wildcard patterns. At the same time, forget the indices. *)
      let arity = datacon_arity datacon in
      let ps = complete 0 arity fields in
      (* Create a data constructor pattern. *)
      O.PConstruct (Datacon.print datacon, ps)
  | PLocated (p, _)
  | PConstraint (p, _) ->
      translate_pattern p
  | PAs (p, x) ->
      O.PAs (translate_pattern p, Variable.print x)
  | PAny ->
      O.PAny

and complete i arity ips =
  if i = arity then
    []
  else
    match ips with
    | (j, p) :: ips when i = j ->
        (* We have an entry at index [i]. Use it. *)
        p :: complete (i + 1) arity ips
    | _ ->
        (* We do not have an entry. Insert a wildcard pattern for this field. *)
        O.PAny :: complete (i + 1) arity ips

(* ---------------------------------------------------------------------------- *)

(* Integer comparison in OCaml. *)

let apply2 f x y =
  O.EApply (O.EApply (f, x), y)

let gt x y =
  apply2 (O.EInfixVar ">") x y

(* ---------------------------------------------------------------------------- *)

(* Expressions. *)

(* We avoid using [Obj.field] and [Obj.set_field], when possible, because they
   are less efficient in terms of speed and code size. In particular, they seem
   to incorporate a check against the special tag 254, which represents an array
   of values of type double. We prefer to cast the receiver to a record type and
   use an OCaml record access expression. This forces us to translate very Mezzo
   data constructor definition to an OCaml record type definition. *)

let rec transl (e : expression) : O.expression =
  match e with
  | EVar x ->
      O.EVar (Variable.print x)
  | EQualified (m, x) ->
      O.EVar (
	Printf.sprintf "%s.%s"
	  (String.capitalize (Module.print m))
	  (Variable.print x)
      )
  | EBuiltin b ->
      (* The builtin operations are defined in the OCaml library module
	 [MezzoBuiltin]. *)
      O.EVar (Printf.sprintf "MezzoBuiltin.%s" b)
  | ELet (flag, eqs, body) ->
      O.ELet (flag, transl_equations eqs, transl body)
  | EFun (p, e) ->
      O.EFun (translate_pattern p, transl e)
  | EAssign (e1, f, e2) ->
      O.EAssign (O.EMagic (transl e1), make_field_name f, transl e2)
  | EAssignTag (e, { previous_datacon; new_datacon }) ->
      (* We must use [Obj.set_tag]; there is no other way. *)
      (* As an optimization, if the old and new integer tags are equal,
	 there is nothing to do. It is OK, in this case, not to translate
         [e] at all, because the definition of Untyped Mezzo guarantees
	 that [e] is a value. *)
      let previous_tag = datacon_tag previous_datacon
      and new_tag = datacon_tag new_datacon in
      if previous_tag = new_tag then
	O.ETuple []
      else
	O.ESetTag (transl e, new_tag)
  | EAccess (e, f) ->
      O.EAccess (O.EMagic (transl e), make_field_name f)
  | EApply (e1, e2) ->
      O.EApply (O.EMagic (transl e1), transl e2)
  | EMatch (e, branches) ->
      O.EMatch (O.EMagic (transl e), transl_branches branches)
  | ETuple es ->
      O.ETuple (List.map transl es)
  | EConstruct (datacon, fields) ->
      (* Build a list of (field index, expression) pairs. *)
      let fields =
	List.map (fun (f, e) ->
	  field_index datacon f,
	  transl e
	) fields
      in
      (* Sort this list by index. *)
      let fields = sort_by_index fields in
      (* In principle, every field is there. Drop the field names,
	 and create a data constructor expression. *)
      O.EConstruct (Datacon.print datacon, List.map snd fields)
  | EIfThenElse (e, e1, e2) ->
      O.EIfThenElse (
	gt (O.EGetTag (O.ERepr (transl e))) (O.EInt 0),
	transl e1,
	transl e2
      )
  | ESequence (e1, e2) ->
      O.ESequence (transl e1, transl e2)
  | EInt i ->
      O.EInt i
  | EFail s ->
      O.EApply (O.EVar "Pervasives.failwith", O.EStringLiteral s)
  | ENull ->
      (* Using the unit value as a representation of [null]. *)
      O.ETuple []

and transl_equations eqs =
  List.map (fun (p, e) ->
    (* We must insert a [magic] because [e] is matched against [p]. *)
    (* And, if this is a toplevel equation, the bound names of [p]
       will be published at type [Obj.t]. *)
    translate_pattern p, O.EMagic (transl e)
  ) eqs

and transl_branches branches =
  List.map (fun (p, e) ->
    (* We insert a [magic] on every branch, because all branches
       must ultimately have the same type. *)
    translate_pattern p, O.EMagic (transl e)
  ) branches

(* TEMPORARY if the OCaml inliner is good, an application of a builtin
   function to an argument of the appropriate shape should be simplified
   to an application of the corresponding OCaml primitive operation.
   Check this. If that is not the case, perform this simplification here. *)

(* ---------------------------------------------------------------------------- *)

(* Type variables. *)

let tyvar (i : int) =
  Printf.sprintf "'a%d" i

let ty (i : int) =
  O.TyVar (tyvar i)

let init (n : int) (f : int -> 'a) : 'a list =
  let rec loop (i : int) =
    if i = n then
      []
    else
      let x = f i in
      x :: loop (i + 1)
  in
  loop 0

let tyvars (base : int) (n : int) : string list =
  init n (fun i -> tyvar (base + i))

let tys (base : int) (n : int) : O.ty list =
  init n (fun i -> ty (base + i))

(* ---------------------------------------------------------------------------- *)

(* For each data constructor, we create a record type. *)

let datacon_record_name (datacon : Datacon.name) : string =
  Printf.sprintf "__mz_record_%s" (Datacon.print datacon)

let datacon_record (branch : data_type_def_branch) =
  let datacon, fields = branch in
  (* We need as many type parameters as there are fields. *)
  let n = List.length fields in
  let lhs = 
    datacon_record_name datacon,
    tyvars 0 n
  in
  let rhs =
    O.Record (List.map2 (fun f ty ->
      O.Mutable, Variable.print f, ty
    ) fields (tys 0 n))
  in
  O.DataTypeGroup (lhs, rhs)

(* ---------------------------------------------------------------------------- *)

(* For each algebraic data type, we create a sum type. *)

let data_sum_name (typecon : Variable.name) : string =
  Variable.print typecon

let data_branch ((base : int), (branch : data_type_def_branch)) : O.data_type_def_branch =
  let datacon, fields = branch in
  (* [base] is the base number for numbering our type variables. *)
  let n = List.length fields in
  Datacon.print datacon, tys base n

let data_sum (def : data_type_def) =
  let typecon, branches = def in
  (* We need as many type parameters as there are fields, in total,
     in all branches. *)
  let n = ref 0 in
  let branches =
    List.map (fun ((_, fields) as branch) ->
      let base = !n in
      n := base + List.length fields;
      base, branch
    ) branches
  in
  let n = !n in
  let lhs =
    data_sum_name typecon,
    tyvars 0 n
  in
  let rhs =
    O.Sum (List.map data_branch branches)
  in
  O.DataTypeGroup (lhs, rhs)

(* ---------------------------------------------------------------------------- *)

(* Translating top-level items. *)

let translate_item = function
  | DataType ((_, branches) as def) ->
      data_sum def :: List.map datacon_record branches
  | ValueDefinition (flag, eqs) ->
      [ O.ValueDefinition (flag, transl_equations eqs) ]
  | ValueDeclaration x ->
      [ O.ValueDeclaration (Variable.print x, O.TyVar "Obj.t") ]
  | OpenDirective m ->
      [ O.OpenDirective (Module.print m) ]

(* ---------------------------------------------------------------------------- *)

(* Translating implementations. *)

let translate_implementation items =
  List.flatten (List.map translate_item items)

(* ---------------------------------------------------------------------------- *)

(* Make sure that [MezzoBuiltin] is well-typed and stand-alone. *)

let _ = MezzoBuiltin._mz_print_value
