///|
test "declaration usage limits retain their meaning through Source identity" {
  for (cause, expected) in [
    (Source(Identity(References(Usage(WorkLimit)))), CompileLimit),
    (Source(Identity(References(Usage(InvalidLimits)))), InvalidConfiguration),
  ] {
    guard rejected(cause) is Rejected(diagnostic) else {
      fail("a usage failure cannot become a missing input request")
    }
    assert_eq(diagnostic_category(diagnostic), expected)
    assert_true(diagnostic_location(diagnostic) is None)
  }
}

///|
test "unused opaque binding classification does not imply frontend support" {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","bindings":{"unused":{"type":"artifact_ref"}},"stages":[{"id":"s","inputs":{},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 100, max_depth: 20, },
      tree: { max_nodes: 100, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000, },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let declaration = @bindings.at(
    @bindings.prepare(program, { max_bindings: 1, max_work: 10000, }).unwrap(),
    0,
  ).unwrap()
  assert_eq(
    source_diagnostic_category(Identity(References(Usage(UnusedBinding(declaration))))),
    InvalidInput,
  )
  // The earlier frontend rejection remains an implementation limitation.
  assert_eq(
    source_diagnostic_category(UnsupportedBindings(@bindings.source(declaration))),
    UnsupportedImplementation,
  )
}

///|
test "Graph query categories retain typed input limits and unknown failures" {
  let cases : Array[(@graph.MatchIssueKind, DiagnosticCategory)] = [
    (Structure(InvalidCount), InvalidInput),
    (Structure(InvalidBody), InvalidInput),
    (Structure(InvalidWeight), InvalidInput),
    (Structure(UnknownParameter("p")), InvalidInput),
    (
      Structure(ContractMismatch(IncompatibleContracts(Unqualified("id"), []))),
      InvalidInput,
    ),
    (Structure(ContractMismatch(InvalidBody)), UnclassifiedFailure),
    (Decode(MissingField), InvalidInput),
    (UnknownField("missing"), InvalidInput),
    (UntypedField("missing"), InvalidInput),
    (ExpectedBoolean, InvalidInput),
    (Typing(UnknownParameter("p")), InvalidInput),
    (Value(WrongType), InvalidInput),
    (Structure(InvalidLimits), InvalidConfiguration),
    (Typing(InvalidLimits), InvalidConfiguration),
    (Value(InvalidLimits), InvalidConfiguration),
    (Structure(BudgetExceeded), CompileLimit),
    (Typing(BudgetExceeded), CompileLimit),
    (Value(BudgetExceeded), CompileLimit),
    (Value(UnsupportedReference), UnsupportedImplementation),
    (Structure(IncompleteGraph), UnclassifiedFailure),
    (Typing(InvalidScope("internal")), UnclassifiedFailure),
  ]
  for (kind, expected) in cases {
    assert_eq(graph_match_diagnostic_category(kind), expected)
  }
}

///|
test "diagnostic categories preserve limit meaning across preparation wrappers" {
  let failures : Array[LocalConstructionFailure] = [
    Environment(BudgetExceeded),
    Source(DeclarationWorkLimit),
    Closure(BudgetExceeded),
    Closure(Values(BudgetExceeded)),
    Closure(Contracts(BudgetExceeded)),
    Units(BudgetExceeded),
    Units(Encoding(OutputLimit)),
    Units(ProofConversion(@encode.OutputLimit)),
    Units(ProofConversion(UnitBuildFailure::BudgetExceeded)),
    Units(
      ProofConversion(UnitBuildFailure::ProofConversion(@encode.OutputLimit)),
    ),
    Units(PublicationHost(BudgetExceeded)),
    Units(PublicationWire(BudgetExceeded)),
    Units(PublicationArithmetic(ClosureBudgetExceeded)),
    Closure(Values(Rows(0, Encoding(OutputLimit)))),
    Closure(Values(Rows(0, Admission(BudgetExceeded)))),
    Closure(Values(Wire(0, Limit(Arithmetic(ClosureBudgetExceeded))))),
    Closure(Values(Recursive(0, Measurement(Encoding(OutputLimit))))),
  ]
  for cause in failures {
    guard rejected(cause) is Rejected(diagnostic) else {
      fail("rejection became a request")
    }
    assert_eq(diagnostic_category(diagnostic), CompileLimit)
  }
  for
    cause in [
      Units(AmbiguousProofInput),
      Units(UnconvertedProofInput),
      Units(ProofConversion(UnitBuildFailure::ForeignOwner)),
      Units(ProofConversion(@encode.InvalidStructure)),
      Units(PublicationHost(IdentityMismatch)),
      Closure(Values(Rows(0, InvalidOwner))),
      Closure(Values(Rows(0, Encoding(InvalidNumber)))),
    ] {
    guard rejected(cause) is Rejected(diagnostic) else {
      fail("internal failure became a request")
    }
    assert_eq(diagnostic_category(diagnostic), UnclassifiedFailure)
    assert_true(diagnostic_location(diagnostic) is None)
  }
}
