///|
fn math_pow_number(
  result : Result[Value, ScalarIssue],
  expected : Double,
) -> Unit raise {
  match result {
    Ok(Number(actual)) => {
      assert_eq(actual, expected)
      if expected == 0.0 {
        assert_true(1.0 / actual > 0.0)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "POW finite Number exact powers and canonical zero" {
  for
    (base, exponent, expected) in [
      (2.0, 3.0, 8.0),
      (-2.0, 3.0, -8.0),
      (-2.0, 4.0, 16.0),
      (4.0, 0.5, 2.0),
      (2.0, -3.0, 0.125),
      (-2.0, -3.0, -0.125),
      (0.0, 0.0, 1.0),
      (-0.0, 0.0, 1.0),
      (0.0, 1.0, 0.0),
      (-0.0, 3.0, 0.0),
      (-0.0, 0.5, 0.0),
      (1.7976931348623157e308, 1.0, 1.7976931348623157e308),
    ] {
    math_pow_number(binary(Pow, Number(base), Number(exponent)), expected)
  }
}

///|
test "POW tests exponent integrality without narrowing to an integer" {
  for
    (exponent, expected) in [
      (9007199254740991.0, -1.0),
      (9007199254740992.0, 1.0),
      (9007199254740994.0, 1.0),
      (-9007199254740991.0, -1.0),
      (1.7976931348623157e308, 1.0),
      (-1.7976931348623157e308, 1.0),
    ] {
    math_pow_number(binary(Pow, Number(-1.0), Number(exponent)), expected)
  }
  for exponent in [0.5, -0.5, 4503599627370495.5, -4503599627370495.5] {
    assert_true(
      binary(Pow, Number(-2.0), Number(exponent)) is Err(ArithmeticFailure),
    )
  }
}

///|
test "POW preserves subnormals and returns zero for unrepresentable underflow" {
  math_pow_number(binary(Pow, Number(2.0), Number(-1074.0)), 5.0e-324)
  math_pow_number(binary(Pow, Number(2.0), Number(-1075.0)), 0.0)
  math_pow_number(binary(Pow, Number(-2.0), Number(-1075.0)), 0.0)
  math_pow_number(binary(Pow, Number(0.5), Number(1.7976931348623157e308)), 0.0)
  math_pow_number(binary(Pow, Number(1.0), Number(1.7976931348623157e308)), 1.0)
}

///|
test "POW rejects zero negative exponents and finite overflow" {
  for base in [0.0, -0.0] {
    for exponent in [-1.0, -0.5, -1.7976931348623157e308] {
      assert_true(
        binary(Pow, Number(base), Number(exponent)) is Err(ArithmeticFailure),
      )
    }
  }
  for
    (base, exponent) in [
      (2.0, 1024.0),
      (-2.0, 1025.0),
      (2.0, 1.7976931348623157e308),
    ] {
    assert_true(
      binary(Pow, Number(base), Number(exponent)) is Err(ArithmeticFailure),
    )
  }
}

///|
test "POW accepts evaluated nulls but refuses other operand domains" {
  assert_true(binary(Pow, Null, Number(-1.0)) is Ok(Null))
  assert_true(binary(Pow, Number(-1.0), Null) is Ok(Null))
  assert_true(binary(Pow, Null, Null) is Ok(Null))
  for value in [Text("2"), Boolean(true)] {
    assert_true(binary(Pow, value, Number(3.0)) is Err(InvalidOperand))
    assert_true(binary(Pow, Number(2.0), value) is Err(InvalidOperand))
  }
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for invalid in [infinity, -infinity, infinity - infinity] {
    assert_true(
      binary(Pow, Number(invalid), Number(0.0)) is Err(InvalidOperand),
    )
    assert_true(
      binary(Pow, Number(1.0), Number(invalid)) is Err(InvalidOperand),
    )
  }
}

///|
test "POW evaluates demanded children before NULL and preserves first failure ownership" {
  for args in ["NULL, 1 / 0", "1 / 0, NULL", "2, 1 / 0"] {
    guard run_expr("\"pow(" + args + ")\"") is Err(issue) else {
      fail("POW suppressed a demanded child failure")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"pow(sqrt(-1), 1 / 0)\"") is Err(first) else {
    fail("POW first failure missing")
  }
  assert_true(
    @lower.expression_body(first.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  assert_true(run_expr("\"if(FALSE, pow(0, -1), 7)\"") is Ok(Number(7.0)))
  assert_true(run_expr("\"coalesce(7, pow(NULL, 1 / 0))\"") is Ok(Number(7.0)))
  for text in ["safe_add(pow(0, -1), 1)", "safe_divide(pow(0, -1), 0)"] {
    guard run_expr("\"" + text + "\"") is Err(issue) else {
      fail("SAFE operation swallowed POW child failure")
    }
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Pow, _, _),
    )
  }
}

///|
test "POW reuses exact binary control workspace and logical-root budgets" {
  let root = lowered("{\"pow\":[{\"literal\":2},{\"literal\":3}]}")
  // Three entries, three results and two consumptions cost eight logical units.
  // The Left/Right continuation reuses one slot; two one-byte roots peak at two.
  for
    (control, slots, work, live, success) in [
      (6, 1, 8L, 2L, true),
      (5, 1, 8L, 2L, false),
      (6, 0, 8L, 2L, false),
      (6, 1, 7L, 2L, false),
      (6, 1, 8L, 1L, false),
    ] {
    let logical = test_logical_budget(work, live)
    let workspace = row_workspace(slots)
    let result = evaluate_expression_retained(
      root,
      {},
      [],
      { remaining: control, max_frames: 1, },
      workspace,
      logical_work=Some(logical),
    )
    if success {
      let value = result.unwrap()
      assert_true(value.value is Number(8.0))
      assert_eq(
        (logical.work, logical.live, logical.peak, workspace.peak),
        (8L, 1L, 2L, 1),
      )
      release_logical_root(logical, value.root.unwrap()).unwrap()
    } else if control < 6 {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    } else if slots < 1 {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
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
test "POW cancellation retains borrowed custody and never refunds consumed work" {
  for stop in 1..<6 {
    let logical = test_logical_budget(100L, 100L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(10)
    let frame = expression_frame(
      lowered("{\"pow\":[{\"literal\":2},{\"literal\":3}]}"),
      {},
      [],
      { remaining: 100, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
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
