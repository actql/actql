///|
test "binding failure origins follow selected values including default budget failures" {
  let d = declarations("{\"x\":{\"type\":\"string\",\"default\":\"long\"}}")
  for
    (supplied, from_default) in [
      (None, true),
      (Some(cursor("{\"x\":\"long\"}")), false),
    ] {
    match @parameter_binding.bind(d, supplied, values_limit(text=1)) {
      Err(
        @parameter_binding.BindingInput(
          actual,
          @parameter_binding.ParameterIssue(
            @parameter_binding.BudgetExceeded,
            path~,
            ..
          )
        )
      ) => {
        assert_true(
          if from_default {
            actual is Default
          } else {
            actual is Supplied
          },
        )
        assert_eq(
          path,
          if from_default {
            [@source.Key("x"), @source.Key("default")]
          } else {
            [@source.Key("x")]
          },
        )
      }
      _ => fail("expected an origin-bearing budget failure")
    }
  }
  assert_true(
    @parameter_binding.bind(d, Some(cursor("[]")), values_limit())
    is Err(
      @parameter_binding.BindingInput(Supplied, @parameter_binding.Decode(_))
    ),
  )
  assert_true(
    @parameter_binding.bind(d, None, values_limit(nodes=-1))
    is Err(@parameter_binding.InvalidLimits),
  )
}
