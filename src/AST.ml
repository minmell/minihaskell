open Name
open Positions
open Types

module Make (P : Types.TypingSyntax) = struct

  include P

  type program = block list

  and block =
    | BClassDefinition of class_definition
    | BInstanceDefinitions of instance_definition list
    | BTypeDefinitions of type_mutual_definitions
    | BDefinition of value_binding

  and class_definition = {
    class_position  : position;
    class_parameter : tname;
    superclasses    : cname list;
    class_name      : cname;
    class_members   : (position * lname * mltype) list;
  }

  and instance_definition = {
    instance_position       : position;
    instance_parameters     : tname list;
    instance_typing_context : class_predicate list;
    instance_class_name     : cname;
    instance_index          : tname;
    instance_members        : record_binding list;
  }

  and value_binding =
    | BindValue of position * value_definition list
    | BindRecValue of position * value_definition list
    | ExternalValue of position * tnames * explicit_binding * string
    (* "let external" should always be explicitly annotated,
       it is counter-productive in many respects to have to infer
       the type of an external value from its usage in the code. *)

  and type_mutual_definitions =
    | TypeDefs of position * type_definition list

  and expression =

    (** Core ML. *)
    | EVar of position * name * instantiation
    | ELambda of position * binding * expression
    | EApp of position * expression * expression
    | EBinding of position * value_binding * expression
    | EPrimitive of position * primitive

    (** Type abstraction. *)
    | EForall of position * tname list * expression

    (** Type annotations. *)
    | EExists of position * tname list * expression
    | ETypeConstraint of position * expression * mltype

    (** Algebraic datatypes. *)
    | EDCon of position * dname * instantiation * expression list
    | EMatch of position * expression * branch list

    (** Records. *)
    | ERecordAccess of position * expression * lname
    | ERecordCon of position * name * instantiation * record_binding list

  (** Constant. *)
  and primitive =
    | PIntegerConstant of int     (** Integer constant. *)
    | PCharConstant of char       (** Character constant. *)
    | PUnit                       (** Unit constant. *)

  (** Pattern matching branch. *)
  and branch =
    | Branch of position * pattern * expression

  and record_binding =
    | RecordBinding of lname * expression

  and type_definition =
    | TypeDef of position * mltypekind * tname * datatype_definition
    | ExternalType of position * tnames * tname * string

  and datatype_definition =
    | DAlgebraic of (position * dname * tnames * mltype) list
    | DRecordType of tnames * (position * lname * mltype) list

  (** A value definition consists of a list of explicit universal
      quantifiers, a binding, and an expression. *)
  and value_definition =
    | ValueDef of position * tnames * class_predicates * binding * expression

  and pattern =
    | PVar of position * name
    | PWildcard of position
    | PAlias of position * name * pattern
    | PTypeConstraint of position * pattern * mltype
    | PPrimitive of position * primitive
    | PData of position * dname * instantiation * pattern list
    | PAnd of position * pattern list
    | POr of position * pattern list

  and tnames = tname list

  and mltype = Types.t

  and mltypescheme = Types.scheme

  and mltypekind = Types.kind

  and explicit_binding = name * mltype

  let rec is_value_form = function
    | EVar _
    | ELambda _
    | EPrimitive _              ->
      true

    | EDCon (_, _, _, es)       ->
      List.for_all is_value_form es

    | ERecordCon (_, _, _, rbs) ->
      List.for_all (fun (RecordBinding (_, e)) -> is_value_form e) rbs

    | EExists (_, _, t)
    | ETypeConstraint (_, t, _)
    | EForall (_, _, t)         ->
      is_value_form t

    | _                         ->
      false
end

module Generic = Make (struct
    type binding
    let binding _ _ = assert false
    let destruct_binding _ = assert false
    type instantiation
    let instantiation _ _ = assert false
    let destruct_instantiation_as_type_applications _ = assert false
    let destruct_instantiation_as_type_constraint _ = assert false
    let implicit = false
  end)

module type GenericS = module type of Generic
