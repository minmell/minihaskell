(**************************************************************************)
(*  Adaptated from:                                                       *)
(*  Mini, a type inference engine based on constraint solving.            *)
(*  Copyright (C) 2006. Fran�ois Pottier, Yann R�gis-Gianas               *)
(*  and Didier R�my.                                                      *)
(*                                                                        *)
(*  This program is free software; you can redistribute it and/or modify  *)
(*  it under the terms of the GNU General Public License as published by  *)
(*  the Free Software Foundation; version 2 of the License.               *)
(*                                                                        *)
(*  This program is distributed in the hope that it will be useful, but   *)
(*  WITHOUT ANY WARRANTY; without even the implied warranty of            *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *)
(*  General Public License for more details.                              *)
(*                                                                        *)
(*  You should have received a copy of the GNU General Public License     *)
(*  along with this program; if not, write to the Free Software           *)
(*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA         *)
(*  02110-1301 USA                                                        *)
(*                                                                        *)
(**************************************************************************)

(** This module is a solver for typing constraints. *)

open Misc
open Name
open Positions
open TypeAlgebra
open InferenceTypes
open MultiEquation
open Positions
open Misc
open Constraint
open Unifier
open MultiEquation
open InferenceExceptions

exception Inconsistency

type tconstraint = Constraint.tconstraint

type typing_context = (cname * variable) list

let rtrue = []
let rconj c = List.flatten c
let rpredicate k c = [(k, c)]

type environment = (typing_context * variable) StringMap.t

let environment_as_list = StringMap.bindings

(** [lookup name env] looks for a definition of [name] within
    the environment [env]. *)
let rec lookup pos name e = try
    StringMap.find name e
  with Not_found ->
    raise (UnboundIdentifier (pos, Name name))

type occurrence = string * position

type type_scheme =
  { universally_qs : variable list  ;
    typing_context : typing_context ;
    inferred_type  : variable       }

type answer = {
  (* Binds a name to:
    * - The typing context supplied by the user
    * - The inferred type *)
  bindings: (string * type_scheme) list;
  instantiations: (occurrence * variable) list;
}

let type_scheme qs tc t =
  { universally_qs = qs ;
    typing_context = tc ;
    inferred_type  = t  }

let empty_answer = {
  bindings = [];
  instantiations = []
}

let new_binding a n t =
  { a with bindings = (n, t) :: a.bindings }

let new_instantiation a n t =
  { a with instantiations = (n, t) :: a.instantiations }

let lookup_binding a n = List.assoc n a.bindings

let lookup_instantiation a i = List.assoc i a.instantiations

(* [generalize] *)

let generalize old_pool young_pool =

  (* We examine the variables in the young pool and sort them by rank
     using a simple bucket sort mechanism. (Recall that every variable
     in the young pool must have rank less than or equal to the pool's
     number.)  These variables are also marked as ``young'', so as to
     be identifiable in constant time. *)

  let young_number =
    number young_pool in

  let sorted =
    Array.create (young_number + 1) [] in

  let young =
    Mark.fresh() in

  List.iter (fun v ->
      let desc = UnionFind.find v in
      desc.mark <- young;
      let rank = desc.rank in
      try
        sorted.(rank) <- v :: sorted.(rank)
      with Invalid_argument _ ->
        (* The invariant is broken. *)
        failwith (Printf.sprintf "Out of bound when generalizing %s/%s"
                    (string_of_int rank)
                    (string_of_int (Array.length sorted)))
    ) (inhabitants young_pool);

  (* Next, we update the ranks of the young variables. One goal is to ensure
     that if [v1] is dominated by [v2], then the rank of [v1] is less than or
     equal to the rank of [v2], or, in other words, that ranks are
     nonincreasing along any path down the structure of terms.  The second
     goal is to ensure that the rank of every young variable is exactly the
     maximum of the ranks of the variables that it dominates, if there are
     any.

     The process consists of several depth-first traversals of the forest
     whose entry points are the young variables. Traversals stop at old
     variables. Roughly speaking, the first goal is achieved on the way
     down, while the second goal is achieved on the way back up.

     During each traversal, every visited variable is marked as such, so as
     to avoid being visited again. To ensure that visiting every variable
     once is enough, traversals whose starting point have lower ranks must
     be performed first. In the absence of cycles, this enforces the
     following invariant: when performing a traversal whose starting point
     has rank [k], every variable marked as visited has rank [k] or less
     already. (In the presence of cycles, this algorithm is incomplete and
     may compute ranks that are slightly higher than necessary.) Conversely,
     every non-visited variable must have rank greater than or equal to
     [k]. This explains why [k] does not need to be updated while going
     down. *)

  let visited =
    Mark.fresh() in

  for k = 0 to young_number do
    let rec traverse v =
      let desc = UnionFind.find v in

      (* If the variable is young and was not visited before, we immediately
         mark it as visited (which is important, since terms may be cyclic).
         If the variable has no structure, we set its rank to [k]. If it has
         some structure, we first traverse its sons, then set its rank to the
         maximum of their ranks. *)

      if Mark.same desc.mark young then begin
        desc.mark <- visited;
        desc.rank <- match desc.structure with
          | Some term ->
            fold (fun son accu ->
                max (traverse son) accu
              ) term IntRank.outermost
          | _ ->
            k
      end

      (* If the variable isn't marked ``young'' or ``visited'', then it must
         be old. Then, we update its rank, but do not pursue the computation
         any further. *)

      else if not (Mark.same desc.mark visited) then begin
        desc.mark <- visited;
        if k < desc.rank then
          desc.rank <- k
      end;

      (* If the variable was visited before, we do nothing. *)

      (* In either case, we return the variable's current (possibly updated)
         rank to the caller, so as to allow the maximum computation above. *)

      desc.rank

    in
    try
      Misc.iter traverse sorted.(k)
    with Invalid_argument _ ->
      (* The invariant is broken. *)
      failwith "Out of bound in traverse"

  done;

  (* The rank of every young variable has now been determined as precisely
     as possible.

     Every young variable that has become an alias for some other (old or
     young) variable is now dropped. We need only keep one representative
     of each equivalence class.

     Every young variable whose rank has become strictly less than the
     current pool's number may be safely turned into an old variable. We do
     so by moving it into the previous pool. In fact, it would be safe to
     move it directly to the pool that corresponds to its rank. However, in
     the current implementation, we do not have all pools at hand, but only
     the previous pool.

     Every young variable whose rank has remained equal to the current
     pool's number becomes universally quantified in the type scheme that is
     being created. We set its rank to [none]. *)

  for k = 0 to young_number - 1 do
    try
      List.iter (fun v ->
          if not (UnionFind.redundant v) then
            register old_pool v
        ) sorted.(k)
    with Invalid_argument _ ->
      (* The invariant is broken. *)
      failwith "Out of bound in young refresh."
  done;

  List.iter (fun v ->
      if not (UnionFind.redundant v) then
        let desc = UnionFind.find v in
        if desc.rank < young_number then
          register old_pool v
        else (
          desc.rank <- IntRank.none;
          if desc.kind = Flexible then desc.kind <- Rigid
        )
    ) sorted.(young_number)


(** [distinct_variables vl] checks that the variables in the list [vl]
    belong to distinct equivalence classes and that their structure is
    [None]. In other words, they do represent distinct (independent)
    variables (as opposed to nonvariable terms). *)
exception DuplicatedMark of Mark.t
let distinct_variables pos vl =
  let m = Mark.fresh() in
  try
    List.iter (fun v ->
        let desc = UnionFind.find v in
        match desc.structure with
        | Some _ ->
          raise (CannotGeneralize (pos, v))
        | _ ->
          if Mark.same desc.mark m then
            raise (DuplicatedMark m);
          desc.mark <- m
      ) vl
  with DuplicatedMark m ->
    let vl' =
      List.filter
        (fun v -> Mark.same (UnionFind.find v).mark m)
        vl
    in
    raise (NonDistinctVariables (pos, vl'))

(** [generic_variables vl] checks that every variable in the list [vl]
    has rank [none]. *)
let generic_variable v =
  let desc = UnionFind.find v in
  IntRank.compare desc.rank IntRank.none = 0

let generic_variables pos vl =
  List.iter (fun v ->
      if not (generic_variable v) then
        raise (CannotGeneralize (pos, v))
    ) vl

(* [solve] *)

let solve env pool c =
  let answer = ref empty_answer in

  (** [given_p] corresponds to the class predicates given
      by the programmer as an annotation:

          let ['b_1 ... 'b_n] [K_1 'c_1, ..., K_m 'c_m] ... = ...

      where c_j's are to be found among b_i's.
      This annotation must *entail* what is inferred for explicitly bound
      type variables.
      (c.f. `test/custom/inference/good/typeclass_annotated_predicate.mlt`
      and `test/custom/inference/bad/typeclass_weak_predicate.mlt`)
      In other words, if the user explicitly binds *some* type variables,
      they have to provide a "sufficiently strong" typing context on *these*
      variables. Otherwise we consider the programmer overlooked something
      and raise an error. No restriction applies to other implicitly added
      variables.
      These annotations overwrite the inferred ones. See in particular
      `test/custom/inference/good/typeclass_annotated_strong_predicate.mlt`
      and the inferred `.mle`. We reproduce it here:

          class K 'a { k : 'a }
          class L 'a { l : 'a -> 'a -> 'a }
          class K 'a, L 'a => Y 'a { y : 'a }

          let ['a] [Y 'a] f : 'a -> 'a = fun x -> l x k

      [f] has type [Y 'a => 'a -> 'a] instead of the more general
      [K 'a, L 'a => 'a -> 'a], which is somewhat different when viewed from
      the point of view of elaboration: one version expects 1 argument,
      the other 2 arguments. (although the first one actually hides the other
      two behind one indirection) *)

  (* There originally was a piece of code which 'canonicalized'
   * class predicates in the output XAST (in inference/externalizeTypes)
   * but that was redundant with this, so we deleted it *)

  (* Called in solve_scheme *)
  let canonicalize pos rqs given_p p =
    let p =
      try
        ConstraintSimplifier.canonicalize pos p
      with
      | ConstraintSimplifier.Unsat (k, t) -> raise (NoInstance (pos, k, t)) in
    let p1, p2 =
      List.partition (fun (_, v) -> List.exists (are_equivalent v) rqs) p in
    let witness = ConstraintSimplifier.entails given_p p1 in
    match witness with
    | None        -> p2
    | Some (k, v) -> raise (IrreduciblePredicate (pos, given_p, k, v))
  in

  let rec solve env pool given_p c =
    let pos = cposition c in
    try
      solve_constraint env pool given_p c
    with Inconsistency -> raise (TypingError pos)

  and solve_constraint env pool given_p = function

    | CTrue p
    | CDump p ->
      rtrue

    | CPredicate (pos, k, ty) ->
      (* Simply return the predicate *)
      let v = chop pool ty in
      [k, v]

    | CEquation (pos, term1, term2) ->
      let t1, t2 = twice (chop pool) term1 term2 in
      unify_terms pos pool t1 t2;
      rtrue

    | CConjunction cl ->
      rconj (List.map (solve env pool given_p) cl)

    | CLet ([ Scheme (_, [], fqs, [], c, _) ], CTrue _) ->
      (* This encodes an existential constraint. In this restricted
         case, there is no need to stop and generalize. The code
         below is only an optimization of the general case. *)
      List.iter (introduce pool) fqs;
      solve env pool given_p c

    | CLet (schemes, c2) ->
      let rs, env' =
        List.fold_left (fun (rs, env') scheme ->
            let (r, env'') = solve_scheme env pool given_p scheme in
            (r :: rs, concat env' env'')
          ) ([], env) schemes
      in
      rconj (solve env' pool given_p c2 :: rs)

    | CInstance (pos, SName name, term) ->
      let ps, t = lookup pos name env in
      let ctys = List.map (fun (k, ty) -> ty) ps in
      begin match instance pool (t :: ctys) with
        | [] -> assert false
        | instance :: itys ->
          let t' = chop pool term in
          answer := new_instantiation !answer (name, pos) t';
          unify_terms pos pool instance t';
          (* The typing context is simply obtained by substitution *)
          List.map2 (fun (k, _) ty -> (k, ty)) ps itys
      end

    | CDisjunction cs ->
      assert false

  and solve_scheme env pool given_p = function

    | Scheme (_, [], [], [], c1, header) ->

      (* There are no quantifiers. In this restricted case,
         there is no need to stop and generalize.
         This is only an optimization of the general case. *)

      let solved_p = solve env pool given_p c1 in
      let henv = StringMap.map (fun (t, _) -> chop pool t) header in
      (solved_p, ([], rtrue, henv))

    | Scheme (pos, rqs, fqs, given_p1, c1, header) ->

      (* The general case. *)

      let pool' = new_pool pool in
      List.iter (introduce pool') rqs;
      List.iter (introduce pool') fqs;
      let header = StringMap.map (fun (t, _) -> chop pool' t) header in
      (* We add the new predicates *)
      let given_ps = given_p1 @ given_p in
      let solved_p = solve env pool' given_ps c1 in
      distinct_variables pos rqs;
      generalize pool pool';
      generic_variables pos rqs;
      let generalized_variables =
        List.filter (fun v ->
            let desc = UnionFind.find v in
            IntRank.compare desc.rank IntRank.none = 0)
          (inhabitants pool') in
      let canon_p = canonicalize pos rqs given_ps solved_p in
      (* Separate predicates depending on whether they have been bound here or
       * higher in the term *)
      let local_p, extern_p =
        List.(partition
                (fun (_, v) ->
                   exists (are_equivalent v) generalized_variables)
                canon_p) in
      let ps = given_p1 @ local_p in
      (extern_p, (generalized_variables, ps, header))

  (* pvt: [partial_type_scheme] above. *)
  and concat env (vs, p, header) =
    StringMap.fold (fun name v env ->
        answer := new_binding !answer name (type_scheme vs p v);
        StringMap.add name (p, v) env
      ) header env

  and unify_terms pos pool t1 t2 =
    try
      unify pos (register pool) t1 t2
    with Unifier.CannotUnify (pos, v1, v2) ->
      raise (IncompatibleTypes (pos, v1, v2))

  in (
    ignore (solve env pool [] c);
    !answer
  )

(** [init] produces a fresh initial state. It consists of an empty
    environment and a fresh, empty pool. *)
let init () =
  StringMap.empty, MultiEquation.init ()

(** The public version of [solve] starts out with an initial state. *)
let solve c =
  let env, pool = init () in
  solve env pool c
