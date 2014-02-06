(** Typing environment for {!XAST}. *)

open XAST
open Positions
open Name

(** The type of environments. *)
type t

(** [empty] is the environment with no binding. *)
val empty : t

(** [initial] contains the builtin type constructors of {!XAST}. *)
val initial : t

(** [values env] projects [env] as an environment of bindings
    that associate type scheme to value identifiers. *)
val values : t -> (tnames * Types.class_predicates * binding) list

(** [lookup pos x env] returns the binding of [x]. *)
val lookup : position -> name -> t
  -> (tnames * Types.class_predicates * binding)

(** [bind_scheme n ts ty e] associates the scheme [ts. ty] to
    the identifier [n] in [e]. *)
val bind_scheme : position -> name -> tnames -> Types.class_predicates
  -> Types.t -> t -> t

(** [bind_simple n ty e] associates the type [ty] to
    the identifier [n] in [e]. *)
val bind_simple : position -> name -> Types.t  -> t -> t

(** [lookup_type_kind pos t e] returns the kind of [t] in [e]. *)
val lookup_type_kind : position -> tname -> t -> Types.kind

(** [lookup_type_definition pos t e] returns the type definition
    of [t] in [e]. *)
val lookup_type_definition : position -> tname -> t -> type_definition

(** [bind_type t k tdef e] associates a kind [k] and a type definition
    [tdef] to the type identifier [t] in [e]. *)
val bind_type : tname -> Types.kind -> type_definition -> t -> t

(** [bind_type_variable x e] introduces the type variable [x] in [e]. *)
val bind_type_variable : tname -> t -> t

(** [lookup_class pos c e] returns the class_definition of [c] in [e]. *)
val lookup_class : position -> tname -> t -> class_definition

(** [is_superclass pos k1 k2 e] returns [true] if [k2] is a superclass of
    [k1] in [e]. *)
val is_superclass : position -> tname -> tname -> t -> bool

(** [bind_class c cdef e] associates a class_definition [cdef] to [c] in [e]. *)
val bind_class : tname -> class_definition -> t -> t

(** [bind_label pos l ts lty rtycon e] associates the type parameters [ts],
    the type [lty] and the record type constructor [rtycon] to the label [l]
    in [e]. *)
val bind_label : position -> lname -> tnames -> Types.t -> tname -> t -> t

(** [lookup_label pos l e] returns the type parameters, the type and
    the record type constructor of the label [l] in [e]. *)
val lookup_label : position -> lname -> t -> tnames * Types.t * tname

val lookup_method : position -> class_definition -> lname -> Types.t

val add_name : t -> position * name -> t

val bind_instance : instance_definition -> t -> t

val if_canonical_then_return : Types.class_predicates -> t -> position -> (tname * (tname list)) list

(** [is_instance_of pos t k e] raises an exception if t is not an
    instance of k in e *)
val is_instance_of : position -> Types.t -> tname -> t -> unit
