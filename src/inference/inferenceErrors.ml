open Name

let handle_error print_variable p =
  let fatal pos msg =
    let pos = Positions.([start_of_position pos; end_of_position pos]) in
    Errors.fatal pos msg
  in
  try
    p ()
  with
  | AlphaRename.UnboundVariable (pos, Name x) ->
    fatal pos (Printf.sprintf "  Identifier `%s' is unbound." x)

  | AlphaRename.OverloadedSymbolCannotBeBound (pos, Name x) ->
    fatal pos (Printf.sprintf
                 "  Identifier `%s' cannot be both overloaded and let-bound."
                 x)

  | InferenceExceptions.UnboundTypeVariable (pos, TName x) ->
    fatal pos (Printf.sprintf "  Type variable `%s' is unbound." x)

  | InferenceExceptions.UnboundTypeConstructor (pos, TName x) ->
    fatal pos (Printf.sprintf "  Type constructor `%s' is unbound." x)

  | InferenceExceptions.UnboundTypeIdentifier (pos, TName x) ->
    fatal pos (Printf.sprintf "  Type identifier `%s' is unbound." x)

  | InferenceExceptions.UnboundLabel (pos, LName x) ->
    fatal pos (Printf.sprintf "  Label `%s' is unbound." x)

  | InferenceExceptions.InvalidTypeVariableIdentifier (pos, TName x) ->
    fatal pos (Printf.sprintf "  `%s' is already a type constructor." x)

  | InferenceExceptions.UnboundDataConstructor (pos, DName x) ->
    fatal pos (Printf.sprintf "  Data constructor `%s' is unbound." x)

  | InferenceExceptions.InvalidDataConstructorDefinition (pos, DName x) ->
    fatal pos (Printf.sprintf
                 "  Invalid definition of data constructor `%s'."
                 x)

  | InferenceExceptions.MultipleLabels (pos, LName x) ->
    fatal pos (Printf.sprintf
                 "  Label `%s' appears multiple times in a record." x)

  | InferenceExceptions.NonLinearPattern (pos, Name x) ->
    fatal pos (Printf.sprintf
                 "  Identifier `%s' appears multiple times in a pattern."
                 x)

  | InferenceExceptions.InvalidDisjunctionPattern pos ->
    fatal pos "  Disjunctive patterns must bind the same variables."

  | InferenceExceptions.NotEnoughPatternArgts pos ->
    fatal pos "  Invalid application of a data constructor in a pattern."

  | InferenceExceptions.CannotGeneralize (pos, v) ->
    fatal pos
      (Printf.sprintf
         "  Cannot generalize the type of this term as requested.
         \n   Inferred type: %s"
         (print_variable pos v))

  | InferenceExceptions.NonDistinctVariables (pos, vl) ->
    fatal pos
      (Printf.sprintf
         "  The following type variables are inferred to be equal: `%s'."
         (String.concat " " (List.map (print_variable pos) vl)))

  | InferenceExceptions.KindError pos ->
    fatal pos "  Ill-kinded type."

  | InferenceExceptions.PartialDataConstructorApplication (pos, xa, ga) ->
    fatal pos (Printf.sprintf
                 "  Partial data constructor application
                      (given %d, expecting %d)."
                 ga xa)

  | InferenceExceptions.TypingError pos ->
    fatal pos "  Type error."

  | InferenceExceptions.IncompatibleTypes (pos, v1, v2) ->
    fatal pos (Printf.sprintf
                 "  The following two types are incompatible:\n    %s\n    %s"
                 (print_variable pos v1)
                 (print_variable pos v2))

  | InferenceExceptions.UnboundIdentifier (pos, Name x) ->
    fatal pos (Printf.sprintf
                 "  `%s' is unbound."
                 x)

  | InferenceExceptions.UnboundClass (pos, CName x) ->
    fatal pos (Printf.sprintf
                 "  Class `%s' is unbound."
                 x)

  | InferenceExceptions.MultipleClassDefinitions (pos, CName x) ->
    fatal pos (Printf.sprintf
                 "  Class `%s' is defined several times."
                 x)

  | InferenceExceptions.OverlappingInstances (pos, CName k, TName t) ->
    fatal pos (Printf.sprintf
                 "  Class `%s' has two instances on head symbol `%s'."
                 k t)

  | ExternalizeTypes.RecursiveType pos ->
    fatal pos (Printf.sprintf "  Type error.")

  | InferenceExceptions.IrreduciblePredicate (pos, ps, CName k, v) ->
    let typctx = String.concat ", "
        (List.map (fun (CName k, v) -> k ^ (print_variable pos v)) ps) in
    fatal pos (Printf.sprintf "  Could not deduce [%s %s] from context [%s]"
                 k (print_variable pos v) typctx)

  | InferenceExceptions.NoInstance (pos, CName k, t) ->
    fatal pos (Printf.sprintf "  An instance of class `%s' for `%s' is \
                               required but undefined." k (of_tname t))
