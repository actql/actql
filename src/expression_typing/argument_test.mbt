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

///|
test "the root NULL context retains the checked contract and does not type descendants" {
  let item = @contract.primitive(StringType, nullable=false)
  let context = @contract.array_contract(
    item,
    max_items=Some(2L),
    nullable=false,
  ).unwrap()
  let checked = @expression_typing.check(
    syntax("{\"literal\":null}"),
    env(),
    test_limits(),
    root_null_context=Some(context),
  ).unwrap()
  let contract = @expression_typing.result_type(checked)
  assert_true(contract.nullable)
  assert_true(contract.shape is @contract.Array(_, max_items=Some(2L)))
  assert_true(
    @expression_typing.check(
      syntax("\"coalesce(NULL, NULL)\""),
      env(),
      test_limits(),
      root_null_context=Some(context),
    )
    is Err(_),
  )
  let ordinary = @expression_typing.check(
    syntax("\"8\""),
    env(),
    test_limits(),
    root_null_context=Some(context),
  ).unwrap()
  assert_true(
    @expression_typing.result_type(ordinary).shape is @contract.Number,
  )
}
