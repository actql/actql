///|
test "changes state and range are not implicitly converted to runtime support" {
  assert_true(
    check_source_mode_obligation(2, 3, @sourceviews.RuntimeModeSupport) is Ok(_),
  )
  for
    obligation in [
      @sourceviews.BoundedChangesRange,
      @sourceviews.SourceStateRequirement,
    ] {
    assert_true(
      check_source_mode_obligation(2, 3, obligation)
      is Err(Unresolved(2, 3, actual)) &&
      actual == obligation,
    )
  }
}
