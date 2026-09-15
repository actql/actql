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
  ]
  for cause in failures {
    guard rejected(cause) is Rejected(diagnostic) else {
      fail("rejection became a request")
    }
    assert_eq(diagnostic_category(diagnostic), CompileLimit)
  }
  for cause in [Units(AmbiguousProofInput), Units(UnconvertedProofInput)] {
    guard rejected(cause) is Rejected(diagnostic) else {
      fail("internal failure became a request")
    }
    assert_eq(diagnostic_category(diagnostic), UnclassifiedFailure)
    assert_true(diagnostic_location(diagnostic) is None)
  }
}
