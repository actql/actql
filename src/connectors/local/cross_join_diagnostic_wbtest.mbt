///|
test "cross join preserves control work separately from row and input capacity" {
  assert_true(
    bounded_cross_join_issue(@execution.ControlWorkLimit, 7)
    is @connector.ControlWorkLimit,
  )
  assert_true(
    bounded_cross_join_issue(@execution.Rows(@execution.RowLimit), 7)
    is @connector.Execution(@execution.Rows(7, @execution.RowLimit)),
  )
  assert_true(
    bounded_cross_join_issue(@execution.InputLimit, 7)
    is @connector.Execution(@execution.InputLimit),
  )
}
