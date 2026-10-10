///|
// GoogleSQL finite-FLOAT64 expectations are authored from its SIGN contract;
// this is not a claim that the cases were executed by live BigQuery.
test "sign preserves finite number type and exact magnitude-independent results" {
  for
    (input, expected) in [
      (-0.0, 0.0),
      (0.0, 0.0),
      (-2.3, -1.0),
      (2.3, 1.0),
      (-5.0e-324, -1.0),
      (5.0e-324, 1.0),
      (-1.7976931348623157e308, -1.0),
      (1.7976931348623157e308, 1.0),
    ] {
    guard unary(@lower.Sign, Number(input)) is Ok(Number(actual)) else {
      fail("finite SIGN rejected")
    }
    assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
  }
  assert_true(unary(@lower.Sign, Null) is Ok(Null))
  for input in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(unary(@lower.Sign, Number(input)) is Err(InvalidOperand))
  }
  for
    value in [
      Boolean(true),
      Text("4"),
      Captured(@admitted.decimal_from_coefficient("4", 8, 0).unwrap()),
    ] {
    assert_true(unary(@lower.Sign, value) is Err(InvalidOperand))
  }
}

///|
test "sign common expression keeps NULL lazy demand and child failure identity" {
  for
    (source, expected) in [
      ("sign(-9)", -1.0),
      ("sign(0)", 0.0),
      ("sign(9)", 1.0),
      ("sign(-5e-324)", -1.0),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Number(actual)) && actual == expected,
    )
  }
  assert_true(run_expr("\"sign(NULL)\"") is Ok(Null))
  assert_true(run_expr("\"if(FALSE, sign(1 / 0), 7)\"") is Ok(Number(7.0)))
  guard run_expr("\"sign(1 / 0)\"") is Err(issue) else {
    fail("child failure suppressed")
  }
  assert_true(issue.kind is Scalar(ArithmeticFailure))
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
}

///|
test "sign evaluates the child once at exact control and workspace bounds" {
  let root = lowered("{\"sign\":{\"negate\":{\"literal\":9}}}")
  for (work, slots, success) in [(6, 2, true), (5, 2, false), (6, 1, false)] {
    let workspace = row_workspace(slots)
    let actual = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 2, },
      workspace,
    )
    if success {
      assert_true(actual is Ok(Number(-1.0)))
      assert_eq(workspace.peak, 2)
    } else if work < 6 {
      assert_true(actual is Err({ kind: ControlLimit, .. }))
    } else {
      assert_true(actual is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
}

///|
test "sign preserves exact semantic work and live root accounting" {
  // Three entries, three produced numeric scalar weights and two consumed
  // operands = eight work. The -9 and -1 intermediate/results need two bytes.
  let root = lowered("{\"sign\":{\"negate\":{\"literal\":9}}}")
  for
    (work, live, success) in [(8L, 2L, true), (7L, 2L, false), (8L, 1L, false)] {
    let logical = test_logical_budget(work, live)
    let workspace = row_workspace(2)
    let result = evaluate_expression_retained(
      root,
      {},
      [],
      { remaining: 100, max_frames: 2, },
      workspace,
      logical_work=Some(logical),
    )
    if success {
      guard result is Ok(value) else { fail("exact SIGN logical bounds") }
      assert_true(value.value is Number(-1.0))
      assert_eq((logical.work, logical.live, logical.peak), (8L, 2L, 2L))
      release_logical_root(logical, value.root.unwrap()).unwrap()
    } else if work < 8L {
      assert_true(
        result
        is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
      )
    } else {
      assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
    }
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "sign cancellation retains cumulative work and external root custody" {
  for stop in [1, 2, 3] {
    let logical = test_logical_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(100)
    let frame = expression_frame(
      lowered("{\"sign\":{\"literal\":9}}"),
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      Some(expression_roots(logical, 100)),
    ).unwrap()
    for _ in 0..<stop {
      assert_true(advance_expression_frame(frame).unwrap() is None)
    }
    let spent = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(logical.work, spent)
    assert_false(borrowed.released)
    assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
    release_logical_root(logical, borrowed).unwrap()
    assert_eq(logical.live, 0L)
  }
}
