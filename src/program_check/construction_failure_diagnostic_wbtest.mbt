///|
test "diagnostic projection retains the original cause and common rejection category" {
  let causes : Array[LocalConstructionFailure] = [
    Source(DeclarationWorkLimit),
    Source(CapacityMetadataBudget),
    InvalidLimits,
    Source(Declarations(@stages.ForeignSteps)),
  ]
  let expected = [
    CompileLimit,
    CompileLimit,
    InvalidConfiguration,
    UnclassifiedFailure,
  ]
  for index, cause in causes {
    let projected = construction_failure_diagnostic(cause)
    guard rejected(cause) is Rejected(original) else {
      fail("a construction diagnostic cannot issue an execution proof")
    }
    assert_eq(diagnostic_category(projected), expected[index])
    assert_eq(diagnostic_category(projected), diagnostic_category(original))
    assert_true(physical_equal(diagnostic_cause(projected), cause))
  }
}
