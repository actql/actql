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
test "known invalid operation frames retain input classification and typed causes" {
  for
    (start, end) in [
      ("{\"preceding\":{\"$param\":\"n\"}}", "{\"preceding\":2}"),
      ("{\"following\":2}", "{\"following\":{\"$param\":\"n\"}}"),
    ] {
    try {
      ignore(
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          parameters=true,
          supplied=Some(supplied_fixture("{\"n\":1}")),
          analytic_limit=Some(1000),
          producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":" +
            start +
            ",\"end\":" +
            end +
            "},\"functions\":{\"answer\":{\"fn\":\"first_value\",\"expr\":\"value\"}}}},{\"select\":[\"id\",{\"value\":\"answer\"}],\"as\":\"selected\"}",
          producer_result_from="selected",
          extra_step_budget=3,
        ),
      )
      fail("reversed frame produced a checked Program")
    } catch {
      Closure(Operations(Frames(InvalidFrame(_)))) as cause => {
        guard rejected(cause) is Rejected(diagnostic) else {
          fail("frame checking rejection became an input request")
        }
        assert_eq(diagnostic_category(diagnostic), InvalidInput)
        assert_true(
          diagnostic_cause(diagnostic)
          is Closure(Operations(Frames(InvalidFrame(_)))),
        )
        assert_true(diagnostic_location(diagnostic) is None)
      }
      error => raise error
    }
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
    (Structure(UnsupportedGraphOperation), UnsupportedImplementation),
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

///|
test "scalar admission rejects invalid frame parameters before frame closure" {
  for direction in ["preceding", "following"] {
    for supplied in ["0", "-1", "1.5", "9007199254740992"] {
      try {
        ignore(
          local_construction_fixture(
            { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
            through_check=true,
            parameters=true,
            supplied=Some(supplied_fixture("{\"n\":" + supplied + "}")),
            analytic_limit=Some(1000),
            producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":{\"" +
              direction +
              "\":{\"$param\":\"n\"}},\"end\":{\"" +
              direction +
              "\":2}},\"functions\":{\"answer\":{\"fn\":\"first_value\",\"expr\":\"value\"}}}},{\"select\":[\"id\",{\"value\":\"answer\"}],\"as\":\"selected\"}",
            producer_result_from="selected",
            extra_step_budget=3,
          ),
        )
        fail("invalid scalar value produced a checked Program")
      } catch {
        Closure(
          Operations(
            Scalars(InvalidValue(_, @pipeline.SafeInteger("n", minimum=1L)))
          )
        ) as cause => {
          guard rejected(cause) is Rejected(diagnostic) else {
            fail("scalar input rejection became a request")
          }
          assert_eq(diagnostic_category(diagnostic), InvalidInput)
          assert_true(
            diagnostic_cause(diagnostic)
            is Closure(
              Operations(
                Scalars(InvalidValue(_, @pipeline.SafeInteger("n", minimum=1L)))
              )
            ),
          )
          assert_true(diagnostic_location(diagnostic) is None)
        }
        error => raise error
      }
    }
  }
}
