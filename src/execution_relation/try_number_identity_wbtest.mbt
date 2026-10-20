///|
test "TRY_NUMBER Number identity evaluates the original finite value" {
  for
    (source, expected) in [
      ("1.25", 1.25),
      ("-1", -1.0),
      ("0", 0.0),
      ("9007199254740992", 9007199254740992.0),
    ] {
    assert_true(
      run_expr("\"try_number(" + source + ")\"") is Ok(Number(actual)) &&
      actual == expected,
    )
  }
  assert_true(run_expr("\"try_number(CAST(NULL AS NUMBER))\"") is Ok(Null))
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for invalid in [infinity, -infinity, infinity - infinity] {
    assert_true(
      unary(@lower.TryNumber, Number(invalid)) is Err(ArithmeticFailure),
    )
  }
  assert_true(unary(@lower.TryNumber, Text("1")) is Err(InvalidOperand))
}

///|
test "TRY_NUMBER Number identity retains canonical operation and re-admitted original child" {
  let original = lowered("\"try_number(1.25)\"")
  let machine = @encode.writer(1000, 100, 10)
  @lower.emit_expression(original, machine)
  let expected = "{\"body\":{\"value\":{\"body\":1.25,\"op\":\"literal\"}},\"op\":\"try_number\"}"
  assert_eq(@encode.finish(machine), expected)
  let source = @encode.writer(1000, 100, 10)
  @lower.emit_expression_source(original, source)
  let restored = lowered(@encode.finish(source))
  let second = @encode.writer(1000, 100, 10)
  @lower.emit_expression(restored, second)
  assert_eq(@encode.finish(second), expected)
  assert_true(
    evaluate_expression(restored, Map([]), [], {
      remaining: 1000,
      max_frames: 10,
    })
    is Ok(Number(1.25)),
  )
}

///|
test "TRY_NUMBER Number identity preserves demanded errors and lazy demand" {
  assert_true(
    run_expr("\"try_number(1 / 0)\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr("\"if(false, try_number(1 / 0), 7)\"") is Ok(Number(7.0)),
  )
  let expression = lowered("\"try_number(id)\"")
  assert_true(
    evaluate_expression(expression, Map([]), [], {
      remaining: 1000,
      max_frames: 10,
    })
    is Err({ kind: MissingValue, .. }),
  )
  let workspace = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      expression,
      Map([("id", Number(1.0))]),
      [],
      { remaining: 1, max_frames: 10, },
      workspace,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(workspace.live, 0)
}

///|
test "TRY_NUMBER Number identity cancellation retains input and retires frame workspace" {
  let expression = lowered("\"try_number(id)\"")
  for stop = 0; stop < 4; stop = stop + 1 {
    let input : Map[String, Value] = { "id": Number(1.25) }
    let execution = start_expression_execution(
      expression,
      input,
      [],
      10000,
      100,
      100,
    ).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      assert_true(
        advance_expression_execution(execution) is Ok(ExpressionContinue),
      )
    }
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(input.get("id") is Some(Number(1.25)))
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}
