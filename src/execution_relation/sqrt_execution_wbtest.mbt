///|
test "sqrt executes independent finite binary64 expression vectors" {
  for
    (source, expected) in [
      ("sqrt(0)", 0.0),
      ("sqrt(1)", 1.0),
      ("sqrt(9)", 3.0),
      ("sqrt(0.25)", 0.5),
      ("sqrt(2.25)", 1.5),
      ("sqrt(2)", 1.4142135623730951),
      ("sqrt(1e300)", 1.0e150),
      ("sqrt(5e-324)", 2.2227587494850775e-162),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Number(actual)) && actual == expected,
      msg=source,
    )
  }
}

///|
test "sqrt obeys independent exact bit boundaries and rejects foreign domains" {
  for
    (input, bits) in [
      (-0.0, 0UL),
      (2.0, 0x3ff6a09e667f3bcdUL),
      (5.0e-324, 0x1e60000000000000UL),
      (1.7976931348623157e308, 0x5fefffffffffffffUL),
    ] {
    guard unary(@lower.Sqrt, Number(input)) is Ok(Number(value)) else {
      fail("finite sqrt input rejected")
    }
    assert_eq(value.reinterpret_as_uint64(), bits)
  }
  assert_true(unary(@lower.Sqrt, Null) is Ok(Null))
  for input in [-1.0, -5.0e-324, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(unary(@lower.Sqrt, Number(input)) is Err(ArithmeticFailure))
  }
  for value in [Boolean(true), Text("4")] {
    assert_true(unary(@lower.Sqrt, value) is Err(InvalidOperand))
  }
  let decimal = @admitted.decimal_from_coefficient("4", 8, 0).unwrap()
  assert_true(unary(@lower.Sqrt, Captured(decimal)) is Err(InvalidOperand))
}

///|
test "sqrt preserves NULL and selected branch demand" {
  assert_true(run_expr("\"sqrt(NULL)\"") is Ok(Null))
  assert_true(run_expr("\"if(FALSE, sqrt(-1), 7)\"") is Ok(Number(7.0)))
  assert_true(
    run_expr("\"sqrt(-1)\"") is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr("\"sqrt(1 / 0)\"") is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "sqrt preserves the demanded failing expression owner" {
  guard run_expr("\"sqrt(-1)\"") is Err(domain) else {
    fail("negative square root must fail")
  }
  assert_true(
    @lower.expression_body(domain.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  guard run_expr("\"sqrt(1 / 0)\"") is Err(operand) else {
    fail("division operand must fail")
  }
  assert_true(
    @lower.expression_body(operand.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
}

///|
test "sqrt uses the existing exact unary control and workspace boundaries" {
  let root = lowered("{\"sqrt\":{\"literal\":9}}")
  for (work, slots, success) in [(4, 1, true), (3, 1, false), (4, 0, false)] {
    let workspace = row_workspace(slots)
    let actual = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 1, },
      workspace,
    )
    if success {
      assert_true(actual is Ok(Number(3.0)))
      assert_eq(workspace.peak, 1)
    } else if work < 4 {
      assert_true(actual is Err({ kind: ControlLimit, .. }))
    } else {
      assert_true(actual is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
  assert_true(
    evaluate_expression(root, {}, [], { remaining: 4, max_frames: 0, })
    is Err({ kind: ControlLimit, .. }),
  )
}

///|
test "sqrt cancellation retains work and releases only owned roots" {
  for stop in [1, 2, 3] {
    let budget = test_logical_budget(10000L, 10000L)
    let borrowed = retain_logical_value(budget, Number(9)).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered("{\"sqrt\":{\"literal\":9}}"),
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      Some(expression_roots(budget, 100)),
    ).unwrap()
    for _ in 0..<stop {
      assert_true(advance_expression_frame(frame).unwrap() is None)
    }
    let consumed = budget.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(budget.work, consumed)
    assert_false(borrowed.released)
    assert_eq((budget.live, workspace.live), (borrowed.bytes, 0))
    release_logical_root(budget, borrowed).unwrap()
    assert_eq(budget.live, 0L)
  }
}
