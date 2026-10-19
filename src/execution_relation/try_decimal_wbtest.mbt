///|
fn try_decimal_expression() -> @lower.Expression raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"input\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"input\":\"not-a-decimal\"}]},\"as\":\"seed\"},{\"derive\":{\"amount\":{\"try_decimal\":{\"value\":{\"field\":\"input\"},\"precision\":4,\"scale\":2}}}}]",
  )
  match
    @lower.lower_expression(owner, 1, 0, {
      max_nodes: 100,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    }) {
    Ok(expression) => expression
    Err({ kind: @lower.ExpressionNotImplemented(tag), .. }) =>
      fail("ExpressionNotImplemented: " + tag)
    Err(_) => fail("original checked TRY_DECIMAL was refused")
  }
}

///|
test "try_decimal evaluates the original checked conversion without swallowing errors" {
  let expression = try_decimal_expression()
  assert_true(
    evaluate_expression(
      expression,
      Map([("input", Text("not-a-decimal"))]),
      [],
      { remaining: 1000, max_frames: 20, },
    ).unwrap()
    is Null,
  )
}

///|
test "try_decimal preserves exact CAST domains and rejects unrepresentable inputs as NULL" {
  for (source, expected) in [("12.3", "1230"), ("-0.01", "-1"), ("0", "0")] {
    assert_true(
      run_expr("\"try_decimal('" + source + "', 6, 2)\"")
      is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == expected &&
      d.precision == 6 &&
      d.scale == 2,
    )
  }
  for
    source in ["-0", "-0.00", "1.000", "1e2", "10000", "+1", "01", " 1", "bad"] {
    assert_true(run_expr("\"try_decimal('" + source + "', 6, 2)\"") is Ok(Null))
    assert_true(
      run_expr("\"CAST('" + source + "' AS DECIMAL(6,2))\"") is Err(_),
    )
  }
  assert_true(
    run_expr("\"try_decimal(12,6,2)\"") is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "1200",
  )
  for value in ["1.5", "9007199254740992"] {
    assert_true(run_expr("\"try_decimal(" + value + ",38,2)\"") is Ok(Null))
  }
  assert_true(
    run_expr("\"try_decimal(CAST('1.20' AS DECIMAL(6,2)),4,1)\"")
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "12",
  )
  assert_true(
    run_expr("\"try_decimal(CAST('1.21' AS DECIMAL(6,2)),4,1)\"") is Ok(Null),
  )
  assert_true(run_expr("\"try_decimal(NULL,4,2)\"") is Ok(Null))
}

///|
test "try_decimal never swallows child or control failures" {
  assert_true(run_expr("\"try_decimal(1 / 0,4,2)\"") is Err(_))
  let expression = try_decimal_expression()
  assert_true(
    evaluate_expression(expression, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    })
    is Err({ kind: MissingValue, .. }),
  )
  let workspace = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      expression,
      Map([("input", Text("bad"))]),
      [],
      { remaining: 10, max_frames: 20, },
      workspace,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(workspace.live, 0)
  assert_true(
    run_expr("\"if(false, try_decimal(1 / 0,4,2), CAST('2' AS DECIMAL(4,2)))\"")
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "200",
  )
}

///|
test "try_decimal cancellation retains original input and releases temporary frame slots" {
  let root = try_decimal_expression()
  for stop = 0; stop < 4; stop = stop + 1 {
    let input : Map[String, Value] = { "input": Text("bad") }
    let execution = start_expression_execution(root, input, [], 10000, 100, 100).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      assert_true(
        advance_expression_execution(execution) is Ok(ExpressionContinue),
      )
    }
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(input.get("input") is Some(Text("bad")))
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}
