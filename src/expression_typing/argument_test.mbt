///|
test "fixed argument domains resolve only immediate NULL literals" {
  for
    domain in [
      @expression_typing.NumberArgument,
      BooleanArgument,
      StringArgument,
    ] {
    for text in ["{\"literal\":null}", "\"(NULL)\""] {
      let checked = @expression_typing.check_argument(
        syntax(text),
        env(),
        domain,
        test_limits(),
      ).unwrap()
      assert_true(@expression_typing.result_type(checked).nullable)
    }
    for
      text in [
        "\"coalesce(NULL, NULL)\"", "\"if(TRUE, NULL, NULL)\"", "\"[NULL]\"",
      ] {
      assert_true(
        @expression_typing.check_argument(
          syntax(text),
          env(),
          domain,
          test_limits(),
        )
        is Err(_),
      )
    }
  }
  assert_true(
    @expression_typing.check(syntax("\"NULL\""), env(), test_limits()) is Err(_),
  )
  assert_true(
    @expression_typing.check_argument(
      syntax("\"'1'\""),
      env(),
      NumberArgument,
      test_limits(),
    )
    is Err(_),
  )
  let n = @expression_typing.check_argument(
    syntax("\"1 + 2\""),
    env(),
    NumberArgument,
    test_limits(),
  ).unwrap()
  assert_true(!@expression_typing.result_type(n).nullable)
}
