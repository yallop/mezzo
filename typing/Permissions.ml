(* There are useful comments in the corresponding .mli *)

open Types
open Utils

(* -------------------------------------------------------------------------- *)

let add_hint hint str =
  match hint with
  | Some (Auto n)
  | Some (User n) ->
      Some (Auto (Variable.register (Variable.print n ^ "_" ^ str)))
  | None ->
      None
;;

type refined_type = Both | One of typ

exception Inconsistent

(** [can_merge env t1 p2] tells whether, assuming that [t2] is a flexible
    variable, it can be safely merged with [t1]. This function checks that the
    facts are compatible. *)
let can_merge (env: env) (t1: typ) (p2: point): bool =
  Log.check (is_flexible env p2) "[can_merge] takes a flexible variable as its second parameter";
  match t1 with
  | TyPoint p1 ->
      if (is_type env p2) then begin
        Log.check (get_kind env p1 = get_kind env p2) "Wait, what?";
        let f1, f2 = get_fact env p1, get_fact env p2 in
        fact_leq f1 f2
      end else if (is_term env p2) then begin
        (* TODO check for [ghost] here? *)
        true
      end else
        true
  | _ ->
      let f2 = get_fact env p2 in
      let f1 = FactInference.analyze_type env t1 in
      fact_leq f1 f2
;;

(** [collect t] recursively walks down a type with kind TYPE, extracts all
    the permissions that appear into it (as tuple or record components), and
    returns the type without permissions as well as a list of types with kind
    PERM, which represents all the permissions that were just extracted. *)
let collect (t: typ): typ * typ list =
  let rec collect (t: typ): typ * typ list =
    match t with
    | TyUnknown
    | TyDynamic

    | TyVar _
    | TyPoint _

    | TyForall _
    | TyExists _
    | TyApp _

    | TySingleton _

    | TyArrow _ ->
        t, []

    (* Interesting stuff happens for structural types only *)
    | TyBar (t, p) ->
        let t, t_perms = collect t in
        let p, p_perms = collect p in
        t, p :: t_perms @ p_perms

    | TyTuple ts ->
        let ts, permissions = List.split (List.map collect ts) in
        let permissions = List.flatten permissions in
        TyTuple ts, permissions

    | TyConcreteUnfolded (datacon, fields) ->
        let permissions, values = List.partition
          (function FieldPermission _ -> true | FieldValue _ -> false)
          fields
        in
        let permissions = List.map (function
          | FieldPermission p -> p
          | _ -> assert false) permissions
        in
        let sub_permissions, values =
         List.fold_left (fun (collected_perms, reversed_values) ->
            function
              | FieldValue (name, value) ->
                  let value, permissions = collect value in
                  permissions :: collected_perms, (FieldValue (name, value)) :: reversed_values
              | _ ->
                  assert false)
            ([],[])
            values
        in
        TyConcreteUnfolded (datacon, List.rev values), List.flatten (permissions :: sub_permissions)

    | TyAnchoredPermission (x, t) ->
        let t, t_perms = collect t in
        TyAnchoredPermission (x, t), t_perms

    | TyEmpty ->
        TyEmpty, []

    | TyStar (p, q) ->
        let p, p_perms = collect p in
        let q, q_perms = collect q in
        TyStar (p, q), p_perms @ q_perms
  in
  collect t
;;


(** [unfold env t] returns [env, t] where [t] has been unfolded, which
    potentially led us into adding new points to [env]. The [hint] serves when
    making up names for intermediary variables. *)
let rec unfold (env: env) ?(hint: name option) (t: typ): env * typ =
  (* This auxiliary function takes care of inserting an indirection if needed,
   * that is, a [=foo] type with [foo] being a newly-allocated [point]. *)
  let insert_point (env: env) ?(hint: name option) (t: typ): env * typ =
    let hint = Option.map_none (Auto (Variable.register (fresh_name "t_"))) hint in
    match t with
    | TySingleton _ ->
        env, t
    | _ ->
        (* The [expr_binder] also serves as the binder for the corresponding
         * TERM type variable. *)
        let env, p = bind_term env hint env.location false in
        (* This will take care of unfolding where necessary. *)
        let env = add env p t in
        env, TySingleton (TyPoint p)
  in

  let rec unfold (env: env) ?(hint: name option) (t: typ): env * typ =
    match t with
    | TyUnknown
    | TyDynamic
    | TyPoint _
    | TySingleton _
    | TyArrow _
    | TyEmpty ->
        env, t

    | TyVar _ ->
        Log.error "No unbound variables allowed here"

    (* TEMPORARY it's unclear what we should do w.r.t. quantifiers... *)
    | TyForall _
    | TyExists _ ->
        env, t

    | TyStar (p, q) ->
        let env, p = unfold env ?hint p in
        let env, q = unfold env ?hint q in
        env, TyStar (p, q)

    | TyBar (t, p) ->
        let env, t = unfold env ?hint t in
        let env, p = unfold env ?hint p in
        env, TyBar (t, p)

    | TyAnchoredPermission (x, t) ->
        let env, t = unfold env ?hint t in
        env, TyAnchoredPermission (x, t)

    (* If this is the application of a data type that only has one branch, we
     * know how to unfold this. Otherwise, we don't! *)
    | TyApp _ ->
      begin
        let cons, args = flatten_tyapp t in
        match cons with
        | TyPoint p ->
          begin
            match get_definition env p with
            | Some (Some (_, [branch]), _) ->
                let branch = instantiate_branch branch args in
                let t = TyConcreteUnfolded branch in
                unfold env ?hint t
            | _ ->
              env, t
          end
        | _ ->
            Log.error "The head of a type application should be a type variable."
      end

    (* We're only interested in unfolding structural types. *)
    | TyTuple components ->
        let env, components = Hml_List.fold_lefti (fun i (env, components) component ->
          let hint = add_hint hint (string_of_int i) in
          let env, component = insert_point env ?hint component in
          env, component :: components
        ) (env, []) components in
        env, TyTuple (List.rev components)

    | TyConcreteUnfolded (datacon, fields) ->
        let env, fields = List.fold_left (fun (env, fields) -> function
          | FieldPermission _ as field ->
              env, field :: fields
          | FieldValue (name, field) ->
              let hint =
                add_hint hint (Hml_String.bsprintf "%a_%a" Datacon.p datacon Field.p name)
              in
              let env, field = insert_point env ?hint field in
              env, FieldValue (name, field) :: fields
        ) (env, []) fields
        in
        env, TyConcreteUnfolded (datacon, List.rev fields)

  in
  unfold env ?hint t


(** [refine_type env t1 t2] tries, given [t1], to turn it into something more
    precise using [t2]. It returns [Both] if both types are to be kept, or [One
    t3] if [t1] and [t2] can be combined into a more precise [t3].

    The order of the arguments does not matter: [refine_type env t1 t2] is equal
    to [refine_type env t2 t1]. *)
and refine_type (env: env) (t1: typ) (t2: typ): env * refined_type =
  (* TEMPORARY find a better name for that function; what it means is « someone else can view this
   * type » *)
  let views t =
    match t with
    | TyApp _ ->
        let cons, _ = flatten_tyapp t in
        has_definition env !!cons
    | TyConcreteUnfolded _
    | TyArrow _
    | TyTuple _ ->
        true
    | _ ->
        false
  in

  let f1 = FactInference.analyze_type env t1 in
  let f2 = FactInference.analyze_type env t2 in

  (* Small wrapper that makes sure we only return one permission if the two
   * original ones were duplicable. *)
  let one_if t =
    if f1 = Duplicable [||] then begin
      Log.check (f1 = f2) "Two equal types should have equal facts";
      One t
    end else
      Both
  in

  if equal env t1 t2 then begin
    env, one_if t1

  end else begin
    try

      (* Having two exclusive permissions on the same point means we're duplicating an *exclusive*
       * access right to the heap. *)
      if f1 = Exclusive && f2 = Exclusive then
        raise Inconsistent;

      (* Exclusive means we're the only one « seeing » this type; if someone else can see the type,
       * we're inconsistent too. Having [t1] exclusive and [t2 = TyAbstract] is not a problem: [t2]
       * could be a hidden [TyDynamic], for instance. *)
      if f1 = Exclusive && views t2 || f2 = Exclusive && views t1 then
        raise Inconsistent;

      match t1, t2 with
      | TyApp _, TyApp _ ->
          (* Type applications. This covers the following cases:
             - abstract vs abstract
             - concrete vs concrete (NOT unfolded)
             - concrete vs abstract *)
          let cons1, args1 = flatten_tyapp t1 in
          let cons2, args2 = flatten_tyapp t2 in

          if same env !!cons1 !!cons2 && List.for_all2 (equal env) args1 args2 then
            env, one_if t1
          else
            env, Both

      | TyConcreteUnfolded branch as t, other
      | other, (TyConcreteUnfolded branch as t) ->
          (* Unfolded concrete types. This covers:
             - unfolded vs unfolded,
             - unfolded vs nominal. *)
          begin match other with
          | TyConcreteUnfolded branch' ->
              (* Unfolded vs unfolded *)
              let datacon, fields = branch in
              let datacon', fields' = branch' in

              if Datacon.equal datacon datacon' then
                (* The names are equal. Both types are unfolded, so recursively unify their fields. *)
                let env = List.fold_left2 (fun env f1 f2 ->
                  match f1, f2 with
                  | FieldValue (name1, t1), FieldValue (name2, t2) ->
                      Log.check (Field.equal name1 name2)
                        "Fields are not in the same order, I thought they were";

                      (* [unify] is responsible for performing the entire job. *)
                      begin match t1, t2 with
                      | TySingleton (TyPoint p1), TySingleton (TyPoint p2) ->
                          unify env p1 p2
                      | _ ->
                          Log.error "The type should've been run through [unfold] before"
                      end

                  | _ ->
                      Log.error "The type should've been run through [collect] before"
                ) env fields fields' in
                env, One t1

              else
                raise Inconsistent

          | TyApp _ ->
              (* Unfolded vs nominal, we transform this into unfolded vs unfolded. *)
              let cons, args = flatten_tyapp other in
              let datacon, _ = branch in

              if same env (DataconMap.find datacon env.type_for_datacon) !!cons then
                let branch' = find_and_instantiate_branch env !!cons datacon args in
                let env, t' = unfold env (TyConcreteUnfolded branch') in
                refine_type env t t'
              else
                (* This is fairly imprecise as well. If both types are concrete
                 * *and* different, this is inconsistent. However, if [other] is
                 * the applicatino of an abstract data type, then of course it is
                 * not inconsistent. *)
                env, Both

          | _ ->
              (* This is fairly imprecise. [TyConcreteUnfolded] vs [TyForall] is
               * of course inconsistent, but [TyConcreteUnfolded] vs [TyPoint]
               * where [TyPoint] is an abstract type is not inconsistent. However,
               * if the [TyPoint] is [int], it definitely is inconsistent. But we
               * have no way to distinguish "base types" and abstract types... *)
              env, Both

          end

      | TyTuple components1, TyTuple components2 ->
          if List.(length components1 <> length components2) then
            raise Inconsistent

          else
            let env = List.fold_left2 (fun env t1 t2 ->
                (* [unify] is responsible for performing the entire job. *)
              begin match t1, t2 with
              | TySingleton (TyPoint p1), TySingleton (TyPoint p2) ->
                  unify env p1 p2
              | _ ->
                  Log.error "The type should've been run through [unfold] before"
              end
            ) env components1 components2 in
            env, One t1

      | TyForall _, _
      | _, TyForall _
      | TyExists _, _
      | _, TyExists _ ->
          (* We don't know how to refine in the presence of quantifiers. We should
           * probably think about it hard and do something very fancy. *)
          env, Both

      | TyAnchoredPermission _, _
      | _, TyAnchoredPermission _
      | TyEmpty, _
      | _, TyEmpty
      | TyStar _, _
      | _, TyStar _ ->
          Log.error "We can only refine types that have kind TYPE."

      | TyUnknown, (_ as t)
      | (_ as t), TyUnknown ->
          env, One t

      | (_ as t), TyPoint p
      | TyPoint p, (_ as t) ->
          begin match structure env p with
          | Some t' ->
              refine_type env t t'
          | None ->
              env, Both
          end

      | _ ->
          env, Both

    with Inconsistent ->

      (* XXX our inconsistency analysis is sub-optimal, see various comments
       * above. *)
      let open TypePrinter in
      Log.debug ~level:4 "Inconsistency detected %a cannot coexist with %a"
        ptype (env, t1) ptype (env, t2);

      (* We could possibly be smarter here, and mark the entire permission soup as
       * being inconsistent. This would allow us to implement some sort of
       * [absurd] construct that asserts that the program point is not reachable. *)
      env, Both

  end


(** [refine env p t] adds [t] to the list of available permissions for [p],
    possibly by refining some of these permissions into more precise ones. *)
and refine (env: env) (point: point) (t': typ): env =
  let permissions = get_permissions env point in
  match t' with
  | TySingleton (TyPoint point') when not (same env point point') ->
      let permissions' = get_permissions env point' in
      let env = merge_left env point point' in
      List.fold_left (fun env t' -> refine env point t') env permissions'
  | _ ->
      let rec refine_list (env, acc) t' = function
        | t :: ts ->
            let env, r = refine_type env t t' in
            begin match r with
            | Both ->
                refine_list (env, (t :: acc)) t' ts
            | One t' ->
                refine_list (env, acc) t' ts
            end
        | [] ->
            env, t' :: acc
      in
      let env, permissions = refine_list (env, []) t' permissions in
      replace_term env point (fun binder -> { binder with permissions })


(** [unify env p1 p2] merges two points, and takes care of dealing with how the
    permissions should be merged. *)
and unify (env: env) (p1: point) (p2: point): env =
  Log.check (is_term env p1 && is_term env p2) "[unify p1 p2] expects [p1] and \
    [p2] to be variables with kind TERM, not TYPE";

  if same env p1 p2 then
    env
  else
    let env =
      List.fold_left (fun env t -> refine env p1 t) env (get_permissions env p2)
    in
    merge_left env p1 p2


(** [add env point t] adds [t] to the list of permissions for [p], performing all
    the necessary legwork. *)
and add (env: env) (point: point) (t: typ): env =
  Log.check (is_term env point) "You can only add permissions to a point that \
    represents a program identifier.";

  (* The point is supposed to represent a term, not a type. If it has a
   * structure, this means that it's a type variable with kind TERM that has
   * been flex'd, then instanciated onto something. We make sure in
   * {Permissions.sub} that we're actually merging, not instanciating, when
   * faced with two [TyPoint]s. *)
  Log.check (not (has_structure env point)) "I don't understand what's happening";

  let hint = get_name env point in

  (* We first perform unfolding, so that constructors with one branch are
   * simplified. *)
  let env, t = unfold env ~hint t in

  (* Now we may have more opportunities for collecting permissions. [collect]
   * doesn't go "through" [TyPoint]s but when indirections are inserted via
   * [insert_point], [add] is recursively called, so inner permissions are
   * collected as well. *)
  let t, perms = collect t in
  let env = List.fold_left add_perm env perms in
  refine env point t


(** [add_perm env t] adds a type [t] with kind PERM to [env], returning the new
    environment. *)
and add_perm (env: env) (t: typ): env =
  TypePrinter.(
    Log.debug ~level:4 "[add_perm] %a"
      ptype (env, t));
  match t with
  | TyAnchoredPermission (TyPoint p, t) ->
      add env p t
  | TyStar (p, q) ->
      add_perm (add_perm env p) q
  | TyEmpty ->
      env
  | _ ->
      Log.error "[add_perm] only works with types that have kind PERM"
;;

let (|||) o1 o2 =
  if Option.is_some o1 then o1 else o2
;;


(** [sub env point t] tries to extract [t] from the available permissions for
    [point] and returns, if successful, the resulting environment. *)
let rec sub (env: env) (point: point) (t: typ): env option =
  Log.check (is_term env point) "You can only subtract permissions from a point \
  that represents a program identifier.";

  (* See the explanation in [add]. *)
  Log.check (not (has_structure env point)) "I don't understand what's happening";

  match t with
  | TyUnknown ->
      Some env

  | TyDynamic ->
      if begin
        List.exists
          (FactInference.is_exclusive env)
          (get_permissions env point)
      end then
        Some env
      else
        None

  | _ ->

      (* Get a "clean" type without nested permissions. *)
      let t, perms = collect t in
      let perms = List.flatten (List.map flatten_star perms) in

      (* Start off by subtracting the type without associated permissions. *)
      let env = sub_clean env point t in

      Option.bind env (fun env ->
        (* We use a worklist-based approch, where we try to find a permission that
         * "works". A permission that works is one where the left-side is a point
         * that is not flexible, i.e. a point that hopefully should have more to
         * extract than (=itself). As we go, more flexible variables will be
         * unified, which will make more candidates suitable for subtraction. *)
        let works env = function
          | TyAnchoredPermission (TyPoint x, _) when not (is_flexible env x) ->
              Some ()
          | _ ->
              None
        in
        let state = ref (env, perms) in
        while begin
          let env, worklist = !state in
          match Hml_List.take (works env) worklist with
          | None ->
              false

          | Some (worklist, (perm, ())) ->
              match sub_perm env perm with
              | Some env ->
                  state := (env, worklist);
                  true
              | None ->
                  false
        end do () done;

        let env, worklist = !state in
        if List.length worklist > 0 then
          (* TODO Throw an exception. *)
          None
        else
          Some env
      )


(** [sub_clean env point t] takes a "clean" type [t] (without nested permissions)
    and performs the actual work of extracting [t] from the list of permissions
    for [point]. *)
and sub_clean (env: env) (point: point) (t: typ): env option =
  if (not (is_term env point)) then
    Log.error "[KindCheck] should've checked that for us";

  let permissions = get_permissions env point in
  (* This is part of our heuristic: in case this subtraction operation triggers
   * a unification of a flexible variable (this happens when merging), we want
   * the flexible variable to preferably unify with *not* a singleton type. *)
  let singletons, non_singletons =
    List.partition (function TySingleton _ -> true | _ -> false) permissions
  in
  let permissions = non_singletons @ singletons in

  (* This is a very dumb strategy, that may want further improvements: we just
   * take the first permission that “works”. *)
  let rec traverse (env: env) (seen: typ list) (remaining: typ list): env option =
    match remaining with
    | hd :: remaining ->
        (* Try to extract [t] from [hd]. *)
        begin match sub_type env hd t with
        | Some env ->
            let duplicable = FactInference.is_duplicable env hd in
            TypePrinter.(
              let open Bash in
              Log.debug ~level:4 "%sTaking%s %a out of the permissions for %a \
                (really? %b)"
                colors.yellow colors.default
                ptype (env, hd)
                pvar (get_name env point)
                (not duplicable));
            (* We're taking out [hd] from the list of permissions for [point].
             * Is it something duplicable? *)
            if duplicable then
              Some env
            else
              Some (replace_term env point (fun binder ->
                { binder with permissions = seen @ remaining }))
        | None ->
            traverse env (hd :: seen) remaining
        end

    | [] ->
        (* We haven't found any suitable permission. Fail. *)
        None
  in
  traverse env [] permissions


(** [sub_type env t1 t2] examines [t1] and, if [t1] "provides" [t2], returns
    [Some env] where [env] has been modified accordingly (for instance, by
    unifying some flexible variables); it returns [None] otherwise. *)
and sub_type (env: env) (t1: typ) (t2: typ): env option =
  TypePrinter.(
    Log.debug ~level:4 "[sub_type] %a %s→%s %a"
      ptype (env, t1)
      Bash.colors.Bash.red Bash.colors.Bash.default
      ptype (env, t2));

  if equal env t1 t2 then
    Some env
  else match t1, t2 with
  | _, TyUnknown ->
      Some env

  | TyForall (binding, t1), _ ->
      let env, t1 = bind_var_in_type ~flexible:true env binding t1 in
      sub_type env t1 t2

  | _, TyForall (binding, t2) ->
      (* Typical use-case: Nil vs [a] list a. We're binding this as a *rigid*
       * type variable. *)
      let env, t2 = bind_var_in_type env binding t2 in
      sub_type env t1 t2

  | TyExists (binding, t1), _ ->
      let env, t1 = bind_var_in_type env binding t1 in
      (* TODO collect permissions inside [t1] and add them to the environment!
       * We should probably do something similar for the two cases above
       * although I'm not sure I understand what should happen... *)
      sub_type env t1 t2

  | _, TyExists (binding, t2) ->
      let env, t2 = bind_var_in_type ~flexible:true env binding t2 in
      let t2, perms = collect t2 in
      List.fold_left
        (fun env perm -> (Option.bind env (fun env -> sub_perm env perm)))
        (sub_type env t1 t2)
        perms

  | TyTuple components1, TyTuple components2 ->
      (* We can only subtract a tuple from another one if they have the same
       * length. *)
      if List.length components1 <> List.length components2 then
        None

      (* We assume here that the [t1] is in expanded form, that is, that [t1] is
       * only a tuple of singletons. *)
      else
        List.fold_left2 (fun env c1 c2 ->
          Option.bind env (fun env ->
            match c1 with
            | TySingleton (TyPoint p) ->
                sub_clean env p c2
            | _ ->
                Log.error "All permissions should be in expanded form."
          )
        ) (Some env) components1 components2

  | TyConcreteUnfolded (datacon1, fields1), TyConcreteUnfolded (datacon2, fields2) ->
      if Datacon.equal datacon1 datacon2 then
        List.fold_left2 (fun env f1 f2 ->
          Option.bind env (fun env ->
            match f1 with
            | FieldValue (name1, TySingleton (TyPoint p)) ->
                begin match f2 with
                | FieldValue (name2, t) ->
                    Log.check (Field.equal name1 name2) "Not in order?";
                    sub_clean env p t
                | _ ->
                    Log.error "The type we're trying to extract should've been \
                      cleaned first."
                end
            | _ ->
                Log.error "All permissions should be in expanded form."
          )
        ) (Some env) fields1 fields2

      else
        None

  | TyConcreteUnfolded (datacon1, _), TyApp _ ->
      let cons2, args2 = flatten_tyapp t2 in
      let point1 = DataconMap.find datacon1 env.type_for_datacon in

      if same env point1 !!cons2 then begin
        let branch2 = find_and_instantiate_branch env !!cons2 datacon1 args2 in
        sub_type env t1 (TyConcreteUnfolded branch2)
      end else begin
        None
      end

  | TyConcreteUnfolded (datacon1, _), TyPoint point2 when not (is_flexible env point2) ->
      (* The case where [point2] is flexible is taken into account further down,
       * as we may need to perform a unification. *)
      let point1 = DataconMap.find datacon1 env.type_for_datacon in

      if same env point1 point2 then begin
        let branch2 = find_and_instantiate_branch env point2 datacon1 [] in
        sub_type env t1 (TyConcreteUnfolded branch2)
      end else begin
        None
      end

  | TyApp _, TyApp _ ->
      let cons1, args1 = flatten_tyapp t1 in
      let cons2, args2 = flatten_tyapp t2 in

      if same env !!cons1 !!cons2 then
        Hml_List.fold_left2i
          (fun i env arg1 arg2 ->
            Option.bind env (fun env ->
              match variance env !!cons1 i with
              | Covariant ->
                  sub_type env arg1 arg2
              | Contravariant ->
                  sub_type env arg2 arg1
              | Bivariant ->
                  Some env
              | Invariant ->
                  equal_modulo_flex env arg1 arg2
          ))
          (Some env) args1 args2
      else
        None

  | TySingleton t1, TySingleton t2 ->
      sub_type env t1 t2

  | TyArrow (t1, t2), TyArrow (t'1, t'2) ->
      Option.bind (sub_type env t1 t'1) (fun env ->
        sub_type env t'2 t2)

  | TyBar (t1, p1), TyBar (t2, p2) ->
      Option.bind (sub_type env t1 t2) (fun env ->
        let env = add_perm env p1 in
        sub_perm env p2)

  | _ ->
      compare_modulo_flex env sub_type t1 t2


and try_merge_flex env p t =
  if is_flexible env p && can_merge env t p then
    Some (instantiate_flexible env p t)
  else
    None


and try_merge_point_to_point env p1 p2 =
  if is_flexible env p2 then
    Some (merge_left env p1 p2)
  else
    None

and compare_modulo_flex env k t1 t2 =
  let c = compare_modulo_flex in
  match t1, t2 with
  | TyPoint p1, TyPoint p2 ->
      if same env p1 p2 then
        Some env
      else
        try_merge_point_to_point env p1 p2 ||| try_merge_point_to_point env p2 p1 |||
        Option.bind (structure env p1) (fun t1 -> c env k t1 t2) |||
        Option.bind (structure env p2) (fun t2 -> c env k t1 t2)

  | TyPoint p1, _ ->
      try_merge_flex env p1 t2 |||
      Option.bind (structure env p1) (fun t1 -> c env k t1 t2)

  | _, TyPoint p2 ->
      try_merge_flex env p2 t1 |||
      Option.bind (structure env p2) (fun t2 -> c env k t1 t2)

  | _ ->
      if equal env t1 t2 then
        Some env
      else
        None

and equal_modulo_flex env t1 t2 =
  compare_modulo_flex env equal_modulo_flex t1 t2

(** [sub_perm env t] takes a type [t] with kind PERM, and tries to return the
    environment without the corresponding permission. *)
and sub_perm (env: env) (t: typ): env option =
  TypePrinter.(
    Log.debug ~level:4 "[sub_perm] %a"
      ptype (env, t));

  match t with
  | TyAnchoredPermission (TyPoint p, t) ->
      sub env p t
  | TyStar (p, q) ->
      Option.bind
        (sub_perm env p)
        (fun env -> sub_perm env q)
  | TyEmpty ->
      Some env
  | _ ->
      let open TypePrinter in
      let open Obj in
      if is_block (repr t) then
        Log.debug "%d-th block constructor" (tag (repr t))
      else
        Log.debug "%d-th constant constructor" (magic t);
      Log.error "[sub_perm] the following type does not have kind PERM: %a"
        ptype (env, t)
;;


let full_merge (env: env) (p: point) (p': point): env =
  Log.check (is_term env p && is_term env p') "Only interested in TERMs here.";

  let perms = get_permissions env p' in
  let env = merge_left env p p' in
  List.fold_left (fun env t -> add env p t) env perms
;;

exception NotFoldable

(** [fold env point] tries to find (hopefully) one "main" type for [point], by
    folding back its "main" type [t] into a form that's suitable for one
    thing, and one thing only: printing. *)
let rec fold (env: env) (point: point): typ option =
  let perms = get_permissions env point in
  let perms = List.filter
    (function
      | TySingleton (TyPoint p) when same env p point ->
          false
      | _ ->
          true
    ) perms
  in
  match perms with
  | [] ->
      Some TyUnknown
  | t :: [] ->
      begin try
        Some (fold_type_raw env t)
      with NotFoldable ->
        None
      end
  | _ ->
      None


and fold_type_raw (env: env) (t: typ): typ =
  match t with
  | TyUnknown
  | TyDynamic ->
      t

  | TyVar _ ->
      Log.error "All types should've been opened at that stage"

  | TyPoint _ ->
      t

  | TyForall _
  | TyExists _
  | TyApp _ ->
      t

  | TySingleton (TyPoint p) ->
      begin match fold env p with
      | Some t ->
          t
      | None ->
          raise NotFoldable
      end

  | TyTuple components ->
      TyTuple (List.map (fold_type_raw env) components)

  (* TODO *)
  | TyConcreteUnfolded _ ->
      t

  | TySingleton _ ->
      t

  | TyArrow _ ->
      t

  | TyBar (t, p) ->
      TyBar (fold_type_raw env t, p)

  | TyAnchoredPermission (x, t) ->
      TyAnchoredPermission (x, fold_type_raw env t)

  | TyEmpty ->
      t

  | TyStar _ ->
      Log.error "Huh I don't think we should have that here"

;;

let fold_type env t =
  try
    Some (fold_type_raw env t)
  with NotFoldable ->
    None
;;
