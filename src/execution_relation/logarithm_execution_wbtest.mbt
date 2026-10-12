///|
fn math_log_number(
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
fn math_log_interval(
  result : Result[Value, ScalarIssue],
  lower : Double,
  upper : Double,
) -> Unit raise {
  match result {
    Ok(Number(actual)) => assert_true(actual > lower && actual < upper)
    _ => assert_true(false)
  }
}

///|
test "EXP finite exact identity and independently bounded irrational result" {
  math_log_number(unary(Exp, Number(0.0)), 1.0)
  math_log_number(unary(Exp, Number(-0.0)), 1.0)
  math_log_interval(unary(Exp, Number(1.0)), 2.71828182845904, 2.71828182845905)
  math_log_interval(
    unary(Exp, Number(-1.0)),
    0.36787944117144,
    0.36787944117145,
  )
}

///|
test "EXP returns zero on underflow and rejects overflow" {
  math_log_number(unary(Exp, Number(-746.0)), 0.0)
  math_log_number(unary(Exp, Number(-1.7976931348623157e308)), 0.0)
  math_log_number(unary(Exp, Number(-745.0)), 5.0e-324)
  assert_true(unary(Exp, Number(710.0)) is Err(ArithmeticFailure))
  assert_true(
    unary(Exp, Number(1.7976931348623157e308)) is Err(ArithmeticFailure),
  )
}

///|
test "LN LOG10 and binary LOG exact identities and independent intervals" {
  math_log_number(unary(Ln, Number(1.0)), 0.0)
  math_log_number(unary(Log10, Number(1.0)), 0.0)
  math_log_number(unary(Log10, Number(100.0)), 2.0)
  math_log_number(binary(Log, Number(8.0), Number(2.0)), 3.0)
  math_log_number(binary(Log, Number(1.0), Number(0.5)), 0.0)
  math_log_number(binary(Log, Number(0.5), Number(0.5)), 1.0)
  math_log_number(binary(Log, Number(0.25), Number(0.5)), 2.0)
  math_log_interval(unary(Ln, Number(2.0)), 0.69314718055994, 0.69314718055995)
  math_log_interval(
    unary(Log10, Number(2.0)),
    0.30102999566398,
    0.30102999566399,
  )
  math_log_interval(
    unary(Ln, Number(5.0e-324)),
    -744.44007192139,
    -744.44007192137,
  )
  math_log_interval(
    binary(Log, Number(2.0), Number(3.0)),
    0.63092975357145,
    0.63092975357146,
  )
  math_log_interval(
    binary(Log, Number(2.0), Number(1.0000000000000002)),
    3121657384082679.0,
    3121657384082681.0,
  )
}

///|
test "LN LOG10 and LOG reject nonpositive inputs and invalid bases" {
  for value in [0.0, -0.0, -1.0, -1.7976931348623157e308] {
    assert_true(unary(Ln, Number(value)) is Err(ArithmeticFailure))
    assert_true(unary(Log10, Number(value)) is Err(ArithmeticFailure))
    assert_true(
      binary(Log, Number(value), Number(2.0)) is Err(ArithmeticFailure),
    )
    assert_true(
      binary(Log, Number(2.0), Number(value)) is Err(ArithmeticFailure),
    )
  }
  assert_true(binary(Log, Number(2.0), Number(1.0)) is Err(ArithmeticFailure))
}

///|
test "Exponential and logarithmic scalar domains are finite Number or evaluated NULL" {
  let maximum = 1.7976931348623157e308
  let infinity = maximum * 2.0
  for op in [@lower.Exp, @lower.Ln, @lower.Log10] {
    assert_true(unary(op, Null) is Ok(Null))
    for
      value in [
        Text("1"),
        Boolean(true),
        Number(infinity),
        Number(-infinity),
        Number(infinity - infinity),
      ] {
      assert_true(unary(op, value) is Err(InvalidOperand))
    }
  }
  assert_true(binary(Log, Null, Number(-1.0)) is Ok(Null))
  assert_true(binary(Log, Number(-1.0), Null) is Ok(Null))
  assert_true(binary(Log, Null, Null) is Ok(Null))
  for
    value in [
      Text("1"),
      Boolean(true),
      Number(infinity),
      Number(-infinity),
      Number(infinity - infinity),
    ] {
    assert_true(binary(Log, value, Number(2.0)) is Err(InvalidOperand))
    assert_true(binary(Log, Number(2.0), value) is Err(InvalidOperand))
  }
}

///|
test "LOG evaluates both children before NULL and unary math preserves child errors" {
  for
    text in [
      "log(NULL, 1 / 0)", "log(1 / 0, NULL)", "exp(1 / 0)", "ln(1 / 0)", "log10(1 / 0)",
    ] {
    guard run_expr("\"" + text + "\"") is Err(issue) else {
      fail("Math suppressed a demanded child failure")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  guard run_expr("\"log(sqrt(-1), 1 / 0)\"") is Err(first) else {
    fail("LOG first failure missing")
  }
  assert_true(
    @lower.expression_body(first.expression) is @lower.Unary(@lower.Sqrt, _),
  )
  assert_true(run_expr("\"log(NULL, 1)\"") is Ok(Null))
  assert_true(run_expr("\"log(-1, NULL)\"") is Ok(Null))
  assert_true(run_expr("\"if(FALSE, ln(0), 7)\"") is Ok(Number(7.0)))
  assert_true(run_expr("\"coalesce(7, log(NULL, 1 / 0))\"") is Ok(Number(7.0)))
  guard run_expr("\"safe_divide(ln(0), 0)\"") is Err(issue) else {
    fail("SAFE swallowed LN child failure")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Ln, _),
  )
}

///|
test "Unary math retains exact existing control workspace and logical-root budgets" {
  for name in ["exp", "ln", "log10"] {
    let input = if name == "exp" { "0" } else { "1" }
    let expected = if name == "exp" { 1.0 } else { 0.0 }
    let root = lowered("{\"" + name + "\":{\"literal\":" + input + "}}")
    // Two entries, two results and one consumption, with one continuation slot.
    for
      (control, slots, work, live, success) in [
        (4, 1, 5L, 1L, true),
        (3, 1, 5L, 1L, false),
        (4, 0, 5L, 1L, false),
        (4, 1, 4L, 1L, false),
        (4, 1, 5L, 0L, false),
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
        assert_true(value.value is Number(actual) && actual == expected)
        assert_eq(
          (logical.work, logical.live, logical.peak, workspace.peak),
          (5L, 1L, 1L, 1),
        )
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else if control < 4 {
        assert_true(result is Err({ kind: ControlLimit, .. }))
      } else if slots < 1 {
        assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      } else if work < 5L {
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
}

///|
test "Unary math cancellation closes existing roots at every suspension" {
  for name in ["exp", "ln", "log10"] {
    for stop in 1..<4 {
      let logical = test_logical_budget(100L, 100L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(10)
      let frame = expression_frame(
        lowered("{\"" + name + "\":{\"literal\":1}}"),
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
}

///|
test "LOG reuses exact binary control workspace and logical-root budgets" {
  let root = lowered("{\"log\":[{\"literal\":8},{\"literal\":2}]}")
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
      assert_true(value.value is Number(3.0))
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
  // A nonintegral result requires more than two canonical wire bytes.
  // Preserve the original tight-cap counterexample; no limit is increased.
  let logical = test_logical_budget(8L, 2L)
  let workspace = row_workspace(1)
  let fractional = evaluate_expression_retained(
    lowered("{\"log\":[{\"literal\":2},{\"literal\":3}]}"),
    {},
    [],
    { remaining: 6, max_frames: 1, },
    workspace,
    logical_work=Some(logical),
  )
  assert_true(fractional is Err({ kind: LogicalValue(LiveValueLimit), .. }))
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "LOG cancellation retains borrowed custody and never refunds consumed work" {
  for stop in 1..<6 {
    let logical = test_logical_budget(100L, 100L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(10)
    let frame = expression_frame(
      lowered("{\"log\":[{\"literal\":2},{\"literal\":3}]}"),
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

///|
test "Finite math backend preparation visits each checked branch without evaluation" {
  for
    expression in [
      "pow(2, 3)", "pow(0, -1)", "exp(710)", "ln(0)", "log10(-1)", "log(8, 1)",
    ] {
    let request = capability_request(
      "[]",
      "{\"derive\":{\"value\":\"" + expression + "\"}}",
    )
    let roots = @lower.fragment_pipeline_roots(
      @lower.fragment_request_pipeline(request),
    )
    assert_true(check_backend_capabilities(roots, 100) is Ok(_))
    assert_true(
      check_backend_capabilities(roots, 0)
      is Err({ kind: PreparationLimit, .. }),
    )
  }
}

///|
test "Finite math composes with existing strict safe precision and substring owners" {
  for
    (source, expected) in [
      ("safe_add(pow(2, 3), round(1.235, 2))", 9.24),
      ("log(pow(2, 3), 2)", 3.0),
      ("exp(ln(1))", 1.0),
      ("if(starts_with(substring('abcdef', 2, 3), 'b'), pow(2, 3), ln(0))", 8.0),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Number(actual)) else {
      fail("existing scalar composition failed")
    }
    assert_eq(actual, expected)
  }
}
