///|
test "array concat preserves original item order and seals the exact funded result" {
  let source = "{\"array_concat\":[{\"array\":[{\"literal\":\"a\"},{\"literal\":null}]},{\"array\":[]},{\"array\":[{\"literal\":\"\\u0000\"},{\"literal\":\"a\"}]}]}"
  let expression = lowered(source)
  let budget = test_logical_budget(10000L, 10000L)
  let workspace = row_workspace(1000)
  let value = evaluate_expression_with_workspace(
    expression,
    {},
    [],
    { remaining: 1000, max_frames: 100, },
    workspace,
    logical_work=Some(budget),
  ).unwrap()
  assert_eq(object_result_wire(value), "[\"a\",null,\"\\u0000\",\"a\"]")
  assert_eq((budget.live, workspace.live), (0L, 0))
}

///|
test "array concat propagates NULL only after original operands succeed" {
  assert_true(
    run_expr(
      "{\"array_concat\":[{\"literal\":null},{\"array\":[{\"literal\":1}]}]}",
    )
    is Ok(Null),
  )
  assert_true(
    run_expr(
      "{\"array_concat\":[{\"literal\":null},{\"array\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}]}",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "array concat cancellation releases the partial result and leaves caller roots live" {
  let expression = lowered(
    "{\"array_concat\":[{\"array\":[{\"literal\":1},{\"literal\":2}]},{\"array\":[{\"literal\":3}]}]}",
  )
  let budget = test_logical_budget(10000L, 10000L)
  let caller = retain_logical_value(budget, Number(8.0)).unwrap()
  let frame = expression_frame(
    expression,
    {},
    [],
    { remaining: 1000, max_frames: 100, },
    row_workspace(120),
    Some(expression_roots(budget, 120)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<100 {
    assert_true(advance_expression_frame(frame) is Ok(None))
    if frame.state is ArrayConcat(state) && state.item_index == 1 {
      reached = true
      break
    }
  }
  assert_true(reached)
  assert_eq(frame.arrays.length(), 1)
  let charged = budget.work
  close_expression_frame(frame)
  assert_eq((budget.live, frame.workspace.live, budget.work), (1L, 0, charged))
  assert_false(caller.released)
  release_logical_root(budget, caller).unwrap()
}

///|
test "array concat refuses a short simultaneous live allowance before copying" {
  let expression = lowered(
    "{\"array_concat\":[{\"array\":[{\"literal\":1},{\"literal\":2}]},{\"array\":[{\"literal\":3}]}]}",
  )
  // [1,2] and [3] remain retained while their new [1,2,3] backing is funded.
  for limit in [14L, 15L] {
    let budget = test_logical_budget(10000L, limit)
    let workspace = row_workspace(100)
    let result = evaluate_expression_with_workspace(
      expression,
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(budget),
    )
    if limit == 14L {
      assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
    } else {
      assert_eq(object_result_wire(result.unwrap()), "[1,2,3]")
      assert_eq(budget.peak, 15L)
    }
    assert_eq((budget.live, workspace.live), (0L, 0))
  }
}
