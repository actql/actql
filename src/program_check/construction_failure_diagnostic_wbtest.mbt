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

///|
test "request diagnostics retain original failures without execution or location proofs" {
  let issues : Array[@sourceviews.RequestFormIssue] = [
    InvalidLimits,
    WorkLimit,
    PartialCorrelation,
    ForeignRequests,
  ]
  let categories = [
    InvalidConfiguration,
    CompileLimit,
    InvalidInput,
    UnclassifiedFailure,
  ]
  for index, issue in issues {
    let projected = source_request_form_diagnostic(issue)
    assert_true(
      diagnostic_cause(projected) is Source(RequestForm(original)) &&
      original == issue,
    )
    assert_eq(diagnostic_category(projected), categories[index])
    assert_true(diagnostic_location(projected) is None)
    guard rejected(diagnostic_cause(projected)) is Rejected(original) else {
      fail("a request form failure cannot become an execution proof")
    }
    assert_eq(diagnostic_category(original), categories[index])
  }
}
