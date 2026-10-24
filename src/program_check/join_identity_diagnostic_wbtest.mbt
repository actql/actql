///|
test "missing required join identity is invalid input without masking internal evidence failures" {
  assert_eq(
    closure_diagnostic_category(Joins(MissingStableIdentity(0))),
    InvalidInput,
  )
  assert_eq(
    closure_diagnostic_category(Joins(MissingEvidence(0))),
    UnclassifiedFailure,
  )
  assert_eq(
    closure_diagnostic_category(Joins(ForeignOccurrence(0))),
    UnclassifiedFailure,
  )
  assert_eq(closure_diagnostic_category(Joins(BudgetExceeded)), CompileLimit)
  assert_eq(
    closure_diagnostic_category(Joins(InvalidLimits)),
    InvalidConfiguration,
  )
}
