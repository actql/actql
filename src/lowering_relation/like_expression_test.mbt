///|
test "LIKE cannot lower from raw bound parameters without the original checked pattern closure" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"matched\":{\"like\":[{\"literal\":\"abc\"},{\"literal\":\"a%\"}]}}}",
  )
  assert_true(
    @lowering_relation.lower_expression(owner, 1, 0, expression_limits())
    is Err({ kind: PendingValidation(PatternValidation("like")), .. }),
  )
}
