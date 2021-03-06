open ElaborationExceptions
open Name
open Errors

let string_of_type ty      = ASTio.(XAST.(to_string pprint_ml_type ty))
let string_of_kind k       = ASTio.(XAST.(to_string pprint_ml_kind k))

let handle_error f =
  try
    f ()
  with
  | CannotElaborateDictionary (pos, ty) ->
    fatal' pos (Printf.sprintf
                  "  Cannot elaborate a dictionary of type %s."
                  (string_of_type ty))

  | UnboundIdentifier (pos, Name x) ->
    fatal' pos (Printf.sprintf
                  "  Identifier `%s' is unbound."
                  x)

  | UnboundTypeVariable (pos, TName x) ->
    fatal' pos (Printf.sprintf
                  "  Type `%s' is unbound."
                  x)

  | UnboundClass (pos, CName x) ->
    fatal' pos (Printf.sprintf
                  "  Class `%s' is unbound."
                  x)

  | UnboundLabel (pos, l) ->
    fatal' pos (Printf.sprintf
                  "  Label `%s' is unbound."
                  (of_lname l))

  | OverlappingInstances (pos, CName s) ->
    fatal' pos (Printf.sprintf
                  "  This instance of class `%s' overlaps with another one."
                  s)

  | AlreadyDefinedClass (pos, CName x) ->
    fatal' pos (Printf.sprintf
                  "  Class `%s' is already defined."
                  x)

  | NonLinearPattern pos ->
    fatal' pos "  This pattern is not linear."

  | InvalidTypeApplication pos ->
    fatal' pos "  Invalid type application."

  | IncompatibleTypes (pos, ty1, ty2) ->
    fatal' pos (Printf.sprintf
                  "  The following types are incompatible:\n  %s\n  %s"
                  (string_of_type ty1)
                  (string_of_type ty2))

  | IncompatibleKinds (pos, k1, k2) ->
    fatal' pos (Printf.sprintf
                  "  The following kinds are incompatible:\n  %s\n  %s"
                  (string_of_kind k1)
                  (string_of_kind k2))

  | RecordExpected (pos, ty) ->
    fatal' pos (Printf.sprintf
                  "  The following type is not a record:\n  %s\n"
                  (string_of_type ty))

  | ApplicationToNonFunctional pos ->
    fatal' pos "  The left-hand side of this application is not a function."

  | PatternsMustBindSameVariables pos ->
    fatal' pos "  The following subpatterns must bind the same variables."

  | InvalidDataConstructorApplication pos ->
    fatal' pos "  Bad number of arguments."

  | IllKindedType pos ->
    fatal' pos "  Ill-kinded type."

  | ValueRestriction pos ->
    fatal' pos "  Only value forms can be polymorphic."

  | InvalidOverloading pos ->
    fatal' pos "  Invalid overloading."

  | InvalidNumberOfTypeAbstraction pos ->
    fatal' pos "  Invalid number of type abstractions."

  | TheseTwoClassesMustNotBeInTheSameContext (pos, CName k1, CName k2) ->
    fatal' pos (Printf.sprintf
                  "  The classes `%s' and '%s' cannot be used \
                   with the same parameter in a context."
                  k1 k2)

  | OnlyLetsCanIntroduceTypeAbstraction pos ->
    fatal' pos "  Only let bindings can introduce type abstractions."

  | SameNameInTypeAbstractionAndScheme pos ->
    fatal' pos "  The same names must be used to denote type parameters \n  \
                in the type scheme and in the type abstractions of \n  \
                let bindings."

  | LabelAlreadyTaken (pos, LName l) ->
    fatal' pos (Printf.sprintf
                  "  The label `%s' is already used by another record type."
                  l)

  | LabelDoesNotBelong (pos, LName l, TName ir, TName xr) ->
    fatal' pos (Printf.sprintf
                  "  The label `%s' belongs to `%s', not `%s'."
                  l xr ir)

  | InvalidRecordInstantiation pos ->
    fatal' pos "  Invalid record instantiation."

  | MultipleLabels (pos, LName l) ->
    fatal' pos (Printf.sprintf "  Multiple definitions of label `%s'." l)

  | VariableIsAMethodName (pos, Name x) ->
    fatal' pos (Printf.sprintf "  Identifier `%s' is used both as \
                                a variable and a method name." x)

  | AmbiguousTypeclass(pos, CName l) ->
    fatal' pos (Printf.sprintf "  The parameter of the type class `%s' doesn't \
                                occur in the definition." l)

  | NotAMethodOf (pos, MName m, CName k) ->
    fatal' pos (Printf.sprintf "  `%s' is not a method of class `%s'." m k)

  | MultipleMethods (pos, LName l) ->
    fatal' pos (Printf.sprintf "  `%s' is declared twice as a method." l)

  | LackingMethod (pos, CName k, LName l) ->
    fatal' pos (Printf.sprintf "  Instance of `%s' lacks method `%s'." k l)

  | TooManyMethods (pos, CName k) ->
    fatal' pos (Printf.sprintf "  Instance of `%s' \
                                contains too many methods." k)

  | NotAnInstance (pos, CName k, ty, CName k', t) ->
    let detail = match t with
      | Misc.Left (TName s) ->
        Printf.sprintf
          "  No instance of class `%s' declared for constructor `%s'." k' s
      | Misc.Right (TName s) ->
        Printf.sprintf
          "  Could not deduce `%s %s'." k' s
      | _ -> assert false
    in
    fatal' pos (Printf.sprintf
                  "  Type\n  %s\n  is not an instance of class `%s'.\n%s"
                  (string_of_type ty) k detail)

  | NotCanonicalConstraint(pos)  ->
    fatal' pos (Printf.sprintf "  Not a canonical form.")

  | NotImplemented (pos, str) ->
    fatal' pos (Printf.sprintf "  Not implemented: `%s'." str)

  | InvalidRecordConstruction pos ->
    fatal' pos "  Invalid record construction (not the right set of fields)."

  | OverloadedSymbolCannotBeBound (pos, Name x) ->
    fatal' pos (Printf.sprintf
                  "  Identifier `%s' cannot be both overloaded and let-bound."
                  x)
