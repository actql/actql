///|
test "declaration usage limits retain their meaning from the existing Owner" {
  let identity = local_identity_fixture()
  let inventory = @references.usage_inventory(
    @references.parameter_usage(
      @context.program_reference_values(
        @context.program_sources_references(
          @context.program_identity_sources(identity),
        ),
      ),
    ),
  )
  for (work, expected) in [(0, CompileLimit), (-1, InvalidConfiguration)] {
    guard @references.check_declaration_usage(inventory, max_work=work)
      is Err(issue) else {
      fail("usage admission must retain its actual limit rejection")
    }
    assert_eq(declaration_usage_diagnostic_category(issue), expected)
  }
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
