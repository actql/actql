///|
test "computed physical diagnostics use full output schema coordinates" {
  let columns = [None, Some(0), None, Some(1)]
  assert_true(
    computed_physical_issue_columns(columns, Cell(7, 1, InvalidPhysicalValue))
    is Cell(7, 3, InvalidPhysicalValue),
  )
  assert_true(
    computed_physical_issue_columns(columns, FieldType(0, TypeMismatch))
    is FieldType(1, TypeMismatch),
  )
  assert_true(
    computed_physical_issue_columns(columns, ShapeMismatch) is ShapeMismatch,
  )
}
