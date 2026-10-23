///|
test "unary TRY_TIMESTAMP uses exact canonical UTC conversion and Timestamp identity" {
  for
    stamp in [
      "1970-01-01T00:00:00.000Z", "1969-12-31T23:59:59.999999999Z", "2000-02-29T00:00:00.123456789Z",
      "9999-12-31T23:59:59.999999999Z",
    ] {
    assert_true(
      run_expr("\"try_timestamp('" + stamp + "')\"")
      is Ok(Captured(@admitted.Timestamp(actual))) &&
      actual == stamp,
    )
    assert_true(
      run_expr("\"try_timestamp(CAST('" + stamp + "' AS TIMESTAMP))\"")
      is Ok(Captured(@admitted.Timestamp(actual))) &&
      actual == stamp,
    )
  }
  for
    bad in [
      "bad", "2001-02-29T00:00:00.000Z", "1970-01-01T00:00:00Z", "1970-01-01T00:00:00.000+00:00",
      "1970-01-01T00:00:00.123000Z", "1970-01-01T00:00:00.1234567890Z", " 1970-01-01T00:00:00.000Z",
    ] {
    assert_true(run_expr("\"try_timestamp('" + bad + "')\"") is Ok(Null))
  }
  assert_true(run_expr("\"try_timestamp(NULL)\"") is Ok(Null))
}

///|
test "unary TRY_TIMESTAMP propagates demanded child and control failures with lazy parents" {
  assert_true(run_expr("\"try_timestamp(CAST(1 / 0 AS STRING))\"") is Err(_))
  assert_true(
    run_expr(
      "\"if(false,try_timestamp(CAST(1 / 0 AS STRING)),try_timestamp(NULL))\"",
    )
    is Ok(Null),
  )
  let root = lowered("\"try_timestamp('bad')\"")
  let workspace = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: 10, max_frames: 20, },
      workspace,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(workspace.live, 0)
  for stop = 0; stop < 4; stop = stop + 1 {
    let execution = start_expression_execution(root, {}, [], 10000, 100, 100).unwrap()
    for _ in 0..<stop {
      assert_true(
        advance_expression_execution(execution) is Ok(ExpressionContinue),
      )
    }
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}
