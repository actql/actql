///|
test "public query routing keeps the unary operand and declared parameter" {
  let context = {
    ..test_context(),
    inputs: [],
    parameter_declarations: Some(test_declarations()),
  }
  for format in [Format::Sql, Format::Text] {
    let actual = lower("SELECT +@p AS value", format, Some(context)).unwrap()
    assert_true(actual.program is Some(_))
    assert_true(
      actual.document.contains("\"params\":{\"p\":{\"type\":\"number\"}}"),
    )
    assert_true(
      actual.document.contains("\"negate\":{\"negate\":{\"$param\":\"p\"}}"),
    )
    assert_true(
      lower("SELECT +'text' AS value", format, Some(context))
      is Err(QueryLowering(Expression({ issue: InvalidArguments, .. }))),
    )
  }
}
