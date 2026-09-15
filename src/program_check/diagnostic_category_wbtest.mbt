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
