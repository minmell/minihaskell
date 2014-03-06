(** Name scopes. *)

(** Program identifiers. *)
type name =
  (* Regular variable name *)
  | Name of string

  (* (class name, id) -> "i_$CLASS_$ID" *)
  | IName of string * int

(** Data constructor identifiers. *)
type dname = DName of string

(** Label identifiers. *)
type lname =
  (* Regular field name *)
  | LName of string

  (* Method name *)
  | MName of string

  (* (superclass, class) -> "s_$SUPER_$CLASS" *)
  | KName of string * string

(** Type identifiers. *)
type tname =
  (* Regular type name (type/type variable) -> "t_$TYPE" *)
  | TName of string

  (* Dictionary type -> "c_$CLASS" *)
  | CName of string
