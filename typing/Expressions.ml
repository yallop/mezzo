(* This file contains our internal syntax for expressions. *)

open Types

(* ---------------------------------------------------------------------------- *)

(* Patterns *)

(* The De Bruijn numbering is defined according to a depth-first traversal of
 * the pattern: the first variable encountered will have index 0, and so on. *)
type pattern =
  (* x: τ *)
  | PConstraint of pattern * typ
  (* x *)
  | PVar of Variable.name
  (* (x₁, …, xₙ) *)
  | PTuple of pattern list
  (* Foo { bar = bar; baz = baz; … } *)
  | PConstruct of Datacon.name * (Field.name * Variable.name) list
  | PLocated of pattern * Lexing.position * Lexing.position

(* ---------------------------------------------------------------------------- *)

(* Expressions *)

type rec_flag = SurfaceSyntax.rec_flag = Nonrecursive | Recursive

type expression =
  (* e: τ *)
  | EConstraint of expression * typ
  (* v, bound *)
  | EVar of index
  (* v, free *)
  | EPoint of point
  (* let rec pat = expr and pat' = expr' in expr *)
  | ELet of rec_flag * (pattern * expression) list * expression
  (* fun [a] (x: τ): τ -> e *)
  | EFun of (Variable.name * kind) list * typ list * typ * expression
  (* v.f <- e *)
  | EAssign of expression * Field.name * expression
  (* e e₁ … eₙ *)
  | EApply of expression * expression list
  (* match e with pᵢ -> eᵢ *)
  | EMatch of expression * (pattern * expression) list
  (* (e₁, …, eₙ) *)
  | ETuple of expression list
  (* Foo { bar = bar; baz = baz; … *)
  | EConstruct of Datacon.name * (Field.name * expression) list
  (* if e₁ then e₂ else e₃ *)
  | EIfThenElse of expression * expression * expression
  | ELocated of expression * Lexing.position * Lexing.position
  (* Arithmetic *)
  | EPlus of expression * expression
  | EMinus of expression * expression
  | ETimes of expression * expression
  | EDiv of expression * expression
  | EUMinus of expression
  | EInt of int


(* The grammar below doesn't enforce the “only variables are allowed on the
 * left-hand side of a let rec” rule. We'll see to that later. Here too, the
 * order of the bindings is significant: if the binding is recursive, the
 * variables in all the patterns are collected in order before type-checking the
 * expressions. *)
type declaration =
  | DMultiple of rec_flag * (pattern * expression) list
  | DLocated of declaration * Lexing.position * Lexing.position

type declaration_group =
  declaration list

(* ---------------------------------------------------------------------------- *)

(* Moar fun with De Bruijn. *)

(* [collect_pattern] returns, in order, the list of bindings present in the
 * pattern. *)
let collect_pattern p =
  let rec collect_pattern acc = function
  | PConstraint (p, _) ->
      collect_pattern acc p
  | PVar name ->
      name :: acc
  | PTuple patterns ->
      List.fold_left collect_pattern acc patterns
  | PConstruct (_, fields) ->
      Hml_List.append_rev_front (snd (List.split fields)) acc
  | PLocated (p, _, _) ->
      collect_pattern acc p
  in
  List.rev (collect_pattern [] p)
;;

let rec subst_patexprs t2 i rec_flag patexprs =
  let patterns, expressions = List.split patexprs in
  let names = List.fold_left (fun acc p ->
    collect_pattern p :: acc) [] patterns
  in
  let names = List.flatten names in
  let n = List.length names in
  let expressions = match rec_flag with
    | Recursive ->
        List.map (subst_expr t2 (i + n)) expressions
    | Nonrecursive ->
        List.map (subst_expr t2 i) expressions
  in
  n, List.combine patterns expressions


(* [subst_expr t2 i e] substitutes type [t2] for index [i] in expression [e]. *)
and subst_expr t2 i e =
  match e with
  | EConstraint (e, t) ->
      EConstraint (subst_expr t2 i e, subst t2 i t)

  | EVar _
  | EPoint _ ->
      e

  | ELet (rec_flag, patexprs, body) ->
      let n, patexprs = subst_patexprs t2 i rec_flag patexprs in
      let body = subst_expr t2 (i + n) body in
      ELet (rec_flag, patexprs, body)

  | EFun (vars, args, return_type, body) ->
      let i = i + List.length vars in
      let args = List.map (subst t2 i) args in
      let return_type = subst t2 i return_type in
      let body = subst_expr t2 i body in
      EFun (vars, args, return_type, body)

  | EAssign (e1, field, e2) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      EAssign (e1, field, e2)

  | EApply (f, args) ->
      let f = subst_expr t2 i f in
      let args = List.map (subst_expr t2 i) args in
      EApply (f, args)

  | EMatch (e, patexprs) ->
      let e = subst_expr t2 i e in
      let patexprs = List.map (fun (pat, expr) ->
          let names = collect_pattern pat in
          let n = List.length names in
          pat, subst_expr t2 (i + n) expr
        ) patexprs
      in
      EMatch (e, patexprs)

  | ETuple exprs ->
      let exprs = List.map (subst_expr t2 i) exprs in
      ETuple exprs

  | EConstruct (name, fieldexprs) ->
      let fieldexprs = List.map (fun (field, expr) ->
        field, subst_expr t2 i expr) fieldexprs
      in
      EConstruct (name, fieldexprs)

  | EIfThenElse (e1, e2, e3) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      let e3 = subst_expr t2 i e3 in
      EIfThenElse (e1, e2, e3)

  | ELocated (e, p1, p2) ->
      let e = subst_expr t2 i e in
      ELocated (e, p1, p2)

  | EPlus (e1, e2) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      EPlus (e1, e2)

  | EMinus (e1, e2) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      EMinus (e1, e2)

  | ETimes (e1, e2) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      ETimes (e1, e2)

  | EDiv (e1, e2) ->
      let e1 = subst_expr t2 i e1 in
      let e2 = subst_expr t2 i e2 in
      EDiv (e1, e2)

  | EUMinus e ->
      let e = subst_expr t2 i e in
      EUMinus e

  | EInt _ ->
      e


and subst_decl t2 i d =
  match d with
  | DMultiple (rec_flag, patexprs) ->
      let _n, patexprs = subst_patexprs t2 i rec_flag patexprs in
      DMultiple (rec_flag, patexprs)

  | DLocated (d, p1, p2) ->
      DLocated (subst_decl t2 i d, p1, p2)
;;

let rec esubst_patexprs e2 i rec_flag patexprs =
  let patterns, expressions = List.split patexprs in
  let names = List.fold_left (fun acc p ->
    collect_pattern p :: acc) [] patterns
  in
  let names = List.flatten names in
  let n = List.length names in
  let expressions = match rec_flag with
    | Recursive ->
        List.map (esubst e2 (i + n)) expressions
    | Nonrecursive ->
        List.map (esubst e2 i) expressions
  in
  n, List.combine patterns expressions

(* [esubst e2 i e1] substitutes expression [e2] for index [i] in expression [e1]. *)
and esubst e2 i e1 =
  match e1 with
  | EConstraint (e, t) ->
      let e = esubst e2 i e in
      EConstraint (e, t)

  | EVar index ->
      if i = index then
        e2
      else
        e1

  | EPoint _ ->
      e1

  | ELet (rec_flag, patexprs, body) ->
      let n, patexprs = esubst_patexprs e2 i rec_flag patexprs in
      let body = esubst e2 (i + n) body in
      ELet (rec_flag, patexprs, body)

  | EFun (vars, params, return_type, body) ->
      let n = List.length vars in
      let body = esubst e2 (i + n) body in
      EFun (vars, params, return_type, body)

  | EAssign (e, f, e') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      EAssign (e, f, e')

  | EApply (f, args) ->
      let f = esubst e2 i f in
      let args = List.map (esubst e2 i) args in
      EApply (f, args)

  | EMatch (e, patexprs) ->
      let e = esubst e2 i e in
      let patexprs = List.map (fun (pat, expr) ->
        let names = collect_pattern pat in
        let n = List.length names in
        let expr = esubst e2 (i + n) expr in
        pat, expr) patexprs
      in
      EMatch (e, patexprs)

  | ETuple exprs ->
      let exprs = List.map (esubst e2 i) exprs in
      ETuple exprs

  | EConstruct (name, fieldexprs) ->
      let fieldexprs = List.map (fun (field, expr) ->
        field, esubst e2 i expr) fieldexprs
      in
      EConstruct (name, fieldexprs)

  | EIfThenElse (e, e', e'') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      let e'' = esubst e2 i e'' in
      EIfThenElse (e, e', e'')


  | ELocated (e, p1, p2) ->
      let e = esubst e2 i e in
      ELocated (e, p1, p2)

  | EPlus (e, e') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      EPlus (e, e')

  | EMinus (e, e') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      EMinus (e, e')

  | ETimes (e, e') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      ETimes (e, e')

  | EDiv (e, e') ->
      let e = esubst e2 i e in
      let e' = esubst e2 i e' in
      EDiv (e, e')

  | EUMinus e ->
      let e = esubst e2 i e in
      EUMinus e

  | EInt _ ->
      e1
;;


(* [bind_patexprs env rec_flag patexprs body] takes a list of patterns and
 * expressions, whose recursivity depends on [rec_flag], collects the variables
 * in the patterns, binds them to new points, and performs the correct
 * substitutions according to the recursivity flag. *)
let bind_patexprs env rec_flag patexprs body =
  let patterns, expressions = List.split patexprs in
  let names = List.fold_left (fun acc p ->
    collect_pattern p :: acc) [] patterns
  in
  let names = List.flatten names in
  let env, points = List.fold_left (fun (env, points) name ->
    let env, point = bind_term env name false in
    env, point :: points) (env, []) names
  in
  (* Trick: keep the list reversed so that the index in the list is also the De
   * Bruijn index. *)
  let perform_all_substitutions expression =
    Hml_List.fold_lefti
      (fun i expr point -> esubst (EPoint point) i expr)
      expression points
  in
  let expressions = match rec_flag with
    | Recursive ->
        List.map perform_all_substitutions expressions
    | Nonrecursive ->
        expressions
  in
  let body = Option.map perform_all_substitutions body in
  env, List.combine patterns expressions, body
;;


let bind_vars (env: env) (vars: type_binding list) =
  (* List kept in reverse, the usual trick *)
  let env, points = List.fold_left (fun (env, points) binding ->
    let env, point = bind_var env binding in
    env, point :: points) (env, []) vars
  in
  let subst_type t =
    Hml_List.fold_lefti (fun i t point -> subst (TyPoint point) i t) t points
  in
  let subst_expr t =
    Hml_List.fold_lefti (fun i t point -> subst_expr (TyPoint point) i t) t points
  in
  env, subst_type, subst_expr
;;


module ExprPrinter = struct

  open Hml_Pprint
  open TypePrinter

  let rec print_patexpr env (pat, expr) =
    print_pat env pat ^^ space ^^ equals ^^ jump (
      print_expr env expr
    )

  and print_patexprs env patexprs =
    join (break1 ^^ string "and" ^^ space) (List.map (print_patexpr env) patexprs)

  and print_pat env = function
    | PConstraint (p, t) ->
        print_pat env p ^^ colon ^^ space ^^ print_type env t

    | PVar v ->
        print_var v

    | PTuple pats ->
        lparen ^^
          join (comma ^^ space) (List.map (print_pat env) pats) ^^
        rparen

    (* Foo { bar = bar; baz = baz; … } *)
    | PConstruct (name, fieldnames) ->
        print_datacon name ^^ space ^^
          if List.length fieldnames > 0 then
            space ^^ lbrace ^^
            nest 4
              (break1 ^^ join
                (semi ^^ break1)
                (List.map (fun (field, name) -> print_field field ^^ space ^^
                  equals ^^ space ^^ print_var name) fieldnames)) ^^
            nest 2 (break1 ^^ rbrace)
          else
            empty

    | PLocated (pat, _, _) ->
        print_pat env pat

  and print_expr env = function
    | EConstraint (e, t) ->
        print_expr env e ^^ colon ^^ space ^^ print_type env t

    | EVar i ->
        int i

    | EPoint point ->
        print_var (get_name env point)

    | ELet (rec_flag, patexprs, body) ->
        let env, patexprs, body = bind_patexprs env rec_flag patexprs (Some body) in
        let body = Option.extract body in
        string "let" ^^ print_rec_flag rec_flag ^^ space ^^
        print_patexprs env patexprs ^^ break1 ^^ string "in" ^^ break1 ^^
        print_expr env body

    (* fun [a] (x: τ): τ -> e *)
    | EFun (vars, args, return_type, body) ->
        let env, subst_type, subst_expr = bind_vars env vars in
        let args = List.map subst_type args in
        let return_type = subst_type return_type in
        let body = subst_expr body in
        string "fun " ^^ lbracket ^^ join (comma ^^ space) (List.map print_binder vars) ^^
        rbracket ^^ nest 2 (
          join break1 (List.map (print_type env) args)
        ) ^^ colon ^^ space ^^ print_type env return_type ^^ space ^^ equals ^^
        nest 2 (print_expr env body)

    (* | EAssign of expression * Field.name * expression

    | EApply of expression * expression list

    | EMatch of expression * (pattern * expression) list

    | ETuple of expression list

    | EConstruct of Datacon.name * (Field.name * expression) list

    | EIfThenElse of expression * expression * expression
    | ELocated of expression * Lexing.position * Lexing.position

    | EPlus of expression * expression
    | EMinus of expression * expression
    | ETimes of expression * expression
    | EDiv of expression * expression
    | EUMinus of expression
    | EInt of int *)

    | _ ->
        assert false

  and print_rec_flag = function
    | Recursive ->
        string " rec"
    | Nonrecursive ->
        empty


  and print_binder (name, kind) =
    print_var name ^^ space ^^ ccolon ^^ print_kind kind


  ;;

end
