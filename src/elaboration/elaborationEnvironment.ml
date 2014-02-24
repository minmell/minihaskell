open Positions
open Name
open XAST
open Types
open ElaborationExceptions

type t = {
  values        : (tnames * class_predicates * binding) list;
  types         : (tname * (Types.kind * type_definition)) list;
  classes       : (tname * class_definition) list;
  labels        : (lname * (tnames * Types.t * tname)) list;
  v_constraints : (tname * tname list) list;
  instances     : (tname * (instance_definition * name) list) list;
  method_names  : lname list;
  names         : name list;
}

let name_of_lname = function 
  | LName s -> Name s
  | KName _ -> assert false

let empty = { values = []; types = []; classes = []; labels = [];
              method_names = []; names = []; v_constraints = [];
              instances = []}

let values env = env.values

let add_name env (pos, name) = match name with
  | IName _ -> env
  | Name s ->
    if List.mem (LName s) env.method_names
    then raise (VariableIsAMethodName (pos, Name s))
    else { env with names = Name s :: env.names }

let add_methods c env (pos, l, ty) = match l with
  | KName _ -> assert false
  | LName s ->
    if List.mem (LName s) env.method_names then
      raise (MultipleMethods (pos, LName s))
    else if List.mem (Name s) env.names then
      raise (VariableIsAMethodName (pos, Name s))
    else
      { env with method_names = (LName s) :: env.method_names;
                 values = ([c.class_parameter],
                           [ClassPredicate (c.class_name, c.class_parameter)],
                           (Name s,ty))
                          :: env.values}

let is_method x env = List.mem x (env.method_names)

let lookup pos x env =
  try
    List.find (fun (_, _, (x', _)) -> x = x') env.values
  with Not_found -> raise (UnboundIdentifier (pos, x))

let lookup_dictionary env c ty =
  match ty with
  |TyVar(_,n) | TyApp(_,n,_) -> let insts = List.assoc n env.instances in 
    let (_,name) = List.find 
        (fun (x,y)-> x.instance_class_name = c)
        insts in
    name 


let bind_scheme pos x ts pred ty env =
  { env with values = (ts, pred, (x, ty)) :: env.values}

let bind_simple pos x ty env =
  bind_scheme pos x [] [] ty env

let bind_type t kind tdef env =
  { env with types = (t, (kind, tdef)) :: env.types }

let lookup_type pos t env =
  try
    List.assoc t env.types
  with Not_found ->
    raise (UnboundTypeVariable (pos, t))

let lookup_type_kind pos t env =
  fst (lookup_type pos t env)

let lookup_type_definition pos t env =
  snd (lookup_type pos t env)


let lookup_class pos k env =
  try
    List.assoc k env.classes
  with Not_found -> raise (UnboundClass (pos, k))


let lookup_superclasses pos k env =
  (lookup_class pos k env).superclasses

let rec is_superclass pos k1 k2 env =
  let scl = lookup_superclasses pos k1 env in
  List.exists (fun k -> k = k2 || is_superclass pos k k2 env) scl

(* Independence constraint (for all i,j: not (Ki < Kj))
 * Also checks that the superclasses are already defined. *)
let unrelated pos env k1 k2 =
  if is_superclass pos k1 k2 env ||
     is_superclass pos k2 k1 env
  then raise (TheseTwoClassesMustNotBeInTheSameContext (pos, k1, k2))

let assert_independent pos sc env =
  ignore (List.fold_left
            (fun acc k -> List.iter (unrelated pos env k) acc; k :: acc) [] sc)

(* Parameter is the singleton of the free variable of the class *)
let rec check_free_variables name parameter (pos, _, t) =
  match parameter with
  | CName _ -> assert false
  | TName s -> 
    let freeT = free t in
    if not (TS.mem parameter freeT) then
      raise (AmbiguousTypeclass (pos, name))
    else if not (TS.is_empty (TS.remove parameter freeT)) then
      raise (TooFreeTypeVariableTypeclass (pos, name))

let bind_class k c env =
  try
    let pos = c.class_position in
    ignore (lookup_class pos k env);
    raise (AlreadyDefinedClass (pos, k))
  with UnboundClass _ ->
    assert_independent c.class_position c.superclasses env;
    List.iter
      (check_free_variables c.class_name c.class_parameter)
      c.class_members;
    let env = List.fold_left (add_methods c) env c.class_members in
    { env with classes = (k, c) :: env.classes }


let bind_type_variable t env =
  bind_type t KStar (TypeDef (undefined_position, KStar, t, DAlgebraic [])) env

let lookup_label pos l env =
  try
    List.assoc l env.labels
  with Not_found -> raise (UnboundLabel (pos, l))

let bind_label pos l ts ty rtcon env =
  try
    ignore (lookup_label pos l env);
    raise (LabelAlreadyTaken (pos, l))
  with UnboundLabel _ ->
    { env with labels = (l, (ts, ty, rtcon)) :: env.labels }

let initial =
  let primitive_type t k = TypeDef (undefined_position, k, t, DAlgebraic []) in
  List.fold_left
    (fun env (t, k) -> bind_type t k (primitive_type t k) env)
    empty 
    PreludeTypes.types

(*
let lookup_method pos k x =
  try
    let (_, _, t) = List.find (fun (_, y, _) -> x = y) k.class_members in
    t
  with Not_found -> raise (NotAMethodOf (pos, x, k.class_name))
*)

let bind_instance env (t, num) =
  try
    let listinstance = List.assoc t.instance_index env.instances in
    if List.exists
        (fun (x, _) -> x.instance_class_name = t.instance_class_name )
        listinstance
    then raise (OverlappingInstances (t.instance_position,
                                      t.instance_class_name))
    else let instances = List.remove_assoc t.instance_index env.instances in
      { env with instances = (t.instance_index, (t,num) :: listinstance)
                             :: instances }
  with Not_found -> { env with instances = (t.instance_index, [t,num])
                                           :: env.instances}

let lookup_instances env c =
  try
    List.assoc c env.instances
  with Not_found -> []

let add_predicates cstr env pos =
  let rec regroup acc = function
    | [] -> acc
    | ClassPredicate (cn,tn) :: q ->
      try
        let old_class = List.assoc tn acc in
        let new_class = cn :: old_class in
        let acc       = List.remove_assoc tn acc in
        regroup ((tn, new_class) :: acc) q
      with Not_found -> regroup ((tn, [cn]) :: acc) q in
  let is_canonical (cs : tname list) =
    List.for_all
      (fun name ->
         not (List.exists (fun y-> y = name || is_superclass pos y name env)
                (List.filter (fun x -> not (x == name)) cs)))
      cs in
  let constr = regroup [] cstr in
  let all_canonical = List.for_all (fun (_, b) -> is_canonical b) constr in
  if all_canonical
  then { env with v_constraints = constr @ env.v_constraints }
  else raise (NotCanonicalConstraint pos)

let add_predicates' ps env =
  { env with instances = ps @ env.instances }

let add_unconstrained_tv ts env ps =
  List.fold_left
    (fun x l ->
       if List.exists (fun (ClassPredicate(k,v)) -> v = l) ps
       then x
       else { x with v_constraints = (l, []) :: x.v_constraints })
    env
    ts


let lookup_constraints tv env =
  try
    List.assoc tv env.v_constraints
  with Not_found -> assert false

let rec is_instance_of pos t k env = match t with
  | TyVar (_, v) ->
    let cs = lookup_constraints v env in
    if not (List.exists (fun k' -> k = k' || is_superclass pos k' k env) cs)
    then raise (NotAnInstance (pos, k, t))
  | TyApp (_, g, ts) ->
    try
      let is = List.assoc g env.instances in
      let (i, _) = List.find (fun (i, _) -> i.instance_class_name = k) is in
      let assoc = List.combine i.instance_parameters ts in
      List.iter
        (fun (ClassPredicate (k, v)) ->
           is_instance_of pos (List.assoc v assoc) k env)
        i.instance_typing_context;
    with Not_found -> raise (NotAnInstance (pos, k, t))

