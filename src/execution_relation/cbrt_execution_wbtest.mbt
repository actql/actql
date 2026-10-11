// Fixed independent decimal brackets. Their exact binary64 endpoint cubes enclose
// the exact binary64 input; no host Math or product output supplies expectations.

///|
test "cbrt finite positive and negative values satisfy independent cube brackets" {
  for
    (input, lower, upper) in [
      (2.0, 1.25992104989487, 1.25992104989488),
      (3.0, 1.44224957030740, 1.44224957030742),
      (10.0, 2.15443469003188, 2.15443469003189),
      (0.5, 0.79370052598409, 0.79370052598411),
      (27.0, 2.99999999999999, 3.00000000000001),
      (125.0, 4.99999999999999, 5.00000000000001),
      (5.0e-324, 1.70318393600325e-108, 1.70318393600327e-108),
      (2.225073858507201e-308, 2.81264428523625e-103, 2.81264428523628e-103),
      (2.2250738585072014e-308, 2.81264428523625e-103, 2.81264428523628e-103),
      (1.7976931348623157e308, 5.64380309412235e102, 5.64380309412238e102),
    ] {
    for (value, lo, hi) in [(input, lower, upper), (-input, -upper, -lower)] {
      guard unary(@lower.Cbrt, Number(value)) is Ok(Number(actual)) else {
        fail("finite cbrt failed")
      }
      assert_true(actual > lo && actual < hi)
    }
  }
}

///|
test "cbrt preserves exact power of two roots and canonicalizes both zero signs" {
  for
    (input, expected) in [
      (0.0, 0.0),
      (-0.0, 0.0),
      (1.0, 1.0),
      (-1.0, -1.0),
      (8.0, 2.0),
      (-8.0, -2.0),
      (0.125, 0.5),
      (-0.125, -0.5),
      (64.0, 4.0),
    ] {
    guard unary(@lower.Cbrt, Number(input)) is Ok(Number(actual)) else {
      fail("cbrt exact identity failed")
    }
    assert_eq(actual.reinterpret_as_uint64(), expected.reinterpret_as_uint64())
  }
  assert_true(unary(@lower.Cbrt, Null) is Ok(Null))
  let inf = 1.7976931348623157e308 * 2.0
  for
    value in [
      Number(inf),
      Number(-inf),
      Number(inf - inf),
      Text("8"),
      Boolean(true),
    ] {
    assert_true(unary(@lower.Cbrt, value) is Err(InvalidOperand))
  }
  assert_true(
    unary(
      @lower.Cbrt,
      Captured(@admitted.decimal_from_coefficient("8", 8, 0).unwrap()),
    )
    is Err(InvalidOperand),
  )
}

///|
test "cbrt preserves demanded errors and outer lazy branch selection" {
  for
    source in [
      "cbrt(1 / 0)", "safe_divide(cbrt(1 / 0),0)", "greatest(NULL,cbrt(1 / 0))",
      "coalesce(NULL,cbrt(1 / 0))",
    ] {
    guard run_expr("\"" + source + "\"") is Err(issue) else {
      fail("cbrt suppressed child failure")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  for source in ["if(FALSE,cbrt(1 / 0),7)", "coalesce(7,cbrt(1 / 0))"] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Number(7.0)))
  }
  assert_true(run_expr("\"cbrt(if(TRUE,-8,1 / 0))\"") is Ok(Number(-2.0)))
  assert_true(run_expr("\"cbrt(NULL)\"") is Ok(Null))
}

///|
test "cbrt uses exact unary work workspace live root and control boundaries" {
  let root = lowered("{\"cbrt\":{\"literal\":8}}")
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
      assert_true(value.value is Number(2.0))
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
  assert_true(
    evaluate_expression(root, {}, [], { remaining: 4, max_frames: 0, })
    is Err({ kind: ControlLimit, .. }),
  )
  let logical = test_logical_budget(5L, 1L)
  let workspace = row_workspace(1)
  let fractional = evaluate_expression_retained(
    lowered("{\"cbrt\":{\"literal\":2}}"),
    {},
    [],
    { remaining: 4, max_frames: 1, },
    workspace,
    logical_work=Some(logical),
  )
  assert_true(fractional is Err({ kind: LogicalValue(LiveValueLimit), .. }))
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "cbrt evaluates its computed operand exactly once" {
  let root = lowered("{\"cbrt\":{\"negate\":{\"literal\":8}}}")
  for work in [5, 6] {
    let workspace = row_workspace(2)
    let result = evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: work, max_frames: 2, },
      workspace,
    )
    if work == 6 {
      assert_true(result is Ok(Number(-2.0)))
      assert_eq(workspace.peak, 2)
    } else {
      assert_true(result is Err({ kind: ControlLimit, .. }))
    }
    assert_eq(workspace.live, 0)
  }
}

///|
test "cbrt cancellation retains borrowed roots and never refunds work" {
  for stop in 1..<4 {
    let logical = test_logical_budget(100L, 100L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let workspace = row_workspace(10)
    let frame = expression_frame(
      lowered("{\"cbrt\":{\"literal\":8}}"),
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
test "cbrt backend preparation visits checked branches without evaluating children" {
  for expression in ["cbrt(-8)", "cbrt(1 / 0)", "if(FALSE,cbrt(1 / 0),7)"] {
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
